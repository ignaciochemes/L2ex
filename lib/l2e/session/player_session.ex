defmodule L2E.Session.PlayerSession do
  @moduledoc """
  One GenServer per online player.

  Owns:
  - Authentication state machine
  - Character position, heading, stats
  - Reference to the ConnectionHandler pid (for outbound packets)
  - Reference to the Region pid (current grid cell)

  All mutable player state lives here exclusively.
  External processes communicate only via message passing.

  Crash semantics: restart: :temporary — do NOT auto-restart.
  The client must reconnect and re-authenticate.
  """

  use GenServer, restart: :temporary
  require Logger

  import Ecto.Query, only: [from: 2]

  alias L2E.{Repo, DB.Account, DB.Character, DB.Item}
  alias L2E.Packet.Server
  alias L2E.Packet.Client
  alias L2E.World.Region
  alias L2E.Game.{ClassTemplates, Stats}
  alias L2E.Combat.Resolver
  alias L2E.Inventory
  alias L2E.Inventory.Supervisor, as: InventorySupervisor
  alias L2E.Item.TemplateTable, as: ItemTemplateTable
  alias L2E.Skill.{TemplateTable, BuffInfo, Effect}
  alias L2E.Party
  alias L2E.Clan
  alias L2E.Data.BuyListTable
  alias L2E.Data.TeleporterTable
  alias L2E.Warehouse
  alias L2E.Trade
  alias L2E.Data.EnchantData
  alias L2E.Zone.ZoneTable
  alias L2E.Data.SkillLearnTable
  alias L2E.Data.ClassAdvancementTable
  alias L2E.Data.ExperienceLossData
  alias L2E.Data.MultisellTable
  alias L2E.DB.CharacterSkill
  alias L2E.DB.CharacterQuest
  alias L2E.DB.CharacterShortcut
  alias L2E.DB.CharacterFriend
  alias L2E.DB.CharacterMacro
  alias L2E.DB.CharacterSubclass
  alias L2E.Duel.Manager, as: DuelManager
  alias L2E.Olympiad.Manager, as: OlympiadManager
  alias L2E.Siege.Manager, as: SiegeManager
  alias L2E.Pet.Supervisor, as: PetSupervisor

  # Respawn delay after death (ms)
  @respawn_ms 30_000

  @type auth_state :: :protocol_ok | :authenticated | :char_selected | :in_world

  @type t :: %{
          conn_pid: pid(),
          auth_state: auth_state(),
          char_id: pos_integer() | nil,
          char_name: String.t() | nil,
          char_db_id: pos_integer() | nil,
          username: String.t() | nil,
          position: {integer(), integer(), integer()},
          heading: non_neg_integer(),
          region_pid: pid() | nil,
          hp: float(),
          max_hp: float(),
          mp: float(),
          max_mp: float()
        }

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(conn_pid: conn_pid) do
    GenServer.start_link(__MODULE__, conn_pid)
  end

  @doc "Send a server packet to this player's client."
  def send_packet(session_pid, packet) do
    GenServer.cast(session_pid, {:send_packet, packet})
  end

  @doc "Get the current quest state for quest_id. Returns a map with :state, :cond, :count, :reward_taken."
  def get_quest_state(pid, quest_id), do: GenServer.call(pid, {:get_quest_state, quest_id})

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(conn_pid) do
    Process.monitor(conn_pid)

    state = %{
      conn_pid: conn_pid,
      auth_state: :protocol_ok,
      char_id: nil,
      char_name: nil,
      char_db_id: nil,
      username: nil,
      class_id: nil,
      level: 1,
      position: {0, 0, 0},
      heading: 0,
      region_pid: nil,
      hp: 100.0,
      max_hp: 100.0,
      mp: 100.0,
      max_mp: 100.0,
      cp: 100.0,
      max_cp: 100.0,
      exp: 0,
      sp: 0,
      # Derived stats (map computed by Stats.compute/2)
      stats: nil,
      # Combat state
      target_id: nil,
      attacking: false,
      attack_timer: nil,
      dead: false,
      # Skill state
      # %{skill_id => level}
      skills: %{},
      # [BuffInfo.t()]
      buffs: [],
      # %{skill_id => expires_monotonic_ms}
      cooldowns: %{},
      casting: false,
      cast_timer: nil,
      # Party / Clan state
      party_pid: nil,
      clan_pid: nil,
      # Pending party invite: {party_pid, invitor_name} — awaiting our answer
      pending_party_invite: nil,
      # Pending clan invite: {clan_pid, clan_name} — awaiting our answer
      pending_clan_invite: nil,
      # Active trade process (nil if not in a trade)
      trade_pid: nil,
      # Pending incoming trade request: {from_char_id, from_pid, trade_pid}
      pending_trade: nil,
      # Active enchant scroll object_id (nil if no enchant dialog open)
      enchant_scroll_id: nil,
      # Current zone type at player's position (:normal | :peace | :pvp | :siege | :no_pvp | :damage | :water | :swamp | :boss | :other)
      zone_type: :normal,
      # M55-B: Zone damage tick timer ref
      zone_damage_timer: nil,
      # M55-B: Water/swim state
      in_water: false,
      # PvP state
      pvp_flag: 0,
      karma: 0,
      pvp_kills: 0,
      pk_kills: 0,
      pvp_flag_timer: nil,
      # Regen tick timer (3-second interval when alive)
      regen_timer: nil,
      # Auto-save timer (5-minute interval)
      save_timer: nil,
      # M39: Auto soulshot item_id (nil = disabled)
      autoshot_item_id: nil,
      # M35: Private store
      private_store_type: :none,
      private_store_list: [],
      private_store_title: "",
      # M43: Buy store
      buy_store_list: [],
      # M42: GM access level (0 = normal player, >0 = GM)
      access_level: 0,
      # M42: GM invisibility toggle
      invisible: false,
      # M36: Tracks which warehouse context the player has open (:personal | :clan)
      warehouse_context: :personal,
      # M47: Quest state map — %{quest_id => %{state: 0|1|2, cond: int, count: int, reward_taken: bool}}
      quests: %{},
      # M49: Crowd-control flags — %{:stunned | :rooted | :sleeping | :paralyzed | :silenced => timer_ref}
      cc_state: %{},
      # M49: Active DoT timers — %{skill_id => timer_ref}
      dots: %{},
      # M49: Charge count (Gladiator Momentum, etc.)
      charge_count: 0,
      # M49: Active toggle skills — %{skill_id => timer_ref}
      toggle_skills: %{},
      # M49-B: Speed debuff state
      slowed: false,
      slow_timer: nil,
      # M49-B: Silence state
      silenced: false,
      silence_timer: nil,
      # M49-B: Stat modifier buffs/debuffs (list of %{skill_id, stat, type, value, timer})
      stat_mods: [],
      # M54: Shortcut bar — list of %{slot, page, type, shortcut_id, level}
      shortcuts: [],
      # M56: Henna/tattoo slots — %{1..3 => henna_id | nil}
      hennas: %{1 => nil, 2 => nil, 3 => nil},
      # M61: Movement state
      is_running: true,
      is_sitting: false,
      # M66: Friend system
      friends_loaded: false,
      # M74-A: Macros
      macros: [],
      # M68: Sub-class system
      subclasses: [],
      active_subclass: nil,
      # M69: Duel state
      pending_duel: nil,
      active_duel_id: nil,
      # M72: Pet
      pet_pid: nil,
      pet_item_obj_id: nil,
      # M70-B / M73: Olympiad match state
      olympiad_match_pid: nil,
      olympiad_return_pos: nil,
      # M80: Pending dialog confirmation state — {:enchant_confirm, item_oid, scroll_oid} | nil
      pending_dialog: nil,
      # M81: Block list — MapSet of blocked player names
      block_list: MapSet.new()
    }

    {:ok, state}
  end

  # -----------------------------------------------------------------------
  # Inbound packets from ConnectionHandler
  # -----------------------------------------------------------------------

  @impl true
  def handle_cast({:packet, packet}, state) do
    handle_packet(packet, state)
  end

  # Outbound packet — forward to ConnectionHandler for encoding + send
  def handle_cast({:send_packet, packet}, state) do
    send(state.conn_pid, {:send_packet, packet})
    {:noreply, state}
  end

  # Connection closed by handler
  def handle_cast(:connection_closed, state) do
    Logger.info("[PlayerSession] Connection closed for char=#{state.char_name}")
    persist_position(state)
    stop_inventory(state)
    leave_region(state)
    {:stop, :normal, state}
  end

  # Player receives damage from NPC
  def handle_cast({:take_damage, amount, from_pid}, %{dead: false} = state) do
    new_hp = max(0.0, state.hp - amount)
    new_state = %{state | hp: new_hp}

    hp_update = Server.StatusUpdate.hp_mp(state.char_id, new_hp, state.mp)
    send(state.conn_pid, {:send_packet, hp_update})

    # Broadcast vitals update to party window
    if state.party_pid, do: Party.vital_update(state.party_pid, state.char_id, new_hp, state.mp)

    # Flag attacker if they are another player
    if is_pid(from_pid) and player_pid?(from_pid) do
      GenServer.cast(from_pid, :set_pvp_flag)
    end

    if new_hp <= 0 do
      Logger.info("[PlayerSession] #{state.char_name} died")
      die_pkt = %Server.Die{object_id: state.char_id, can_sweep: false}
      send(state.conn_pid, {:send_packet, die_pkt})
      if state.region_pid, do: GenServer.cast(state.region_pid, {:broadcast_packet, die_pkt})
      cancel_timer(state.attack_timer)
      cancel_timer(state.regen_timer)

      # Notify killer about PvP/PK outcome
      if is_pid(from_pid) and player_pid?(from_pid) do
        GenServer.cast(
          from_pid,
          {:player_killed, self(), state.pvp_flag, state.karma, state.level}
        )
      end

      maybe_drop_karma_items(state)
      Process.send_after(self(), :respawn, @respawn_ms)

      # XP loss on death (Interlude rules: % of XP within current level)
      exp_loss = ExperienceLossData.calculate_exp_loss(state.exp, state.level)
      level_floor_xp = L2E.Data.ExperienceTable.get_xp_for_level(state.level)
      new_exp = max(state.exp - exp_loss, level_floor_xp)

      if exp_loss > 0 and state.char_db_id do
        Repo.update_all(
          from(c in Character, where: c.id == ^state.char_db_id),
          set: [exp: new_exp]
        )

        send(
          state.conn_pid,
          {:send_packet,
           %Server.StatusUpdate{
             object_id: state.char_id,
             attributes: [{Server.StatusUpdate.attr_exp(), new_exp}]
           }}
        )

        Logger.info(
          "[PlayerSession] #{state.char_name} lost #{exp_loss} EXP on death (level #{state.level})"
        )
      end

      {:noreply,
       %{
         new_state
         | dead: true,
           attacking: false,
           attack_timer: nil,
           regen_timer: nil,
           exp: new_exp
       }}
    else
      {:noreply, new_state}
    end
  end

  def handle_cast({:take_damage, _amount, _from_pid}, state), do: {:noreply, state}

  # Attacker receives a PvP flag from hitting another player
  def handle_cast(:set_pvp_flag, state) do
    cancel_timer(state.pvp_flag_timer)
    timer = Process.send_after(self(), :clear_pvp_flag, 60_000)
    new_state = %{state | pvp_flag: 1, pvp_flag_timer: timer}
    broadcast_user_info(new_state)
    {:noreply, new_state}
  end

  # Notification that we killed another player
  def handle_cast(
        {:player_killed, _victim_pid, victim_pvp_flag, victim_karma, victim_level},
        state
      ) do
    new_state =
      cond do
        # Victim had karma (was a PK) — no karma gain, no PvP kill count
        victim_karma > 0 ->
          # Reduce victim karma is handled on victim side; nothing extra here
          state

        # Victim was PvP flagged — mutual fight, count as PvP kill
        victim_pvp_flag > 0 ->
          new_pvp = state.pvp_kills + 1

          if state.char_db_id do
            Repo.update_all(
              from(c in Character, where: c.id == ^state.char_db_id),
              set: [pvp_kills: new_pvp]
            )
          end

          %{state | pvp_kills: new_pvp}

        # Victim was innocent — this is a PK
        true ->
          new_karma = state.karma + victim_level * 9
          new_pk = state.pk_kills + 1

          if state.char_db_id do
            Repo.update_all(
              from(c in Character, where: c.id == ^state.char_db_id),
              set: [karma: new_karma, pk_kills: new_pk]
            )
          end

          new_s = %{state | karma: new_karma, pk_kills: new_pk}
          broadcast_user_info(new_s)
          new_s
      end

    {:noreply, new_state}
  end

  # NPC dropped items go directly into the killer's inventory
  def handle_cast({:receive_drops, drops}, %{auth_state: :in_world} = state) do
    Enum.each(drops, fn {item_id, count} ->
      case Inventory.add_item(state.char_id, item_id, count) do
        {:ok, change_type, {instance, template}} ->
          change_int = change_type_to_int(change_type)
          pkt = %Server.InventoryUpdate{changes: [{change_int, instance, template}]}
          send(state.conn_pid, {:send_packet, pkt})

        {:error, reason} ->
          Logger.warning(
            "[PlayerSession] Failed to add dropped item #{item_id}: #{inspect(reason)}"
          )
      end
    end)

    {:noreply, state}
  end

  def handle_cast({:receive_drops, _drops}, state), do: {:noreply, state}

  # NPC killed by this player — grant EXP and SP, check level-up
  def handle_cast({:receive_xp_sp, _exp, _sp}, %{auth_state: auth} = state)
      when auth != :in_world,
      do: {:noreply, state}

  def handle_cast({:receive_xp_sp, exp, sp}, state) do
    new_exp = state.exp + exp
    new_sp = state.sp + sp

    # Check level up
    next_level_xp = Stats.xp_to_next_level(state.level + 1)

    {new_level, new_state} =
      if next_level_xp != :infinity and new_exp >= next_level_xp do
        lvl = state.level + 1
        template = ClassTemplates.get_or_default(state.class_id)
        derived = Stats.compute(template, lvl)
        bonuses = Inventory.get_equip_bonuses(state.char_id)
        new_stats = Stats.apply_equipment(derived, bonuses) |> Stats.apply_buffs(state.buffs)

        new_hp = new_stats.max_hp * 1.0
        new_mp = new_stats.max_mp * 1.0

        level_up_pkt = %Server.SocialAction{object_id: state.char_id, action_id: 2316}

        if state.region_pid,
          do: GenServer.cast(state.region_pid, {:broadcast_packet, level_up_pkt})

        send(state.conn_pid, {:send_packet, level_up_pkt})

        user_info = %Server.UserInfo{
          char_id: state.char_id,
          char_name: state.char_name,
          x: elem(state.position, 0),
          y: elem(state.position, 1),
          z: elem(state.position, 2),
          heading: state.heading,
          hp: trunc(new_hp),
          max_hp: new_stats.max_hp,
          pvp_flag: state.pvp_flag,
          karma: state.karma
        }

        send(state.conn_pid, {:send_packet, user_info})

        Logger.info("[PlayerSession] #{state.char_name} leveled up to #{lvl}!")

        {lvl,
         %{
           state
           | level: lvl,
             stats: new_stats,
             max_hp: new_hp,
             max_mp: new_mp,
             max_cp: new_stats.max_cp * 1.0,
             hp: new_hp,
             mp: new_mp,
             cp: new_stats.max_cp * 1.0
         }}
      else
        {state.level, state}
      end

    final_state = %{new_state | exp: new_exp, sp: new_sp, level: new_level}

    # Send XP/SP + level update to client via StatusUpdate
    xp_update = %Server.StatusUpdate{
      object_id: state.char_id,
      attributes: [
        {Server.StatusUpdate.attr_exp(), new_exp},
        {Server.StatusUpdate.attr_sp(), new_sp},
        {Server.StatusUpdate.attr_level(), new_level}
      ]
    }

    send(state.conn_pid, {:send_packet, xp_update})

    # Persist to DB
    if db_id = state.char_db_id do
      Repo.update_all(
        from(c in Character, where: c.id == ^db_id),
        set: [exp: new_exp, sp: new_sp, level: new_level]
      )
    end

    {:noreply, final_state}
  end

  # M35: Seller is notified that a buyer purchased items from their store
  def handle_cast({:store_items_sold, sold_items, _total_cost}, state) do
    # Remove sold items from store list
    sold_obj_ids = MapSet.new(sold_items, & &1.object_id)

    new_store_list =
      Enum.reject(state.private_store_list, fn entry ->
        MapSet.member?(sold_obj_ids, entry.object_id)
      end)

    new_state =
      if new_store_list == [] do
        %{state | private_store_list: [], private_store_type: :none}
      else
        %{state | private_store_list: new_store_list}
      end

    {:noreply, new_state}
  end

  # M43: Buy store owner's session notifies seller about a completed purchase.
  # Seller loses items, gains adena, receives inventory update packets.
  def handle_cast({:buy_store_sold, validated_items, total_adena}, state) do
    # Add adena to seller
    case Inventory.add_item(state.char_id, 57, total_adena) do
      {:ok, change_type, {instance, template}} ->
        pkt = %Server.InventoryUpdate{
          changes: [{change_type_to_int(change_type), instance, template}]
        }

        send(state.conn_pid, {:send_packet, pkt})

      _ ->
        :ok
    end

    # Remove each sold item and send inventory update
    Enum.each(validated_items, fn %{object_id: obj_id, count: count} ->
      case Inventory.remove_item(state.char_id, obj_id, count) do
        {:ok, change_type, {instance, template}} ->
          pkt = %Server.InventoryUpdate{
            changes: [{change_type_to_int(change_type), instance, template}]
          }

          send(state.conn_pid, {:send_packet, pkt})

        _ ->
          :ok
      end
    end)

    {:noreply, state}
  end

  # M47: External systems (NPC kill events, item handlers) push quest progress updates
  def handle_cast({:quest_progress, quest_id, cond, count}, state) do
    updated =
      Map.update(
        state.quests,
        quest_id,
        %{state: 1, cond: cond, count: count, reward_taken: false},
        fn q -> %{q | cond: cond, count: count} end
      )

    L2E.DB.CharacterQuest.set_quest_state(state.char_id, quest_id, 1, cond, count)
    {:noreply, %{state | quests: updated}}
  end

  # M47: Mark a quest as completed
  def handle_cast({:quest_complete, quest_id}, state) do
    updated =
      Map.update(
        state.quests,
        quest_id,
        %{state: 2, cond: 0, count: 0, reward_taken: false},
        fn q -> %{q | state: 2} end
      )

    L2E.DB.CharacterQuest.complete_quest(state.char_id, quest_id)
    {:noreply, %{state | quests: updated}}
  end

  # M50: NPC kill event for quest system
  def handle_cast({:npc_killed_for_quest, npc_template_id}, %{auth_state: :in_world} = state) do
    player_info = %{
      char_id: state.char_id,
      level: state.level,
      class_id: state.class_id
    }

    new_quests = L2E.Quest.Handler.dispatch_kill(npc_template_id, player_info, state.quests)

    Enum.each(new_quests, fn {quest_id, q_state} ->
      if Map.get(state.quests, quest_id) != q_state do
        L2E.DB.CharacterQuest.set_quest_state(
          state.char_id,
          quest_id,
          q_state.state,
          q_state.cond,
          q_state.count
        )
      end
    end)

    {:noreply, %{state | quests: new_quests}}
  end

  def handle_cast({:npc_killed_for_quest, _}, state), do: {:noreply, state}

  # M49: Apply crowd control to this player
  def handle_cast({:apply_cc, cc_type, duration_ms}, state)
      when cc_type in [:stunned, :rooted, :sleeping, :paralyzed, :silenced] do
    if ref = Map.get(state.cc_state, cc_type), do: Process.cancel_timer(ref)
    timer = Process.send_after(self(), {:cc_expired, cc_type}, duration_ms)
    {:noreply, %{state | cc_state: Map.put(state.cc_state, cc_type, timer)}}
  end

  # M49: Apply DoT to this player
  def handle_cast({:apply_dot, skill_id, _level, damage_per_tick, tick_ms, ticks_left}, state) do
    if ref = Map.get(state.dots, skill_id), do: Process.cancel_timer(ref)

    timer =
      Process.send_after(
        self(),
        {:dot_tick, skill_id, damage_per_tick, tick_ms, ticks_left},
        tick_ms
      )

    {:noreply, %{state | dots: Map.put(state.dots, skill_id, timer)}}
  end

  # -----------------------------------------------------------------------
  # AOI broadcasts from Region
  # -----------------------------------------------------------------------

  @impl true
  def handle_info({:broadcast, :player_entered, info}, state) do
    packet = %Server.CharInfo{
      char_id: info.char_id,
      char_name: info.char_name,
      x: elem(info.position, 0),
      y: elem(info.position, 1),
      z: elem(info.position, 2),
      heading: info.heading
    }

    send(state.conn_pid, {:send_packet, packet})
    {:noreply, state}
  end

  def handle_info({:broadcast, :player_moved, info}, state) do
    {ox, oy, oz} = info.origin
    {x, y, z} = info.position

    packet = %Server.CharMoveToLocation{
      char_id: info.char_id,
      x: x,
      y: y,
      z: z,
      origin_x: ox,
      origin_y: oy,
      origin_z: oz
    }

    send(state.conn_pid, {:send_packet, packet})
    {:noreply, state}
  end

  def handle_info({:broadcast, :player_left, char_id}, state) do
    Logger.debug("[PlayerSession] #{char_id} left AOI")
    {:noreply, state}
  end

  # -----------------------------------------------------------------------
  # Combat events
  # -----------------------------------------------------------------------

  # Auto-attack tick — fire one hit against current target
  def handle_info(:auto_attack_tick, %{attacking: true, target_id: target_id} = state)
      when not is_nil(target_id) do
    case find_npc_pid(target_id) do
      nil ->
        # Not an NPC — check if it's another player (PvP)
        case find_player_pid(target_id) do
          nil ->
            {:noreply, %{state | attacking: false, attack_timer: nil, target_id: nil}}

          player_pid ->
            my_stats = consume_shot_and_boost(state, player_combat_stats(state))

            {:ok, _target_char_id, target_stats, target_pos} =
              GenServer.call(player_pid, :get_combat_stats)

            {damage, result} = Resolver.resolve_hit(my_stats, target_stats)

            attack_pkt = %Server.Attack{
              attacker_id: state.char_id,
              attacker_x: elem(state.position, 0),
              attacker_y: elem(state.position, 1),
              attacker_z: elem(state.position, 2),
              target_id: target_id,
              damage: damage,
              miss: result == :miss,
              crit: result == :crit,
              target_x: elem(target_pos, 0),
              target_y: elem(target_pos, 1),
              target_z: elem(target_pos, 2)
            }

            if state.region_pid,
              do: GenServer.cast(state.region_pid, {:broadcast_packet, attack_pkt})

            GenServer.cast(player_pid, {:take_damage, damage, self()})
            timer = schedule_attack(state)
            {:noreply, %{state | attack_timer: timer}}
        end

      npc_pid ->
        npc_stats = L2E.NPC.Instance.get_stats(npc_pid)
        my_stats = consume_shot_and_boost(state, player_combat_stats(state))
        {damage, result} = Resolver.resolve_hit(my_stats, npc_stats)

        # Broadcast Attack packet to region
        npc_info = L2E.NPC.Instance.get_info(npc_pid)

        attack_pkt = %Server.Attack{
          attacker_id: state.char_id,
          attacker_x: elem(state.position, 0),
          attacker_y: elem(state.position, 1),
          attacker_z: elem(state.position, 2),
          target_id: target_id,
          damage: damage,
          miss: result == :miss,
          crit: result == :crit,
          target_x: elem(npc_info.position, 0),
          target_y: elem(npc_info.position, 1),
          target_z: elem(npc_info.position, 2)
        }

        if state.region_pid, do: GenServer.cast(state.region_pid, {:broadcast_packet, attack_pkt})

        # Tell NPC to take damage
        L2E.NPC.Instance.take_damage(npc_pid, damage, self())

        # Schedule next tick
        timer = schedule_attack(state)
        {:noreply, %{state | attack_timer: timer}}
    end
  end

  def handle_info(:auto_attack_tick, state) do
    {:noreply, %{state | attacking: false, attack_timer: nil}}
  end

  # Player respawns at bind point / starting area
  def handle_info(:respawn, state) do
    template = ClassTemplates.get_or_default(state.class_id)
    derived = Stats.compute(template, state.level)
    new_hp = derived.max_hp * 1.0
    new_mp = derived.max_mp * 1.0

    regen_timer = Process.send_after(self(), :regen_tick, 3_000)
    new_state = %{state | dead: false, hp: new_hp, mp: new_mp, regen_timer: regen_timer}

    revive_pkt = %Server.Revive{object_id: state.char_id}
    send(state.conn_pid, {:send_packet, revive_pkt})
    hp_update = Server.StatusUpdate.hp_mp(state.char_id, new_hp, new_mp)
    send(state.conn_pid, {:send_packet, hp_update})

    Logger.info("[PlayerSession] #{state.char_name} respawned")
    {:noreply, new_state}
  end

  # HP/MP regeneration tick (3-second interval)
  def handle_info(:regen_tick, %{dead: false, auth_state: :in_world} = state) do
    template = ClassTemplates.get_or_default(state.class_id)

    hp_regen = Stats.hp_regen(template, state.level)
    mp_regen = Stats.mp_regen(template, state.level)

    new_hp = min(state.max_hp, state.hp + hp_regen)
    new_mp = min(state.max_mp, state.mp + mp_regen)

    timer = Process.send_after(self(), :regen_tick, 3_000)

    if new_hp != state.hp or new_mp != state.mp do
      hp_update = Server.StatusUpdate.hp_mp(state.char_id, new_hp, new_mp)
      send(state.conn_pid, {:send_packet, hp_update})

      if state.party_pid,
        do: Party.vital_update(state.party_pid, state.char_id, new_hp, new_mp)
    end

    {:noreply, %{state | hp: new_hp, mp: new_mp, regen_timer: timer}}
  end

  def handle_info(:regen_tick, state) do
    timer = unless state.dead, do: Process.send_after(self(), :regen_tick, 3_000)
    {:noreply, %{state | regen_timer: timer}}
  end

  # Auto-save player position + vitals to DB every 5 minutes
  def handle_info(:auto_save, %{auth_state: :in_world} = state) do
    persist_position(state)
    timer = Process.send_after(self(), :auto_save, 300_000)
    {:noreply, %{state | save_timer: timer}}
  end

  def handle_info(:auto_save, state) do
    timer = Process.send_after(self(), :auto_save, 300_000)
    {:noreply, %{state | save_timer: timer}}
  end

  # Clear PvP flag after 60 seconds of no combat
  def handle_info(:clear_pvp_flag, state) do
    new_state = %{state | pvp_flag: 0, pvp_flag_timer: nil}
    broadcast_user_info(new_state)
    {:noreply, new_state}
  end

  # ConnectionHandler process died — shut down cleanly
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{conn_pid: pid} = state) do
    Logger.info("[PlayerSession] Connection process down (#{inspect(reason)}), stopping")
    persist_position(state)
    stop_inventory(state)
    leave_region(state)
    {:stop, :normal, state}
  end

  # Skill cast completes — apply effect
  def handle_info({:cast_complete, skill_id, level, target_id}, state) do
    case TemplateTable.get(skill_id, level) do
      nil ->
        {:noreply, %{state | casting: false, cast_timer: nil}}

      template ->
        launched_pkt = %Server.MagicSkillLaunched{
          caster_id: state.char_id,
          skill_id: skill_id,
          skill_level: level,
          target_ids: [target_id]
        }

        if state.region_pid,
          do: GenServer.cast(state.region_pid, {:broadcast_packet, launched_pkt})

        send(state.conn_pid, {:send_packet, launched_pkt})

        now_ms = System.monotonic_time(:millisecond)
        new_cooldowns = Map.put(state.cooldowns, skill_id, now_ms + template.reuse_ms)
        new_mp = max(0.0, state.mp - template.mp_cost)

        new_state =
          case template.effect_type do
            :heal ->
              my_stats = player_combat_stats(state)
              healed = Effect.apply_heal(my_stats, template.power)
              new_hp = min(state.hp + healed, state.max_hp)

              send(
                state.conn_pid,
                {:send_packet, Server.StatusUpdate.hp_mp(state.char_id, new_hp, new_mp)}
              )

              %{
                state
                | hp: new_hp,
                  mp: new_mp,
                  cooldowns: new_cooldowns,
                  casting: false,
                  cast_timer: nil
              }

            :m_damage ->
              caster_stats = player_combat_stats(state)
              target_state = get_target_stats(target_id, state)
              damage = Effect.apply_magic_damage(caster_stats, target_state, template.power)
              deal_damage_to_target(target_id, damage, state)

              send(
                state.conn_pid,
                {:send_packet, Server.StatusUpdate.hp_mp(state.char_id, state.hp, new_mp)}
              )

              %{state | mp: new_mp, cooldowns: new_cooldowns, casting: false, cast_timer: nil}

            :p_damage ->
              caster_stats = player_combat_stats(state)
              target_state = get_target_stats(target_id, state)
              damage = Effect.apply_physical_damage(caster_stats, target_state, template.power)
              deal_damage_to_target(target_id, damage, state)

              send(
                state.conn_pid,
                {:send_packet, Server.StatusUpdate.hp_mp(state.char_id, state.hp, new_mp)}
              )

              %{state | mp: new_mp, cooldowns: new_cooldowns, casting: false, cast_timer: nil}

            type when type in [:buff, :debuff] ->
              buff = %BuffInfo{
                skill_id: skill_id,
                level: level,
                skill_name: template.name,
                caster_id: state.char_id,
                start_monotonic: now_ms,
                duration_ms: template.buff_duration_ms,
                stat_bonus: template.stat_bonus
              }

              new_buffs = [buff | Enum.reject(state.buffs, &(&1.skill_id == skill_id))]
              buffed_stats = Stats.apply_buffs(state.stats, new_buffs)

              Process.send_after(self(), {:buff_expired, skill_id}, template.buff_duration_ms)

              abn_pkt = %Server.AbnormalStatusUpdate{effects: new_buffs}
              send(state.conn_pid, {:send_packet, abn_pkt})

              send(
                state.conn_pid,
                {:send_packet, Server.StatusUpdate.hp_mp(state.char_id, state.hp, new_mp)}
              )

              %{
                state
                | buffs: new_buffs,
                  stats: buffed_stats,
                  mp: new_mp,
                  cooldowns: new_cooldowns,
                  casting: false,
                  cast_timer: nil
              }

            :stun ->
              caster_stats = player_combat_stats(state)
              target_stats = get_target_stats(target_id, state)

              if Effect.check_cc_lands?(caster_stats, target_stats) do
                apply_cc_to_target(target_id, :stunned, template.buff_duration_ms, state)
              end

              %{state | mp: new_mp, cooldowns: new_cooldowns, casting: false, cast_timer: nil}

            :root ->
              caster_stats = player_combat_stats(state)
              target_stats = get_target_stats(target_id, state)

              if Effect.check_cc_lands?(caster_stats, target_stats) do
                apply_cc_to_target(target_id, :rooted, template.buff_duration_ms, state)
              end

              %{state | mp: new_mp, cooldowns: new_cooldowns, casting: false, cast_timer: nil}

            :dot_hp ->
              caster_stats = player_combat_stats(state)
              tick_ms = Map.get(template.stat_bonus, :tick_ms, 3_000)
              tick_count = Map.get(template.stat_bonus, :tick_count, 10)
              damage_per_tick = Effect.dot_tick_damage(caster_stats, template.power)

              apply_dot_to_target(
                target_id,
                skill_id,
                level,
                damage_per_tick,
                tick_ms,
                tick_count,
                state
              )

              %{state | mp: new_mp, cooldowns: new_cooldowns, casting: false, cast_timer: nil}

            :charge ->
              new_charge = min(10, state.charge_count + 1)

              send(
                state.conn_pid,
                {:send_packet,
                 %Server.StatusUpdate{
                   object_id: state.char_id,
                   attributes: [{0x21, new_charge}]
                 }}
              )

              %{
                state
                | mp: new_mp,
                  cooldowns: new_cooldowns,
                  casting: false,
                  cast_timer: nil,
                  charge_count: new_charge
              }

            :toggle ->
              if Map.has_key?(state.toggle_skills, skill_id) do
                if ref = Map.get(state.toggle_skills, skill_id), do: Process.cancel_timer(ref)
                new_buffs = Enum.reject(state.buffs, &(&1.skill_id == skill_id))
                abn = %Server.AbnormalStatusUpdate{effects: new_buffs}
                send(state.conn_pid, {:send_packet, abn})

                %{
                  state
                  | mp: new_mp,
                    cooldowns: new_cooldowns,
                    casting: false,
                    cast_timer: nil,
                    toggle_skills: Map.delete(state.toggle_skills, skill_id),
                    buffs: new_buffs
                }
              else
                timer =
                  Process.send_after(
                    self(),
                    {:toggle_tick, skill_id, template.mp_cost},
                    2_000
                  )

                buff = %BuffInfo{
                  skill_id: skill_id,
                  level: level,
                  skill_name: template.name,
                  caster_id: state.char_id,
                  start_monotonic: now_ms,
                  duration_ms: 0,
                  stat_bonus: template.stat_bonus
                }

                new_buffs = [buff | Enum.reject(state.buffs, &(&1.skill_id == skill_id))]
                abn = %Server.AbnormalStatusUpdate{effects: new_buffs}
                send(state.conn_pid, {:send_packet, abn})

                %{
                  state
                  | mp: new_mp,
                    cooldowns: new_cooldowns,
                    casting: false,
                    cast_timer: nil,
                    toggle_skills: Map.put(state.toggle_skills, skill_id, timer),
                    buffs: new_buffs
                }
              end

            :slow ->
              caster_stats = player_combat_stats(state)
              target_stats = get_target_stats(target_id, state)

              if Effect.check_cc_lands?(caster_stats, target_stats) do
                _factor = Effect.slow_factor(template.power)
                timer = Process.send_after(self(), {:slow_expired}, template.buff_duration_ms)

                %{
                  state
                  | mp: new_mp,
                    cooldowns: new_cooldowns,
                    casting: false,
                    cast_timer: nil,
                    slowed: true,
                    slow_timer: timer
                }
              else
                %{state | mp: new_mp, cooldowns: new_cooldowns, casting: false, cast_timer: nil}
              end

            :silence ->
              caster_stats = player_combat_stats(state)
              target_stats = get_target_stats(target_id, state)

              if Effect.check_silence_lands?(caster_stats, target_stats) do
                timer = Process.send_after(self(), {:silence_expired}, template.buff_duration_ms)

                %{
                  state
                  | mp: new_mp,
                    cooldowns: new_cooldowns,
                    casting: false,
                    cast_timer: nil,
                    silenced: true,
                    silence_timer: timer
                }
              else
                %{state | mp: new_mp, cooldowns: new_cooldowns, casting: false, cast_timer: nil}
              end

            :mana_burn ->
              caster_stats = player_combat_stats(state)
              mp_damage = Effect.apply_mana_burn(caster_stats, template.power)
              burned_mp = max(0.0, new_mp - mp_damage)

              send(
                state.conn_pid,
                {:send_packet, Server.StatusUpdate.hp_mp(state.char_id, state.hp, burned_mp)}
              )

              %{state | mp: burned_mp, cooldowns: new_cooldowns, casting: false, cast_timer: nil}

            :cancel ->
              count = Effect.cancel_count(template.power)
              new_buffs = state.buffs |> Enum.shuffle() |> Enum.drop(count)
              abn_pkt = %Server.AbnormalStatusUpdate{effects: new_buffs}
              send(state.conn_pid, {:send_packet, abn_pkt})

              %{
                state
                | mp: new_mp,
                  cooldowns: new_cooldowns,
                  casting: false,
                  cast_timer: nil,
                  buffs: new_buffs
              }

            _ ->
              %{state | mp: new_mp, cooldowns: new_cooldowns, casting: false, cast_timer: nil}
          end

        {:noreply, new_state}
    end
  end

  # Buff timer expired — remove from buff list and recalculate stats
  def handle_info({:buff_expired, skill_id}, state) do
    new_buffs = Enum.reject(state.buffs, &(&1.skill_id == skill_id))
    template = ClassTemplates.get_or_default(state.class_id)
    base_stats = Stats.compute(template, state.level)
    bonuses = Inventory.get_equip_bonuses(state.char_id)
    new_stats = base_stats |> Stats.apply_equipment(bonuses) |> Stats.apply_buffs(new_buffs)

    abn_pkt = %Server.AbnormalStatusUpdate{effects: new_buffs}
    send(state.conn_pid, {:send_packet, abn_pkt})

    {:noreply, %{state | buffs: new_buffs, stats: new_stats}}
  end

  # M21: Another player invites this player to a party
  def handle_info({:party_invite, party_pid, invitor_name}, state) do
    {:noreply, %{state | pending_party_invite: {party_pid, invitor_name}}}
  end

  # M22: Another player invites this player to a clan
  def handle_info({:clan_invite, clan_pid}, state) do
    {:noreply, %{state | pending_clan_invite: {clan_pid, ""}}}
  end

  # M27: Another player sends a trade invite to this player
  def handle_info({:trade_invite, from_char_id, from_name, from_pid, trade_pid}, state) do
    # Send a trade request packet to the client so they see the accept/decline dialog
    pkt = %Server.SendTradeRequest{
      partner_object_id: from_char_id,
      partner_name: from_name
    }

    send(state.conn_pid, {:send_packet, pkt})
    {:noreply, %{state | pending_trade: {from_char_id, from_pid, trade_pid}}}
  end

  # Party disbanded or we were kicked — clear our party reference
  def handle_info(:party_disbanded, state) do
    {:noreply, %{state | party_pid: nil}}
  end

  # Instance expired — eject player back to Giran town spawn
  def handle_info(:instance_ejected, state) do
    spawn_x = Application.get_env(:l2e, :spawn_x, 83_400)
    spawn_y = Application.get_env(:l2e, :spawn_y, 147_880)
    spawn_z = Application.get_env(:l2e, :spawn_z, -3_400)
    new_state = do_teleport({spawn_x, spawn_y, spawn_z}, state)
    {:noreply, new_state}
  end

  # Door state changed in the current instance
  def handle_info({:instance_door_update, door_id, open?}, state) do
    Logger.debug("[Instance] Door #{door_id} is now #{if open?, do: "open", else: "closed"}")
    {:noreply, state}
  end

  # M49: CC timer expired — remove the flag
  def handle_info({:cc_expired, cc_type}, state) do
    {:noreply, %{state | cc_state: Map.delete(state.cc_state, cc_type)}}
  end

  # M49: DoT tick fires
  def handle_info(
        {:dot_tick, skill_id, damage_per_tick, tick_ms, ticks_left},
        %{dead: false} = state
      ) do
    new_hp = max(0.0, state.hp - damage_per_tick)

    send(
      state.conn_pid,
      {:send_packet, Server.StatusUpdate.hp_mp(state.char_id, new_hp, state.mp)}
    )

    new_dots =
      if ticks_left > 1 do
        timer =
          Process.send_after(
            self(),
            {:dot_tick, skill_id, damage_per_tick, tick_ms, ticks_left - 1},
            tick_ms
          )

        Map.put(state.dots, skill_id, timer)
      else
        Map.delete(state.dots, skill_id)
      end

    if new_hp <= 0 do
      die_pkt = %Server.Die{object_id: state.char_id, can_sweep: false}
      send(state.conn_pid, {:send_packet, die_pkt})
      if state.region_pid, do: GenServer.cast(state.region_pid, {:broadcast_packet, die_pkt})
      cancel_timer(state.attack_timer)
      cancel_timer(state.regen_timer)
      Process.send_after(self(), :respawn, 30_000)

      {:noreply,
       %{
         state
         | hp: 0.0,
           dead: true,
           attacking: false,
           attack_timer: nil,
           regen_timer: nil,
           dots: new_dots
       }}
    else
      {:noreply, %{state | hp: new_hp, dots: new_dots}}
    end
  end

  def handle_info({:dot_tick, _skill_id, _dmg, _ms, _ticks}, state), do: {:noreply, state}

  # M49: Toggle MP drain tick
  def handle_info({:toggle_tick, skill_id, mp_cost_per_tick}, state) do
    if Map.has_key?(state.toggle_skills, skill_id) do
      if state.mp < mp_cost_per_tick do
        new_buffs = Enum.reject(state.buffs, &(&1.skill_id == skill_id))
        abn = %Server.AbnormalStatusUpdate{effects: new_buffs}
        send(state.conn_pid, {:send_packet, abn})

        {:noreply,
         %{state | toggle_skills: Map.delete(state.toggle_skills, skill_id), buffs: new_buffs}}
      else
        new_mp = state.mp - mp_cost_per_tick

        send(
          state.conn_pid,
          {:send_packet, Server.StatusUpdate.hp_mp(state.char_id, state.hp, new_mp)}
        )

        timer = Process.send_after(self(), {:toggle_tick, skill_id, mp_cost_per_tick}, 2_000)

        {:noreply,
         %{state | mp: new_mp, toggle_skills: Map.put(state.toggle_skills, skill_id, timer)}}
      end
    else
      {:noreply, state}
    end
  end

  # ---- M66: Friend handle_info -----------------------------------------------

  def handle_info({:friend_invite, inviter_id, inviter_name}, state) do
    # Store pending invite and ask the player (client shows a dialog)
    # L2 protocol: the client accepts with RequestAnswerFriendInvite
    send(
      state.conn_pid,
      {:send_packet,
       %Server.L2Friend{
         type: 1,
         obj_id: inviter_id,
         name: inviter_name,
         online: true
       }}
    )

    {:noreply, Map.put(state, :pending_friend_invite, {inviter_id, inviter_name})}
  end

  def handle_info({:friend_added, friend_id, friend_name}, state) do
    send(
      state.conn_pid,
      {:send_packet,
       %Server.L2Friend{
         type: 1,
         obj_id: friend_id,
         name: friend_name,
         online: true
       }}
    )

    {:noreply, state}
  end

  def handle_info({:friend_msg, sender_name, message}, state) do
    send(
      state.conn_pid,
      {:send_packet,
       %Server.FriendRecvMsg{
         receiver_name: state.char_name,
         sender_name: sender_name,
         message: message
       }}
    )

    {:noreply, state}
  end

  def handle_info({:friend_online, friend_id, friend_name}, state) do
    send(
      state.conn_pid,
      {:send_packet,
       %Server.FriendStatusPacket{
         obj_id: friend_id,
         name: friend_name,
         online: true
       }}
    )

    {:noreply, state}
  end

  def handle_info({:friend_offline, friend_id, friend_name}, state) do
    send(
      state.conn_pid,
      {:send_packet,
       %Server.FriendStatusPacket{
         obj_id: friend_id,
         name: friend_name,
         online: false
       }}
    )

    {:noreply, state}
  end

  # ---- M69: Duel handle_info -------------------------------------------------

  def handle_info({:duel_invite, inviter_id, inviter_name, party_duel}, state) do
    send(
      state.conn_pid,
      {:send_packet,
       %Server.ExDuelAskStart{
         requestor_name: inviter_name,
         party_duel: party_duel
       }}
    )

    {:noreply, %{state | pending_duel: {inviter_id, inviter_name, party_duel}}}
  end

  def handle_info({:duel_start, duel_id, party_duel}, state) do
    send(state.conn_pid, {:send_packet, %Server.ExDuelReady{party_duel: party_duel}})
    send(state.conn_pid, {:send_packet, %Server.ExDuelStart{party_duel: party_duel}})
    {:noreply, %{state | active_duel_id: duel_id, pending_duel: nil}}
  end

  def handle_info({:duel_end, party_duel}, state) do
    send(state.conn_pid, {:send_packet, %Server.ExDuelEnd{party_duel: party_duel}})
    {:noreply, %{state | active_duel_id: nil}}
  end

  # ---- M72: Pet handle_info --------------------------------------------------

  def handle_info({:pet_spawned, pet_pid, pet_item_obj_id}, state) do
    {:noreply, %{state | pet_pid: pet_pid, pet_item_obj_id: pet_item_obj_id}}
  end

  def handle_info({:pet_despawned}, state) do
    {:noreply, %{state | pet_pid: nil, pet_item_obj_id: nil}}
  end

  # M49-B: Slow timer expired
  def handle_info({:slow_expired}, state) do
    {:noreply, %{state | slowed: false, slow_timer: nil}}
  end

  # M49-B: Silence timer expired
  def handle_info({:silence_expired}, state) do
    {:noreply, %{state | silenced: false, silence_timer: nil}}
  end

  # M55-B: Zone damage tick
  def handle_info({:zone_damage_tick, zone_type}, state) do
    current_zone =
      ZoneTable.zone_type_at(
        elem(state.position, 0),
        elem(state.position, 1),
        elem(state.position, 2)
      )

    if current_zone == zone_type and state.hp > 0 do
      damage =
        if zone_type == :damage,
          do: max(1, div(state.max_hp, 20)),
          else: max(1, div(state.max_hp, 50))

      new_hp = max(0, state.hp - damage)
      tick_ms = if zone_type == :damage, do: 2000, else: 4000
      timer = Process.send_after(self(), {:zone_damage_tick, zone_type}, tick_ms)
      state = %{state | hp: new_hp, zone_damage_timer: timer}

      send(
        state.conn_pid,
        {:send_packet, Server.StatusUpdate.hp_mp(state.char_id, new_hp, state.mp)}
      )

      {:noreply, state}
    else
      # Player left zone — no more ticks
      {:noreply, %{state | zone_damage_timer: nil}}
    end
  end

  # ---- M70-B: Olympiad match messages from Olympiad.Match -------------------

  def handle_info({:olympiad_match_start, match_pid, _opponent_info}, state) do
    {:noreply, %{state | olympiad_match_pid: match_pid, olympiad_return_pos: state.position}}
  end

  def handle_info({:olympiad_arena_teleport, x, y, z}, state) do
    new_pos = {x, y, z}

    send(
      state.conn_pid,
      {:send_packet,
       %Server.TeleportToLocation{
         object_id: state.char_id,
         x: x,
         y: y,
         z: z
       }}
    )

    {:noreply, %{state | position: new_pos}}
  end

  def handle_info({:olympiad_match_result, :draw, _opponent_name, _points_delta}, state) do
    send(
      state.conn_pid,
      {:send_packet,
       %Server.ExOlympiadMatchResult{
         winner_char_id: 0,
         winner_name: "",
         loser_char_id: 0,
         loser_name: ""
       }}
    )

    {:noreply, state}
  end

  def handle_info({:olympiad_match_result, :win, opponent_name, _points_delta}, state) do
    send(
      state.conn_pid,
      {:send_packet,
       %Server.ExOlympiadMatchResult{
         winner_char_id: state.char_id,
         winner_name: state.char_name,
         loser_char_id: 0,
         loser_name: opponent_name || ""
       }}
    )

    {:noreply, state}
  end

  def handle_info({:olympiad_match_result, :loss, opponent_name, _points_delta}, state) do
    send(
      state.conn_pid,
      {:send_packet,
       %Server.ExOlympiadMatchResult{
         winner_char_id: 0,
         winner_name: opponent_name || "",
         loser_char_id: state.char_id,
         loser_name: state.char_name
       }}
    )

    {:noreply, state}
  end

  def handle_info({:olympiad_return, {x, y, z}}, state) do
    return_pos = state.olympiad_return_pos || {x, y, z}
    {rx, ry, rz} = return_pos

    send(
      state.conn_pid,
      {:send_packet,
       %Server.TeleportToLocation{
         object_id: state.char_id,
         x: rx,
         y: ry,
         z: rz
       }}
    )

    {:noreply, %{state | olympiad_match_pid: nil, olympiad_return_pos: nil, position: return_pos}}
  end

  # ---- M72-B: Pet died -------------------------------------------------------

  def handle_info({:pet_died}, state) do
    if state.pet_pid, do: Process.exit(state.pet_pid, :normal)
    {:noreply, %{state | pet_pid: nil, pet_item_obj_id: nil}}
  end

  def handle_info(msg, state) do
    Logger.debug("[PlayerSession] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_combat_stats, _from, state) do
    result = {:ok, state.char_id, player_combat_stats(state), state.position}
    {:reply, result, state}
  end

  # Party/Clan calls this to get the player's info for the party window
  def handle_call(:get_party_info, _from, state) do
    info = %{
      char_name: state.char_name,
      char_id: state.char_id,
      hp: state.hp,
      max_hp: state.max_hp,
      mp: state.mp,
      max_mp: state.max_mp,
      level: state.level,
      class_id: state.class_id
    }

    {:reply, {:ok, info}, state}
  end

  # M35: Buyer calls this to read the seller's current store list + char_id
  def handle_call(:get_store_list, _from, state) do
    {:reply, {state.char_id, state.private_store_list}, state}
  end

  # M43: Anyone can call this to read the buy store list + owner char_id
  def handle_call(:get_buy_store_list, _from, state) do
    {:reply, {state.char_id, state.buy_store_list}, state}
  end

  # M47: Retrieve current quest state for a quest_id
  def handle_call({:get_quest_state, quest_id}, _from, state) do
    quest = Map.get(state.quests, quest_id, %{state: 0, cond: 0, count: 0, reward_taken: false})
    {:reply, quest, state}
  end

  # M43: Runs on the BUY STORE OWNER's session when a seller offers items.
  # Validates the request, transfers items + adena, and updates the buy list.
  def handle_call(
        {:buy_from_me, seller_pid, seller_char_id, items},
        _from,
        %{private_store_type: :buy_store} = state
      ) do
    case validate_buy_from_request(state.buy_store_list, items) do
      {:ok, total_cost, validated} ->
        if Inventory.get_adena_count(state.char_id) >= total_cost do
          # Deduct adena from owner
          Inventory.spend_adena(state.char_id, total_cost)

          # Give items to owner, send inventory updates
          Enum.each(validated, fn %{item_id: item_id, count: count} ->
            case Inventory.add_item(state.char_id, item_id, count) do
              {:ok, change_type, {instance, template}} ->
                pkt = %Server.InventoryUpdate{
                  changes: [{change_type_to_int(change_type), instance, template}]
                }

                send(state.conn_pid, {:send_packet, pkt})

              _ ->
                :ok
            end
          end)

          # Notify seller to remove items from their inventory and receive adena
          GenServer.cast(seller_pid, {:buy_store_sold, validated, total_cost})

          # Reduce buy list counts; close store if all filled
          new_buy_list = reduce_buy_list(state.buy_store_list, validated)

          new_state =
            if new_buy_list == [] do
              %{state | buy_store_list: [], private_store_type: :none}
            else
              %{state | buy_store_list: new_buy_list}
            end

          _ = seller_char_id
          {:reply, :ok, new_state}
        else
          {:reply, {:error, :insufficient_adena}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:buy_from_me, _seller_pid, _seller_char_id, _items}, _from, state) do
    {:reply, {:error, :store_closed}, state}
  end

  # -----------------------------------------------------------------------
  # Packet handlers (auth state machine)
  # -----------------------------------------------------------------------

  # ---- AuthLogin (state :protocol_ok) ------------------------------------

  defp handle_packet(%L2E.Packet.Client.AuthLogin{} = pkt, %{auth_state: :protocol_ok} = state) do
    case L2E.LoginServer.AccountStore.pop(pkt.login_name, pkt.play_ok1, pkt.play_ok2) do
      {:ok, _session_key} ->
        Logger.info("[PlayerSession] AuthLogin ok for #{pkt.login_name}")

        access_level =
          case Repo.get_by(Account, username: pkt.login_name) do
            %Account{access_level: lvl} -> lvl
            nil -> 0
          end

        new_state = %{
          state
          | username: pkt.login_name,
            auth_state: :authenticated,
            access_level: access_level
        }

        send(state.conn_pid, {:send_packet, build_char_select_info(pkt.login_name)})
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("[PlayerSession] AuthLogin failed for #{pkt.login_name}: #{reason}")
        {:stop, :normal, state}
    end
  end

  # ---- NewCharacter (state :authenticated) --------------------------------

  defp handle_packet(%L2E.Packet.Client.NewCharacter{}, %{auth_state: :authenticated} = state) do
    send(state.conn_pid, {:send_packet, %Server.NewCharacterSuccess{}})
    {:noreply, state}
  end

  # ---- CharacterCreate (state :authenticated) -----------------------------

  defp handle_packet(
         %L2E.Packet.Client.CharacterCreate{} = pkt,
         %{auth_state: :authenticated, username: username} = state
       ) do
    attrs = %{
      account_name: username,
      name: pkt.name,
      race: pkt.race,
      sex: pkt.sex,
      class_id: pkt.class_id,
      hair_style: pkt.hair_style,
      hair_color: pkt.hair_color,
      face: pkt.face
    }

    case Repo.insert(Character.create_changeset(attrs)) do
      {:ok, char} ->
        Logger.info("[PlayerSession] Created character #{pkt.name} for #{username}")
        grant_initial_equipment(char.id, pkt.class_id)
        send(state.conn_pid, {:send_packet, %Server.CharCreateOk{}})
        # Refresh char list so the client can select the new character
        send(state.conn_pid, {:send_packet, build_char_select_info(username)})

      {:error, %Ecto.Changeset{errors: errors}} ->
        reason =
          if Keyword.has_key?(errors, :name),
            do: Server.CharCreateFail.reason_name_exists(),
            else: Server.CharCreateFail.reason_invalid_name()

        Logger.info("[PlayerSession] CharacterCreate failed for #{pkt.name}: #{inspect(errors)}")
        send(state.conn_pid, {:send_packet, %Server.CharCreateFail{reason: reason}})
    end

    {:noreply, state}
  end

  # ---- CharacterDelete (state :authenticated) -----------------------------

  defp handle_packet(
         %L2E.Packet.Client.CharacterDelete{slot: slot},
         %{auth_state: :authenticated, username: username} = state
       ) do
    chars = list_characters(username)

    case Enum.at(chars, slot) do
      nil ->
        send(state.conn_pid, {:send_packet, %Server.CharDeleteFail{reason: 1}})

      char ->
        Repo.delete!(char)

        Logger.info(
          "[PlayerSession] Deleted character #{char.name} (slot #{slot}) for #{username}"
        )

        send(state.conn_pid, {:send_packet, %Server.CharDeleteOk{}})
        send(state.conn_pid, {:send_packet, build_char_select_info(username)})
    end

    {:noreply, state}
  end

  # ---- CharacterSelect (state :authenticated) ----------------------------

  defp handle_packet(
         %L2E.Packet.Client.CharacterSelect{slot: slot},
         %{auth_state: :authenticated, username: username} = state
       ) do
    chars = list_characters(username)

    case Enum.at(chars, slot) do
      nil ->
        Logger.warning("[PlayerSession] CharacterSelect: invalid slot #{slot}")
        {:noreply, state}

      char ->
        new_state = %{
          state
          | char_id: char.id,
            char_db_id: char.id,
            char_name: char.name,
            class_id: char.class_id,
            level: char.level,
            exp: char.exp,
            sp: char.sp,
            position: {char.x, char.y, char.z},
            heading: char.heading,
            hp: char.hp,
            max_hp: char.max_hp,
            mp: char.mp,
            max_mp: char.max_mp,
            karma: Map.get(char, :karma, 0),
            pvp_kills: Map.get(char, :pvp_kills, 0),
            pk_kills: Map.get(char, :pk_kills, 0),
            auth_state: :char_selected,
            hennas: %{
              1 => char.henna1,
              2 => char.henna2,
              3 => char.henna3
            }
        }

        selected = %Server.CharSelected{
          name: char.name,
          object_id: char.id,
          session_id: :rand.uniform(0x7FFFFFFF),
          clan_id: 0,
          sex: char.sex,
          race: char.race,
          class_id: char.class_id,
          x: char.x,
          y: char.y,
          z: char.z,
          hp: char.hp,
          max_hp: char.max_hp,
          mp: char.mp,
          max_mp: char.max_mp,
          sp: char.sp,
          exp: char.exp,
          level: char.level,
          karma: 0
        }

        send(state.conn_pid, {:send_packet, selected})
        {:noreply, new_state}
    end
  end

  # ---- EnterWorld (state :char_selected) ---------------------------------

  defp handle_packet(%L2E.Packet.Client.EnterWorld{}, %{auth_state: :char_selected} = state) do
    char_id = state.char_id
    char_name = state.char_name

    # Derive full stats from class template + level
    template = ClassTemplates.get_or_default(state.class_id)
    derived_base = Stats.compute(template, state.level)

    # Start inventory for this character and apply equipment bonuses to stats
    InventorySupervisor.start_inventory(char_id)
    equip_bonuses = Inventory.get_equip_bonuses(char_id)
    derived = Stats.apply_equipment(derived_base, equip_bonuses)

    # Use DB HP/MP if in valid range, otherwise start at full
    cur_hp = min(state.hp, derived.max_hp * 1.0)
    cur_mp = min(state.mp, derived.max_mp * 1.0)

    new_state = %{
      state
      | auth_state: :in_world,
        stats: derived,
        max_hp: derived.max_hp * 1.0,
        max_mp: derived.max_mp * 1.0,
        max_cp: derived.max_cp * 1.0,
        hp: cur_hp,
        mp: cur_mp,
        cp: derived.max_cp * 1.0
    }

    Registry.register(L2E.Session.Registry, char_id, self())

    # Stamp last_access
    if char_db_id = state.char_db_id do
      Repo.update_all(
        from(c in Character, where: c.id == ^char_db_id),
        set: [last_access: DateTime.utc_now()]
      )
    end

    user_info = %Server.UserInfo{
      char_id: char_id,
      char_name: char_name,
      x: elem(new_state.position, 0),
      y: elem(new_state.position, 1),
      z: elem(new_state.position, 2),
      heading: new_state.heading,
      hp: trunc(cur_hp),
      max_hp: derived.max_hp,
      pvp_flag: new_state.pvp_flag,
      karma: new_state.karma
    }

    send(state.conn_pid, {:send_packet, user_info})

    # Send full stat update so the client shows correct HP/MP bars and paperdoll stats
    status_update = Server.StatusUpdate.from_char_stats(char_id, derived, cur_hp, cur_mp)
    send(state.conn_pid, {:send_packet, status_update})

    # Send full inventory list so the client populates the inventory window
    items = Inventory.get_items(char_id)
    send(state.conn_pid, {:send_packet, %Server.ItemList{items: items}})

    # Load and send skill list
    skills = load_char_skills(char_id)
    send(state.conn_pid, {:send_packet, build_skill_list_packet(skills)})

    # Load quest state from DB
    quests = load_char_quests(char_id)

    region_pid = enter_region(new_state)

    regen_timer = Process.send_after(self(), :regen_tick, 3_000)
    save_timer = Process.send_after(self(), :auto_save, 300_000)

    # M54: Load shortcuts from DB and send ShortcutInit
    shortcuts = load_char_shortcuts(char_id)
    shortcut_init = %Server.ShortcutInit{shortcuts: shortcuts}
    send(state.conn_pid, {:send_packet, shortcut_init})

    # M67: Send QuestList — active quests for the quest journal
    active_quests =
      quests
      |> Enum.filter(fn {_id, q} -> q.state == 1 end)
      |> Enum.map(fn {quest_id, q} -> %{quest_id: quest_id, cond: q.cond} end)

    send(state.conn_pid, {:send_packet, %Server.QuestList{quests: active_quests}})

    # M66: Send empty friend list on enter world (full load deferred)
    send(state.conn_pid, {:send_packet, %Server.FriendList{friends: []}})

    # M74-A: Load macros
    macros =
      L2E.Repo.all(
        from(m in CharacterMacro, where: m.character_id == ^state.char_id, order_by: m.macro_id)
      )

    send(
      state.conn_pid,
      {:send_packet, %L2E.Packet.Server.SendMacroList{revision: 0, macros: macros}}
    )

    Logger.info(
      "[PlayerSession] #{char_name} (id=#{char_id}) entered the world (class=#{state.class_id}, level=#{state.level})"
    )

    {:noreply,
     %{
       new_state
       | region_pid: region_pid,
         skills: skills,
         quests: quests,
         shortcuts: shortcuts,
         macros: macros,
         regen_timer: regen_timer,
         save_timer: save_timer
     }}
  end

  # ---- MoveToLocation (state :in_world) ----------------------------------

  # M49: Block movement when stunned, rooted, sleeping, or paralyzed
  defp handle_packet(%L2E.Packet.Client.MoveToLocation{}, %{cc_state: cc} = state)
       when is_map_key(cc, :stunned) or is_map_key(cc, :rooted) or
              is_map_key(cc, :sleeping) or is_map_key(cc, :paralyzed) do
    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.MoveToLocation{} = move, state) do
    origin = state.position
    new_pos = {move.x, move.y, move.z}
    new_state = %{state | position: new_pos}

    if state.region_pid do
      GenServer.cast(
        state.region_pid,
        {:player_moved, state.char_id, self(), origin, new_pos, state.heading}
      )
    end

    {:noreply, new_state}
  end

  defp handle_packet(%L2E.Packet.Client.ValidatePosition{x: x, y: y, z: z, heading: h}, state) do
    new_zone = ZoneTable.zone_type_at(x, y, z)
    state = handle_zone_change(state, new_zone)
    {:noreply, %{state | position: {x, y, z}, heading: h}}
  end

  # ---- Action (0x04) — target selection or attack ------------------------

  defp handle_packet(%L2E.Packet.Client.Action{object_id: obj_id, action_id: action_id}, state) do
    cond do
      obj_id == state.char_id ->
        # Clicking on self: deselect
        {:noreply, state}

      action_id == 0 ->
        # Normal click: set target
        new_state = %{state | target_id: obj_id}
        color = level_color(state, obj_id)

        send(
          state.conn_pid,
          {:send_packet,
           %Server.TargetSelected{
             object_id: state.char_id,
             target_id: obj_id,
             color: color
           }}
        )

        send(
          state.conn_pid,
          {:send_packet,
           %Server.MyTargetSelected{
             target_id: obj_id,
             color: color
           }}
        )

        # M16: If target is an NPC, open dialog on second click (or always)
        case find_npc_pid(obj_id) do
          nil ->
            # M35: If target is a player with an active sell store, show it
            case Registry.lookup(L2E.Session.Registry, obj_id) do
              [{other_pid, _}] ->
                {_char_id, sell_list} = GenServer.call(other_pid, :get_store_list)

                unless sell_list == [] do
                  buyer_adena = Inventory.get_adena_count(state.char_id)
                  seller_items = Inventory.get_items(obj_id)

                  store_display =
                    Enum.flat_map(sell_list, fn entry ->
                      case Enum.find(seller_items, fn {inst, _} -> inst.id == entry.object_id end) do
                        nil ->
                          []

                        {inst, tpl} ->
                          [
                            %{
                              type2: tpl.type2,
                              obj_id: inst.id,
                              item_id: inst.item_id,
                              count: entry.count,
                              enchant: inst.enchant_level || 0,
                              bodypart: tpl.bodypart,
                              price: entry.price,
                              ref_price: tpl.sell_price
                            }
                          ]
                      end
                    end)

                  store_pkt = %Server.PrivateStoreListSell{
                    seller_id: obj_id,
                    is_package: 0,
                    buyer_adena: buyer_adena,
                    items: store_display
                  }

                  send(state.conn_pid, {:send_packet, store_pkt})
                end

                # M43: Also display buy store if owner has one open
                {_char_id, buy_list} = GenServer.call(other_pid, :get_buy_store_list)

                unless buy_list == [] do
                  buy_pkt = %Server.PrivateStoreListBuy{
                    owner_id: obj_id,
                    items:
                      Enum.map(buy_list, fn e ->
                        %{item_id: e.item_id, count: e.count, price: e.price}
                      end)
                  }

                  send(state.conn_pid, {:send_packet, buy_pkt})
                end

              _ ->
                :ok
            end

          npc_pid ->
            open_npc_dialog(npc_pid, obj_id, state)
        end

        {:noreply, new_state}

      action_id == 1 ->
        # Shift-click: attack — blocked in peace zones
        if state.zone_type == :peace do
          {:noreply, state}
        else
          new_state = %{state | target_id: obj_id}
          {:noreply, start_auto_attack(new_state)}
        end
    end
  end

  # ---- AttackRequest (0x0A) — direct attack ------------------------------

  # M49: Block attacks when stunned, sleeping, or paralyzed
  defp handle_packet(%L2E.Packet.Client.AttackRequest{}, %{cc_state: cc} = state)
       when is_map_key(cc, :stunned) or is_map_key(cc, :sleeping) or
              is_map_key(cc, :paralyzed) do
    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.AttackRequest{object_id: obj_id}, state) do
    # Block attacks in peace zones
    if state.zone_type == :peace do
      {:noreply, state}
    else
      new_state = %{state | target_id: obj_id}
      {:noreply, start_auto_attack(new_state)}
    end
  end

  # ---- RequestTargetCanceld (0x37) — cancel target -----------------------

  defp handle_packet(%L2E.Packet.Client.RequestTargetCanceld{}, state) do
    cancel_timer(state.attack_timer)
    {:noreply, %{state | target_id: nil, attacking: false, attack_timer: nil}}
  end

  # ---- M54: RequestShortcutReg (0x33) — register a shortcut --------------

  defp handle_packet(
         %L2E.Packet.Client.RequestShortcutReg{
           type: type,
           slot: slot,
           page: page,
           shortcut_id: sc_id,
           level: level
         },
         %{auth_state: :in_world} = state
       )
       when page in 0..9 do
    effective_level =
      if type == 1,
        do: Map.get(state.skills, sc_id, level),
        else: level

    CharacterShortcut.upsert(state.char_id, slot, page, type, sc_id, effective_level)

    sc = %{type: type, slot: slot, page: page, shortcut_id: sc_id, level: effective_level}

    new_shortcuts =
      Enum.reject(state.shortcuts, fn s -> s.slot == slot and s.page == page end)

    send(
      state.conn_pid,
      {:send_packet,
       %Server.ShortcutRegister{
         type: type,
         slot: slot,
         page: page,
         shortcut_id: sc_id,
         level: effective_level
       }}
    )

    {:noreply, %{state | shortcuts: [sc | new_shortcuts]}}
  end

  defp handle_packet(%L2E.Packet.Client.RequestShortcutReg{}, state), do: {:noreply, state}

  # ---- M54: RequestShortcutDel (0x35) — delete a shortcut ----------------

  defp handle_packet(
         %L2E.Packet.Client.RequestShortcutDel{slot: slot, page: page},
         %{auth_state: :in_world} = state
       ) do
    CharacterShortcut.delete(state.char_id, slot, page)

    new_shortcuts =
      Enum.reject(state.shortcuts, fn s -> s.slot == slot and s.page == page end)

    {:noreply, %{state | shortcuts: new_shortcuts}}
  end

  # ---- M59: RequestActionUse (0x45) — action bar slot activated ----------

  defp handle_packet(
         %L2E.Packet.Client.RequestActionUse{action_id: 0},
         %{auth_state: :in_world, target_id: target_id} = state
       )
       when not is_nil(target_id) do
    if state.zone_type == :peace do
      {:noreply, state}
    else
      {:noreply, start_auto_attack(state)}
    end
  end

  defp handle_packet(
         %L2E.Packet.Client.RequestActionUse{action_id: 2},
         %{auth_state: :in_world} = state
       ) do
    Logger.debug(
      "[PlayerSession] #{state.char_name} sit/stand toggle (no-op until ChangeWaitType)"
    )

    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestActionUse{}, state), do: {:noreply, state}

  # ---- M56: RequestHennaEquip (0xBC) — equip a dye/tattoo ----------------

  defp handle_packet(
         %L2E.Packet.Client.RequestHennaEquip{dye_id: dye_id},
         %{auth_state: :in_world} = state
       ) do
    case L2E.Data.HennaTable.get_dye_for_item(dye_id) do
      nil ->
        {:noreply, state}

      henna ->
        slot = Enum.find_value(1..3, fn s -> if Map.get(state.hennas, s) == nil, do: s end)

        if slot do
          items = Inventory.get_items(state.char_id)

          case Enum.find(items, fn {inst, _} -> inst.item_id == henna.dye_id end) do
            {inst, _} when inst.count >= henna.dye_count ->
              Inventory.remove_item(state.char_id, inst.id, henna.dye_count)
              new_hennas = Map.put(state.hennas, slot, henna.henna_id)
              update_henna_in_db(state.char_id, new_hennas)
              send(state.conn_pid, {:send_packet, build_henna_info_packet(new_hennas)})
              {:noreply, %{state | hennas: new_hennas}}

            _ ->
              {:noreply, state}
          end
        else
          {:noreply, state}
        end
    end
  end

  # ---- M56: RequestHennaRemove (0xBF) — remove a dye/tattoo --------------

  defp handle_packet(
         %L2E.Packet.Client.RequestHennaRemove{dye_id: dye_id},
         %{auth_state: :in_world} = state
       ) do
    slot =
      Enum.find_value(1..3, fn s ->
        hid = Map.get(state.hennas, s)

        if hid do
          henna = L2E.Data.HennaTable.get(hid)
          if henna && henna.dye_id == dye_id, do: s
        end
      end)

    if slot do
      henna = L2E.Data.HennaTable.get(Map.get(state.hennas, slot))
      Inventory.add_item(state.char_id, henna.dye_id, henna.cancel_fee)
      new_hennas = Map.put(state.hennas, slot, nil)
      update_henna_in_db(state.char_id, new_hennas)
      send(state.conn_pid, {:send_packet, build_henna_info_packet(new_hennas)})
      {:noreply, %{state | hennas: new_hennas}}
    else
      {:noreply, state}
    end
  end

  # ---- M56: RequestRecipeItemMakeSelf (0xAF) — craft via self recipe ------

  defp handle_packet(
         %L2E.Packet.Client.RequestRecipeItemMakeSelf{recipe_id: recipe_id},
         %{auth_state: :in_world} = state
       ) do
    case L2E.Data.RecipeTable.get(recipe_id) do
      nil ->
        {:noreply, state}

      recipe ->
        items = Inventory.get_items(state.char_id)

        result =
          Enum.reduce_while(recipe.ingredients, :ok, fn %{item_id: iid, count: qty}, _ ->
            case Enum.find(items, fn {inst, _} -> inst.item_id == iid end) do
              {inst, _} when inst.count >= qty -> {:cont, :ok}
              _ -> {:halt, :error}
            end
          end)

        case result do
          :ok ->
            Enum.each(recipe.ingredients, fn %{item_id: iid, count: qty} ->
              {inst, _} = Enum.find(items, fn {i, _} -> i.item_id == iid end)
              Inventory.remove_item(state.char_id, inst.id, qty)
            end)

            Inventory.add_item(state.char_id, recipe.item_id, recipe.count)

            pkt = %Server.RecipeItemMakeInfo{
              recipe_id: recipe_id,
              current_mp: round(state.mp),
              max_mp: round(state.max_mp),
              success: true,
              is_common: Map.get(recipe, :is_common, false)
            }

            send(state.conn_pid, {:send_packet, pkt})

          :error ->
            pkt = %Server.RecipeItemMakeInfo{
              recipe_id: recipe_id,
              current_mp: round(state.mp),
              max_mp: round(state.max_mp),
              success: false,
              is_common: Map.get(recipe, :is_common, false)
            }

            send(state.conn_pid, {:send_packet, pkt})
        end

        {:noreply, state}
    end
  end

  # ---- M56: RequestConfirmRefinerItem (0xD0/0x2A) — validate life stone ---

  defp handle_packet(%L2E.Packet.Client.RequestConfirmRefinerItem{}, state) do
    # Client validation step — acknowledge with no extra state change.
    {:noreply, state}
  end

  # ---- M56: RequestRefine (0xD0/0x2C) — augment weapon with life stone ----

  defp handle_packet(
         %L2E.Packet.Client.RequestRefine{},
         %{auth_state: :in_world} = state
       ) do
    option = L2E.Data.OptionTable.get_random_option(:low)
    aug_id = if option, do: option.option_id, else: 0

    pkt = %Server.ExVariationResult{
      stat12: aug_id,
      stat34: 0,
      result: if(option, do: 1, else: 0)
    }

    send(state.conn_pid, {:send_packet, pkt})
    {:noreply, state}
  end

  defp handle_packet(
         %L2E.Packet.Client.UseItem{object_id: obj_id},
         %{auth_state: :in_world} = state
       ) do
    # Check if the item being used is an enchant scroll
    items = Inventory.get_items(state.char_id)

    enchant_scroll =
      Enum.find(items, fn {inst, _tmpl} -> inst.object_id == obj_id end)
      |> case do
        {inst, _tmpl} -> EnchantData.get(inst.item_id)
        nil -> nil
      end

    if enchant_scroll != nil do
      # Open enchant dialog — just remember which scroll the player selected
      {:noreply, %{state | enchant_scroll_id: obj_id}}
    else
      case Inventory.use_item(state.char_id, obj_id) do
        {:ok, change_type, {instance, template}} ->
          change_int = change_type_to_int(change_type)
          pkt = %Server.InventoryUpdate{changes: [{change_int, instance, template}]}
          send(state.conn_pid, {:send_packet, pkt})

          new_state =
            if template.type in [:weapon, :armor] do
              recalculate_stats_with_equipment(state)
            else
              apply_item_effect(state, template)
            end

          {:noreply, new_state}

        {:error, _reason} ->
          {:noreply, state}
      end
    end
  end

  # ---- RequestEnchantItem (0x58) — player confirms enchant attempt -------

  defp handle_packet(
         %L2E.Packet.Client.RequestEnchantItem{object_id: item_obj_id},
         %{auth_state: :in_world, enchant_scroll_id: scroll_obj_id} = state
       )
       when not is_nil(scroll_obj_id) do
    items = Inventory.get_items(state.char_id)

    # Find the scroll instance and the target item instance
    scroll_pair = Enum.find(items, fn {inst, _} -> inst.object_id == scroll_obj_id end)
    item_pair = Enum.find(items, fn {inst, _} -> inst.object_id == item_obj_id end)

    case {scroll_pair, item_pair} do
      {{scroll_inst, _scroll_tmpl}, {item_inst, item_tmpl}} ->
        scroll_data = EnchantData.get(scroll_inst.item_id)

        cond do
          scroll_data == nil ->
            send(state.conn_pid, {:send_packet, %Server.EnchantResult{result: :cancelled}})
            {:noreply, %{state | enchant_scroll_id: nil}}

          # Verify grade match — item grade must match scroll's target_grade
          not grades_match?(item_tmpl, scroll_data.target_grade) ->
            send(state.conn_pid, {:send_packet, %Server.EnchantResult{result: :cancelled}})
            {:noreply, %{state | enchant_scroll_id: nil}}

          true ->
            current_enchant = item_inst.enchant_level || 0
            result = EnchantData.try_enchant(scroll_inst.item_id, current_enchant)

            # Consume the scroll regardless of result
            Inventory.remove_item(state.char_id, scroll_inst.item_id, 1)

            new_state =
              case result do
                :success ->
                  new_enchant = current_enchant + 1
                  Inventory.update_enchant(state.char_id, item_obj_id, new_enchant)
                  send(state.conn_pid, {:send_packet, %Server.EnchantResult{result: :success}})
                  state

                :fail when scroll_data.blessed ->
                  # Blessed scroll: item stays at current level
                  send(
                    state.conn_pid,
                    {:send_packet, %Server.EnchantResult{result: :blessed_fail}}
                  )

                  state

                :fail ->
                  # Normal scroll: item destroyed on fail if enchant >= +4
                  if current_enchant >= 4 do
                    Inventory.remove_item(state.char_id, item_inst.item_id, 1)
                    send(state.conn_pid, {:send_packet, %Server.EnchantResult{result: :fail}})
                  else
                    # Below +4 always succeeds per L2 rules — this branch shouldn't trigger,
                    # but handle defensively: success anyway
                    Inventory.update_enchant(state.char_id, item_obj_id, current_enchant + 1)
                    send(state.conn_pid, {:send_packet, %Server.EnchantResult{result: :success}})
                  end

                  state

                :max ->
                  send(state.conn_pid, {:send_packet, %Server.EnchantResult{result: :cancelled}})
                  state

                :unknown_scroll ->
                  send(state.conn_pid, {:send_packet, %Server.EnchantResult{result: :cancelled}})
                  state
              end

            {:noreply, %{new_state | enchant_scroll_id: nil}}
        end

      _ ->
        send(state.conn_pid, {:send_packet, %Server.EnchantResult{result: :cancelled}})
        {:noreply, %{state | enchant_scroll_id: nil}}
    end
  end

  defp handle_packet(%L2E.Packet.Client.RequestEnchantItem{}, state) do
    send(state.conn_pid, {:send_packet, %Server.EnchantResult{result: :cancelled}})
    {:noreply, %{state | enchant_scroll_id: nil}}
  end

  # ---- RequestDestroyItem (0x59) — delete item from inventory -----------

  defp handle_packet(
         %L2E.Packet.Client.RequestDestroyItem{object_id: obj_id, count: count},
         %{auth_state: :in_world} = state
       ) do
    case Inventory.remove_item(state.char_id, obj_id, max(1, count)) do
      {:ok, _change_type, {instance, template}} ->
        pkt = %Server.InventoryUpdate{changes: [{3, instance, template}]}
        send(state.conn_pid, {:send_packet, pkt})

      {:error, _} ->
        :ok
    end

    {:noreply, state}
  end

  # ---- RequestDropItem (0x12) — drop item to ground ----------------------

  defp handle_packet(
         %L2E.Packet.Client.RequestDropItem{object_id: obj_id, count: count, x: x, y: y, z: z},
         %{auth_state: :in_world} = state
       ) do
    case Inventory.remove_item(state.char_id, obj_id, max(1, count)) do
      {:ok, _change_type, {instance, template}} ->
        pkt = %Server.InventoryUpdate{changes: [{3, instance, template}]}
        send(state.conn_pid, {:send_packet, pkt})

        if state.region_pid do
          drop_obj_id = :erlang.unique_integer([:positive, :monotonic])

          GenServer.cast(
            state.region_pid,
            {:drop_item, drop_obj_id, template.item_id, x, y, z, instance.count}
          )
        end

      {:error, _} ->
        :ok
    end

    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestSkillList{}, %{auth_state: :in_world} = state) do
    send(state.conn_pid, {:send_packet, build_skill_list_packet(state.skills)})
    {:noreply, state}
  end

  # ---- RequestMagicSkillUse (0x2F) — player activates a skill ------------

  # M49: Block skill use when stunned, sleeping, paralyzed, or silenced (cc)
  defp handle_packet(%L2E.Packet.Client.RequestMagicSkillUse{}, %{cc_state: cc} = state)
       when is_map_key(cc, :stunned) or is_map_key(cc, :sleeping) or
              is_map_key(cc, :paralyzed) or is_map_key(cc, :silenced) do
    {:noreply, state}
  end

  # M49-B: Block skill use when silenced
  defp handle_packet(%L2E.Packet.Client.RequestMagicSkillUse{}, %{silenced: true} = state) do
    {:noreply, state}
  end

  defp handle_packet(
         %L2E.Packet.Client.RequestMagicSkillUse{},
         %{auth_state: :in_world, zone_type: :peace} = state
       ) do
    # Skills that target others are blocked in peace zones
    {:noreply, state}
  end

  defp handle_packet(
         %L2E.Packet.Client.RequestMagicSkillUse{skill_id: skill_id},
         %{auth_state: :in_world, dead: false} = state
       ) do
    level = level_from_skills(state.skills, skill_id)

    with {:ok, template} <- fetch_skill_template(skill_id, level),
         :ok <- check_not_casting(state),
         :ok <- check_cooldown(state.cooldowns, skill_id),
         :ok <- check_mp(state.mp, template.mp_cost) do
      target_id = state.target_id || state.char_id

      cast_pkt = %Server.MagicSkillUse{
        caster_id: state.char_id,
        target_id: target_id,
        skill_id: skill_id,
        skill_level: level,
        hit_time: template.cast_time_ms,
        reuse_delay: template.reuse_ms,
        x: elem(state.position, 0),
        y: elem(state.position, 1),
        z: elem(state.position, 2)
      }

      if state.region_pid, do: GenServer.cast(state.region_pid, {:broadcast_packet, cast_pkt})
      send(state.conn_pid, {:send_packet, cast_pkt})

      ref =
        Process.send_after(
          self(),
          {:cast_complete, skill_id, level, target_id},
          template.cast_time_ms
        )

      {:noreply, %{state | casting: true, cast_timer: ref}}
    else
      _ -> {:noreply, state}
    end
  end

  defp handle_packet(%L2E.Packet.Client.RequestMagicSkillUse{}, state), do: {:noreply, state}

  # ---- RequestPickUpItem (0x16) — pick up a ground item ------------------

  defp handle_packet(
         %L2E.Packet.Client.RequestPickUpItem{object_id: obj_id},
         %{auth_state: :in_world} = state
       ) do
    if state.region_pid do
      case GenServer.call(state.region_pid, {:pickup_item, obj_id, self()}) do
        nil ->
          :ok

        item_data ->
          case Inventory.add_item(state.char_id, item_data.item_id, item_data.count) do
            {:ok, change_type, {instance, template}} ->
              change_int = change_type_to_int(change_type)
              pkt = %Server.InventoryUpdate{changes: [{change_int, instance, template}]}
              send(state.conn_pid, {:send_packet, pkt})

            {:error, reason} ->
              Logger.warning(
                "[PlayerSession] Pickup add_item failed #{item_data.item_id}: #{inspect(reason)}"
              )
          end
      end
    end

    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestPickUpItem{}, state), do: {:noreply, state}

  # ---- M16: NPC Interaction via Action (0x04) + Bypass (0x21) ------------

  # Re-handle Action for NPC interaction (action_id=0 on an NPC → show dialog)
  # This is injected before the existing Action handler; the first matching
  # clause wins, so this specific NPC-open case must live before the generic one.
  # NOTE: We handle this inside the Action handler by checking if the target is an NPC.

  defp handle_packet(
         %L2E.Packet.Client.RequestBypassToServer{command: cmd},
         %{auth_state: :in_world} = state
       ) do
    handle_bypass(cmd, state)
  end

  defp handle_packet(%L2E.Packet.Client.RequestBypassToServer{}, state), do: {:noreply, state}

  # ---- RequestGotoLobby (0xBA) — player returns to character selection ----

  defp handle_packet(%L2E.Packet.Client.RequestGotoLobby{}, %{auth_state: :in_world} = state) do
    # Save position/vitals to DB before leaving world
    persist_position(state)

    # Cancel active timers
    cancel_timer(state.regen_timer)
    cancel_timer(state.save_timer)
    cancel_timer(state.attack_timer)
    cancel_timer(state.cast_timer)

    # Leave current region and unregister from session registry
    leave_region(state)
    stop_inventory(state)

    if state.char_id do
      Registry.unregister(L2E.Session.Registry, state.char_id)
    end

    # RestartResponse: opcode 0x71 + success byte
    send(state.conn_pid, {:send_packet, <<0x71, 0x01>>})

    {:noreply,
     %{
       state
       | auth_state: :authenticated,
         region_pid: nil,
         target_id: nil,
         attacking: false,
         attack_timer: nil,
         dead: false,
         casting: false,
         cast_timer: nil,
         regen_timer: nil,
         save_timer: nil,
         buffs: [],
         cooldowns: %{},
         pvp_flag_timer: nil
     }}
  end

  defp handle_packet(%L2E.Packet.Client.RequestGotoLobby{}, state), do: {:noreply, state}

  # ---- RequestSSQStatus (0xC7) — M61-B: Seven Signs Quest status panel ----
  # SSQStatus server packet not yet implemented; log and ignore until M61-C.
  defp handle_packet(%L2E.Packet.Client.RequestSSQStatus{page: _page}, state) do
    {:noreply, state}
  end

  defp handle_packet(
         %L2E.Packet.Client.RequestBuyItem{npc_object_id: _npc_id, items: items},
         %{auth_state: :in_world} = state
       ) do
    Enum.each(items, fn {item_id, count} ->
      case Inventory.add_item(state.char_id, item_id, count) do
        {:ok, change_type, {instance, template}} ->
          change_int = change_type_to_int(change_type)
          pkt = %Server.InventoryUpdate{changes: [{change_int, instance, template}]}
          send(state.conn_pid, {:send_packet, pkt})

        {:error, reason} ->
          Logger.warning("[PlayerSession] Buy failed item_id=#{item_id}: #{inspect(reason)}")
      end
    end)

    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestBuyItem{}, state), do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.RequestSellItem{npc_object_id: _npc_id, items: items},
         %{auth_state: :in_world} = state
       ) do
    Enum.each(items, fn {obj_id, _item_id, count} ->
      case Inventory.remove_item(state.char_id, obj_id, count) do
        {:ok, change_type, {instance, template}} ->
          change_int = change_type_to_int(change_type)
          pkt = %Server.InventoryUpdate{changes: [{change_int, instance, template}]}
          send(state.conn_pid, {:send_packet, pkt})

        {:error, _} ->
          :ok
      end
    end)

    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestSellItem{}, state), do: {:noreply, state}

  # ---- M26: Warehouse (0x32 withdraw, 0x33 deposit) ----------------------

  defp handle_packet(
         %L2E.Packet.Client.RequestWarehouseWithdraw{items: items},
         %{auth_state: :in_world} = state
       ) do
    Enum.each(items, fn %{object_id: inst_id, count: qty} ->
      wh_result =
        case state.warehouse_context do
          :clan when state.clan_id != 0 ->
            L2E.Warehouse.ClanWarehouse.withdraw(state.clan_id, inst_id, qty)

          _ ->
            Warehouse.withdraw(state.char_id, inst_id, qty)
        end

      case wh_result do
        {:ok, item} ->
          {:ok, _change_type, {inv_inst, template}} =
            Inventory.add_item(state.char_id, item.item_id, item.count)

          pkt = %Server.InventoryUpdate{
            changes: [{1, inv_inst, template}]
          }

          send(state.conn_pid, {:send_packet, pkt})

        {:error, reason} ->
          Logger.warning("[PlayerSession] warehouse withdraw failed: #{inspect(reason)}")
      end
    end)

    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestWarehouseWithdraw{}, state), do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.RequestWarehouseDeposit{items: items},
         %{auth_state: :in_world} = state
       ) do
    Enum.each(items, fn %{object_id: inst_id, count: qty} ->
      case Inventory.remove_item(state.char_id, inst_id, qty) do
        {:ok, _change_type, {inst, _template}} ->
          deposit_result =
            case state.warehouse_context do
              :clan when state.clan_id != 0 ->
                L2E.Warehouse.ClanWarehouse.deposit(
                  state.clan_id,
                  inst.item_id,
                  qty,
                  inst.enchant_level || 0
                )

              _ ->
                Warehouse.deposit(state.char_id, inst.item_id, qty, inst.enchant_level || 0)
            end

          case deposit_result do
            {:ok, _wh_id} ->
              # Send inventory update to remove item from client view
              pkt = %Server.InventoryUpdate{changes: [{3, inst, %{}}]}
              send(state.conn_pid, {:send_packet, pkt})

            {:error, reason} ->
              Logger.warning("[PlayerSession] warehouse deposit failed: #{inspect(reason)}")
          end

        {:error, reason} ->
          Logger.warning(
            "[PlayerSession] inventory remove for deposit failed: #{inspect(reason)}"
          )
      end
    end)

    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestWarehouseDeposit{}, state), do: {:noreply, state}

  # ---- M27: Trade --------------------------------------------------------

  defp handle_packet(
         %L2E.Packet.Client.TradeRequest{target_object_id: target_obj_id},
         %{auth_state: :in_world} = state
       ) do
    # target_obj_id is the object_id (DB id) of the target player
    target_char_id = target_obj_id

    cond do
      target_char_id == state.char_id ->
        {:noreply, state}

      state.trade_pid != nil ->
        {:noreply, state}

      true ->
        case Registry.lookup(L2E.Session.Registry, target_char_id) do
          [{target_pid, _}] ->
            case L2E.Trade.Supervisor.start_trade(
                   state.char_id,
                   target_char_id,
                   self(),
                   target_pid
                 ) do
              {:ok, trade_pid} ->
                # Notify the target player of incoming trade request
                send(
                  target_pid,
                  {:trade_invite, state.char_id, state.char_name, self(), trade_pid}
                )

                new_state = %{state | trade_pid: trade_pid}
                {:noreply, new_state}

              _ ->
                {:noreply, state}
            end

          [] ->
            {:noreply, state}
        end
    end
  end

  defp handle_packet(%L2E.Packet.Client.TradeRequest{}, state), do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.AnswerTradeRequest{response: response},
         %{auth_state: :in_world} = state
       ) do
    case state.pending_trade do
      {from_char_id, from_pid, trade_pid} when response == 1 ->
        # Accept — tell trade process we accepted
        Trade.accept(trade_pid, state.char_id)
        # Notify initiator
        pkt = %Server.TradeStart{
          partner_object_id: from_char_id,
          items: []
        }

        send(from_pid, {:send_packet, pkt})

        send(
          state.conn_pid,
          {:send_packet, %Server.TradeStart{partner_object_id: from_char_id, items: []}}
        )

        new_state = %{state | trade_pid: trade_pid, pending_trade: nil}
        {:noreply, new_state}

      {_from_char_id, _from_pid, trade_pid} ->
        # Decline — cancel the trade process
        Trade.cancel(trade_pid, state.char_id)
        {:noreply, %{state | pending_trade: nil}}

      nil ->
        {:noreply, state}
    end
  end

  defp handle_packet(%L2E.Packet.Client.AnswerTradeRequest{}, state), do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.AddTradeItem{items: items},
         %{auth_state: :in_world} = state
       ) do
    if trade_pid = state.trade_pid do
      Enum.each(items, fn %{object_id: obj_id, count: qty} ->
        Trade.add_item(trade_pid, state.char_id, obj_id, qty)
      end)
    end

    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.AddTradeItem{}, state), do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.TradeDone{response: response},
         %{auth_state: :in_world} = state
       ) do
    case state.trade_pid do
      nil ->
        {:noreply, state}

      trade_pid ->
        if response == 1 do
          Trade.confirm(trade_pid, state.char_id)
        else
          Trade.cancel(trade_pid, state.char_id)
        end

        {:noreply, %{state | trade_pid: nil}}
    end
  end

  defp handle_packet(%L2E.Packet.Client.TradeDone{}, state), do: {:noreply, state}

  # ---- M17: Chat (Say2 0x38) ---------------------------------------------

  defp handle_packet(
         %L2E.Packet.Client.Say2{message: msg, chat_type: chat_type, target_name: target_name},
         %{auth_state: :in_world} = state
       ) do
    pkt = %Server.CreatureSay{
      char_id: state.char_id,
      chat_type: chat_type,
      char_name: state.char_name,
      message: msg
    }

    case chat_type do
      2 ->
        # Whisper: find target player and send directly
        if target_name do
          case find_session_by_name(target_name) do
            nil ->
              :ok

            target_pid ->
              send(target_pid, {:send_packet, pkt})
              # Echo back to sender
              send(state.conn_pid, {:send_packet, pkt})
          end
        end

      3 ->
        # Party chat: broadcast to party members
        if state.party_pid do
          GenServer.cast(state.party_pid, {:party_chat, state.char_id, pkt})
        end

      4 ->
        # Clan chat: broadcast to clan members
        if state.clan_pid do
          GenServer.cast(state.clan_pid, {:clan_chat, state.char_id, pkt})
        end

      _ ->
        # SAY (0), SHOUT (1), TRADE (8) etc. — broadcast to region
        if state.region_pid do
          GenServer.cast(state.region_pid, {:broadcast_packet, pkt})
        end

        # Always send to self
        send(state.conn_pid, {:send_packet, pkt})
    end

    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.Say2{}, state), do: {:noreply, state}

  # ---- M21: Party requests -----------------------------------------------

  defp handle_packet(
         %L2E.Packet.Client.RequestJoinParty{target_name: target_name, distribution_type: dist},
         %{auth_state: :in_world} = state
       ) do
    if state.char_name == target_name do
      send(
        state.conn_pid,
        {:send_packet,
         %Server.SystemMessage{message_id: Server.SystemMessage.msg_cannot_invite_self()}}
      )

      {:noreply, state}
    else
      case find_session_by_name(target_name) do
        nil ->
          {:noreply, state}

        target_pid ->
          # Create or reuse party
          party_pid =
            case state.party_pid do
              nil ->
                {:ok, pid} = L2E.Party.Supervisor.start_party(state.char_id, self(), dist)
                pid

              pid ->
                pid
            end

          Party.invite(party_pid, resolve_char_id(target_pid), target_pid, state.char_name)

          # Tell target session about pending invite
          send(target_pid, {:party_invite, party_pid, state.char_name})

          {:noreply, %{state | party_pid: party_pid}}
      end
    end
  end

  defp handle_packet(%L2E.Packet.Client.RequestJoinParty{}, state), do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.RequestAnswerJoinParty{response: response},
         %{auth_state: :in_world} = state
       ) do
    case state.pending_party_invite do
      nil ->
        {:noreply, state}

      {party_pid, _invitor_name} ->
        accept = response == 1
        Party.answer_invite(party_pid, state.char_id, self(), accept)

        new_state =
          if accept do
            %{state | party_pid: party_pid, pending_party_invite: nil}
          else
            %{state | pending_party_invite: nil}
          end

        {:noreply, new_state}
    end
  end

  defp handle_packet(%L2E.Packet.Client.RequestAnswerJoinParty{}, state), do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.RequestWithDrawalParty{},
         %{auth_state: :in_world} = state
       ) do
    if state.party_pid do
      Party.leave(state.party_pid, state.char_id)
      {:noreply, %{state | party_pid: nil}}
    else
      {:noreply, state}
    end
  end

  defp handle_packet(%L2E.Packet.Client.RequestWithDrawalParty{}, state), do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.RequestOustPartyMember{target_name: name},
         %{auth_state: :in_world} = state
       ) do
    if state.party_pid do
      Party.kick(state.party_pid, name)
    end

    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestOustPartyMember{}, state), do: {:noreply, state}

  # ---- M22: Clan requests ------------------------------------------------

  defp handle_packet(
         %L2E.Packet.Client.RequestJoinPledge{target_id: target_id},
         %{auth_state: :in_world} = state
       ) do
    case find_session_by_id(target_id) do
      nil ->
        {:noreply, state}

      target_pid ->
        # Create or reuse clan (simplified: no DB persistence for clans yet)
        clan_pid =
          case state.clan_pid do
            nil ->
              clan_id = :erlang.unique_integer([:positive, :monotonic])
              clan_name = "#{state.char_name}'s Clan"

              {:ok, pid} =
                L2E.Clan.Supervisor.start_clan(clan_id, clan_name, state.char_id, self())

              pid

            pid ->
              pid
          end

        Clan.invite(clan_pid, target_id, target_pid)
        send(target_pid, {:clan_invite, clan_pid})

        {:noreply, %{state | clan_pid: clan_pid}}
    end
  end

  defp handle_packet(%L2E.Packet.Client.RequestJoinPledge{}, state), do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.RequestAnswerJoinPledge{response: response},
         %{auth_state: :in_world} = state
       ) do
    case state.pending_clan_invite do
      nil ->
        {:noreply, state}

      {clan_pid, _clan_name} ->
        accept = response == 1
        Clan.answer_invite(clan_pid, state.char_id, self(), accept)

        new_state =
          if accept do
            %{state | clan_pid: clan_pid, pending_clan_invite: nil}
          else
            %{state | pending_clan_invite: nil}
          end

        {:noreply, new_state}
    end
  end

  defp handle_packet(%L2E.Packet.Client.RequestAnswerJoinPledge{}, state), do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.RequestWithdrawalPledge{},
         %{auth_state: :in_world} = state
       ) do
    if state.clan_pid do
      Clan.leave(state.clan_pid, state.char_id)
      {:noreply, %{state | clan_pid: nil}}
    else
      {:noreply, state}
    end
  end

  defp handle_packet(%L2E.Packet.Client.RequestWithdrawalPledge{}, state), do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.RequestOustPledgeMember{target_name: name},
         %{auth_state: :in_world} = state
       ) do
    if state.clan_pid do
      Clan.kick(state.clan_pid, name)
    end

    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestOustPledgeMember{}, state), do: {:noreply, state}

  # ---- M39: RequestAutoSoulShot (0xD0/0x05) — toggle auto soulshot -------

  defp handle_packet(
         %L2E.Packet.Client.RequestAutoSoulShot{item_id: item_id, type: type},
         %{auth_state: :in_world} = state
       ) do
    new_id = if type == 1, do: item_id, else: nil
    confirm = %Server.ExAutoSoulShot{item_id: item_id, type: type}
    send(state.conn_pid, {:send_packet, confirm})
    {:noreply, %{state | autoshot_item_id: new_id}}
  end

  defp handle_packet(%L2E.Packet.Client.RequestAutoSoulShot{}, state), do: {:noreply, state}

  # ---- M35: Private Store — Sell -----------------------------------------

  defp handle_packet(
         %L2E.Packet.Client.RequestPrivateStoreManageSell{},
         %{auth_state: :in_world} = state
       ) do
    adena = Inventory.get_adena_count(state.char_id)
    items = Inventory.get_items(state.char_id)

    available =
      items
      |> Enum.reject(fn {inst, _tpl} -> inst.is_equipped end)
      |> Enum.map(fn {inst, tpl} ->
        %{
          type2: tpl.type2,
          obj_id: inst.id,
          item_id: inst.item_id,
          count: inst.count || 1,
          enchant: inst.enchant_level || 0,
          bodypart: tpl.bodypart,
          price: tpl.sell_price
        }
      end)

    store_items =
      state.private_store_list
      |> Enum.map(fn entry ->
        case Enum.find(items, fn {inst, _} -> inst.id == entry.object_id end) do
          nil ->
            nil

          {inst, tpl} ->
            %{
              type2: tpl.type2,
              obj_id: inst.id,
              item_id: inst.item_id,
              count: entry.count,
              enchant: inst.enchant_level || 0,
              bodypart: tpl.bodypart,
              price: entry.price,
              ref_price: tpl.sell_price
            }
        end
      end)
      |> Enum.reject(&is_nil/1)

    pkt = %Server.PrivateStoreManageListSell{
      seller_id: state.char_id,
      is_package: 0,
      adena: adena,
      available_items: available,
      store_items: store_items
    }

    send(state.conn_pid, {:send_packet, pkt})
    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestPrivateStoreManageSell{}, state),
    do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.SetPrivateStoreListSell{is_package: is_pkg, items: items},
         %{auth_state: :in_world} = state
       ) do
    # Enrich each store entry with the item_id looked up from seller's inventory
    inv_items = Inventory.get_items(state.char_id)

    enriched =
      Enum.flat_map(items, fn entry ->
        case Enum.find(inv_items, fn {inst, _} -> inst.id == entry.object_id end) do
          nil -> []
          {inst, _tpl} -> [Map.put(entry, :item_id, inst.item_id)]
        end
      end)

    new_state = %{state | private_store_type: :sell, private_store_list: enriched}

    msg_pkt = %Server.PrivateStoreMsgSell{
      object_id: state.char_id,
      title: state.private_store_title
    }

    if state.region_pid do
      GenServer.cast(state.region_pid, {:broadcast_packet, msg_pkt})
    end

    _ = is_pkg
    {:noreply, new_state}
  end

  defp handle_packet(%L2E.Packet.Client.SetPrivateStoreListSell{}, state), do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.RequestPrivateStoreQuitSell{},
         %{auth_state: :in_world} = state
       ) do
    new_state = %{
      state
      | private_store_type: :none,
        private_store_list: [],
        private_store_title: ""
    }

    # Broadcast empty title to clear store icon for nearby players
    msg_pkt = %Server.PrivateStoreMsgSell{object_id: state.char_id, title: ""}

    if state.region_pid do
      GenServer.cast(state.region_pid, {:broadcast_packet, msg_pkt})
    end

    {:noreply, new_state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestPrivateStoreQuitSell{}, state),
    do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.SetPrivateStoreMsgSell{title: title},
         %{auth_state: :in_world} = state
       ) do
    new_state = %{state | private_store_title: title || ""}
    {:noreply, new_state}
  end

  defp handle_packet(%L2E.Packet.Client.SetPrivateStoreMsgSell{}, state), do: {:noreply, state}

  # M75-A: Buy store title message
  defp handle_packet(
         %L2E.Packet.Client.SetPrivateStoreMsgBuy{title: title},
         %{auth_state: :in_world} = state
       ) do
    new_state = %{state | private_store_title: title || ""}
    {:noreply, new_state}
  end

  defp handle_packet(%L2E.Packet.Client.SetPrivateStoreMsgBuy{}, state), do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.RequestPrivateStoreBuy{seller_id: seller_id, items: req_items},
         %{auth_state: :in_world} = state
       ) do
    with [{seller_pid, _}] <- Registry.lookup(L2E.Session.Registry, seller_id),
         {:ok, total_cost, validated} <- validate_store_items(seller_pid, req_items),
         :ok <- check_buyer_adena(state.char_id, total_cost) do
      # Deduct adena from buyer
      Inventory.spend_adena(state.char_id, total_cost)

      # Process each item: remove from seller, give to buyer
      Enum.each(validated, fn %{obj_id: obj_id, item_id: item_id, count: count, price: price} ->
        _ = price
        Inventory.remove_item(seller_id, obj_id, count)

        case Inventory.add_item(state.char_id, item_id, count) do
          {:ok, change_type, {instance, template}} ->
            change_int = change_type_to_int(change_type)
            pkt = %Server.InventoryUpdate{changes: [{change_int, instance, template}]}
            send(state.conn_pid, {:send_packet, pkt})

          {:error, _} ->
            :ok
        end
      end)

      # Pay adena to seller and notify them
      Inventory.add_item(seller_id, 57, total_cost)
      GenServer.cast(seller_pid, {:store_items_sold, req_items, total_cost})
    else
      _ -> :ok
    end

    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestPrivateStoreBuy{}, state), do: {:noreply, state}

  # ---- M43: Private Store — Buy ------------------------------------------

  defp handle_packet(
         %L2E.Packet.Client.RequestPrivateStoreManageBuy{},
         %{auth_state: :in_world} = state
       ) do
    pkt = %Server.PrivateStoreManageListBuy{
      owner_id: state.char_id,
      adena: Inventory.get_adena_count(state.char_id),
      buy_list: state.buy_store_list
    }

    send(state.conn_pid, {:send_packet, pkt})
    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestPrivateStoreManageBuy{}, state),
    do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.SetPrivateStoreListBuy{items: items},
         %{auth_state: :in_world} = state
       ) do
    valid =
      is_list(items) and
        Enum.all?(items, fn e ->
          is_map(e) and
            Map.get(e, :item_id, 0) > 0 and
            Map.get(e, :count, 0) > 0 and
            Map.get(e, :price, 0) > 0
        end)

    if valid do
      total_needed = Enum.reduce(items, 0, fn e, acc -> acc + e.price * e.count end)
      owner_adena = Inventory.get_adena_count(state.char_id)

      if owner_adena >= total_needed do
        new_state = %{state | private_store_type: :buy_store, buy_store_list: items}

        msg_pkt = %Server.PrivateStoreMsgBuy{
          object_id: state.char_id,
          title: state.private_store_title
        }

        if state.region_pid do
          GenServer.cast(state.region_pid, {:broadcast_packet, msg_pkt})
        end

        {:noreply, new_state}
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  defp handle_packet(%L2E.Packet.Client.SetPrivateStoreListBuy{}, state), do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.RequestPrivateStoreQuitBuy{},
         %{auth_state: :in_world} = state
       ) do
    new_state = %{state | private_store_type: :none, buy_store_list: []}

    msg_pkt = %Server.PrivateStoreMsgBuy{object_id: state.char_id, title: ""}

    if state.region_pid do
      GenServer.cast(state.region_pid, {:broadcast_packet, msg_pkt})
    end

    {:noreply, new_state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestPrivateStoreQuitBuy{}, state),
    do: {:noreply, state}

  # Seller sends this when they want to sell items TO a buy store owner.
  # (L2J: RequestPrivateStoreSell — client opcode 0xB7)
  defp handle_packet(
         %L2E.Packet.Client.RequestPrivateStoreSell{owner_obj_id: owner_id, items: items},
         %{auth_state: :in_world} = state
       ) do
    with [{owner_pid, _}] <- Registry.lookup(L2E.Session.Registry, owner_id),
         true <- validate_seller_has_items(state.char_id, items) do
      GenServer.call(owner_pid, {:buy_from_me, self(), state.char_id, items})
    else
      _ -> :ok
    end

    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestPrivateStoreSell{}, state), do: {:noreply, state}

  # ---- M44: Skill Learn --------------------------------------------------

  defp handle_packet(
         %L2E.Packet.Client.RequestAcquireSkillInfo{
           skill_id: sid,
           skill_level: slvl,
           acquire_type: _
         },
         %{auth_state: :in_world} = state
       ) do
    info = SkillLearnTable.get_skill_info(state.class_id, sid, slvl)

    pkt = %Server.AcquireSkillInfo{
      skill_id: sid,
      skill_level: slvl,
      sp_cost: if(info, do: info.sp_cost, else: 0),
      min_level: if(info, do: info.min_level, else: 0)
    }

    send(state.conn_pid, {:send_packet, pkt})
    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestAcquireSkillInfo{}, state), do: {:noreply, state}

  defp handle_packet(
         %L2E.Packet.Client.RequestAcquireSkill{
           skill_id: sid,
           skill_level: slvl,
           acquire_type: _
         },
         %{auth_state: :in_world} = state
       ) do
    case SkillLearnTable.get_skill_info(state.class_id, sid, slvl) do
      nil ->
        {:noreply, state}

      %{sp_cost: sp_cost, min_level: min_level} ->
        cond do
          state.level < min_level ->
            {:noreply, state}

          state.sp < sp_cost ->
            {:noreply, state}

          true ->
            new_sp = state.sp - sp_cost
            new_skills = Map.put(state.skills, sid, slvl)

            # Persist skill
            if state.char_db_id do
              CharacterSkill.upsert_skill(state.char_db_id, sid, slvl)
            end

            # Persist SP
            if state.char_db_id do
              Repo.update_all(
                from(c in Character, where: c.id == ^state.char_db_id),
                set: [sp: new_sp]
              )
            end

            send(
              state.conn_pid,
              {:send_packet, %Server.AcquireSkillDone{skill_id: sid, skill_level: slvl}}
            )

            sp_update = %Server.StatusUpdate{
              object_id: state.char_id,
              attributes: [{Server.StatusUpdate.attr_sp(), new_sp}]
            }

            send(state.conn_pid, {:send_packet, sp_update})
            send(state.conn_pid, {:send_packet, build_skill_list_packet(new_skills)})

            {:noreply, %{state | sp: new_sp, skills: new_skills}}
        end
    end
  end

  defp handle_packet(%L2E.Packet.Client.RequestAcquireSkill{}, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # M60: Session lifecycle
  # ---------------------------------------------------------------------------

  defp handle_packet(%L2E.Packet.Client.Appearing{}, state) do
    # Client confirmed it loaded the teleport destination — re-send char position
    {x, y, z} = state.position

    send(
      state.conn_pid,
      {:send_packet,
       %Server.TeleportToLocation{
         object_id: state.char_id,
         x: x,
         y: y,
         z: z
       }}
    )

    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.Logout{}, state) do
    persist_position(state)
    stop_inventory(state)
    leave_region(state)
    {:stop, :normal, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestRestart{}, state) do
    persist_position(state)
    stop_inventory(state)
    leave_region(state)
    send(state.conn_pid, {:send_packet, %Server.RestartResponse{response: 1}})
    {:stop, :normal, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestRestartPoint{type: _type}, state) do
    # Respawn at Giran (default); later: check clan hall, castle ownership
    {rx, ry, rz} = {147_456, 23_040, -2_016}
    new_state = %{state | position: {rx, ry, rz}, hp: state.max_hp, dead: false}

    send(
      state.conn_pid,
      {:send_packet,
       %Server.TeleportToLocation{
         object_id: new_state.char_id,
         x: rx,
         y: ry,
         z: rz
       }}
    )

    {:noreply, new_state}
  end

  # ---------------------------------------------------------------------------
  # M61: Movement completeness
  # ---------------------------------------------------------------------------

  defp handle_packet(%L2E.Packet.Client.MoveWithDelta{dx: dx, dy: dy, dz: dz}, state) do
    {ox, oy, oz} = state.position
    {:noreply, %{state | position: {ox + dx, oy + dy, oz + dz}}}
  end

  defp handle_packet(%L2E.Packet.Client.CannotMoveAnymore{x: x, y: y, z: z, heading: h}, state) do
    {:noreply, %{state | position: {x, y, z}, heading: h}}
  end

  defp handle_packet(%L2E.Packet.Client.RequestSocialAction{action_id: action_id}, state) do
    if state.region_pid do
      GenServer.cast(
        state.region_pid,
        {:broadcast_packet,
         %Server.SocialAction{
           object_id: state.char_id,
           action_id: action_id
         }}
      )
    end

    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.ChangeMoveType2{move_type: move_type}, state) do
    new_state = %{state | is_running: move_type == 1}

    if state.region_pid do
      {x, y, z} = state.position

      GenServer.cast(
        state.region_pid,
        {:broadcast_packet,
         %Server.ChangeMoveType{
           object_id: state.char_id,
           run_mode: move_type,
           x: x,
           y: y,
           z: z
         }}
      )
    end

    {:noreply, new_state}
  end

  defp handle_packet(%L2E.Packet.Client.ChangeWaitType2{move_type: move_type}, state) do
    new_state = %{state | is_sitting: move_type == 1}

    if state.region_pid do
      {x, y, z} = state.position

      GenServer.cast(
        state.region_pid,
        {:broadcast_packet,
         %Server.ChangeWaitType{
           object_id: state.char_id,
           move_type: move_type,
           x: x,
           y: y,
           z: z
         }}
      )
    end

    {:noreply, new_state}
  end

  # ---------------------------------------------------------------------------
  # M62: Inventory actions
  # ---------------------------------------------------------------------------

  defp handle_packet(%L2E.Packet.Client.RequestUnequipItem{slot: slot}, state) do
    items = Inventory.get_items(state.char_id)

    case Enum.find(items, fn {inst, tmpl} -> inst.is_equipped and tmpl.bodypart == slot end) do
      {inst, _tmpl} ->
        case Inventory.use_item(state.char_id, inst.id) do
          {:ok, change_type, {instance, template}} ->
            pkt = %Server.InventoryUpdate{
              changes: [{change_type_to_int(change_type), instance, template}]
            }

            send(state.conn_pid, {:send_packet, pkt})
            {:noreply, recalculate_stats_with_equipment(state)}

          {:error, _} ->
            send(state.conn_pid, {:send_packet, %Server.ActionFail{}})
            {:noreply, state}
        end

      nil ->
        {:noreply, state}
    end
  end

  defp handle_packet(%L2E.Packet.Client.RequestCrystallizeItem{object_id: oid}, state) do
    items = Inventory.get_items(state.char_id)

    case Enum.find(items, fn {inst, _} -> inst.id == oid end) do
      {_inst, template} when not is_nil(template) ->
        {crystal_id, crystal_count} =
          crystal_data_for_grade(
            Map.get(template, :grade, :none),
            1
          )

        Inventory.remove_item(state.char_id, oid, 1)
        Inventory.add_item(state.char_id, crystal_id, crystal_count)
        new_items = Inventory.get_items(state.char_id)
        send(state.conn_pid, {:send_packet, %Server.ItemList{items: new_items}})

      _ ->
        send(state.conn_pid, {:send_packet, %Server.ActionFail{}})
    end

    {:noreply, state}
  end

  defp handle_packet(%L2E.Packet.Client.RequestSaveInventoryOrder{}, state),
    do: {:noreply, state}

  defp handle_packet(%L2E.Packet.Client.RequestItemList{}, state) do
    items = Inventory.get_items(state.char_id)
    send(state.conn_pid, {:send_packet, %Server.ItemList{items: items}})
    {:noreply, state}
  end

  # M64: MultiSell — player executes a multisell exchange
  defp handle_packet(
         %L2E.Packet.Client.MultiSellChoose{list_id: list_id, entry_id: entry_id},
         state
       ) do
    case MultisellTable.get(list_id) do
      nil ->
        send(state.conn_pid, {:send_packet, %Server.ActionFail{}})

      list ->
        case Enum.find(list.entries, &(&1.entry_id == entry_id)) do
          nil ->
            send(state.conn_pid, {:send_packet, %Server.ActionFail{}})

          entry ->
            has_all =
              Enum.all?(entry.ingredients, fn {item_id, needed} ->
                Inventory.count_item(state.char_id, item_id) >= needed
              end)

            if has_all do
              Enum.each(entry.ingredients, fn {item_id, count} ->
                Inventory.remove_item_by_template(state.char_id, item_id, count)
              end)

              Enum.each(entry.products, fn {item_id, count} ->
                Inventory.add_item(state.char_id, item_id, count)
              end)

              items = Inventory.get_items(state.char_id)
              send(state.conn_pid, {:send_packet, %Server.ItemList{items: items}})
            else
              send(state.conn_pid, {:send_packet, %Server.ActionFail{}})
            end
        end
    end

    {:noreply, state}
  end

  # ---- M66: Friend list -------------------------------------------------------

  defp handle_packet(%Client.RequestFriendList{}, state) do
    friends = CharacterFriend.load_for_character(state.char_id)

    friends_data =
      Enum.map(friends, fn f ->
        online =
          case Registry.lookup(L2E.Session.Registry, f.friend_id) do
            [{_pid, _}] -> true
            [] -> false
          end

        %{obj_id: f.friend_id, name: f.friend_name, online: online}
      end)

    send(state.conn_pid, {:send_packet, %Server.FriendList{friends: friends_data}})
    {:noreply, state}
  end

  defp handle_packet(%Client.RequestFriendInvite{name: name}, state) do
    case Registry.lookup(L2E.Session.Registry, name) do
      [{target_pid, _}] ->
        send(target_pid, {:friend_invite, state.char_id, state.char_name})

      [] ->
        Logger.debug("[PlayerSession] Friend invite: #{name} not online")
    end

    {:noreply, state}
  end

  defp handle_packet(%Client.RequestAnswerFriendInvite{response: response}, state) do
    case Map.get(state, :pending_friend_invite) do
      nil ->
        {:noreply, state}

      {inviter_id, inviter_name} ->
        if response == 1 do
          CharacterFriend.add(state.char_id, inviter_id, inviter_name)
          CharacterFriend.add(inviter_id, state.char_id, state.char_name)

          send(
            state.conn_pid,
            {:send_packet,
             %Server.L2Friend{
               type: 1,
               obj_id: inviter_id,
               name: inviter_name,
               online: true
             }}
          )

          case Registry.lookup(L2E.Session.Registry, inviter_id) do
            [{inviter_pid, _}] ->
              send(inviter_pid, {:friend_added, state.char_id, state.char_name})

            [] ->
              :ok
          end
        end

        {:noreply, Map.delete(state, :pending_friend_invite)}
    end
  end

  defp handle_packet(%Client.RequestFriendDel{name: name}, state) do
    friends = CharacterFriend.load_for_character(state.char_id)

    case Enum.find(friends, fn f -> f.friend_name == name end) do
      nil ->
        {:noreply, state}

      friend ->
        CharacterFriend.remove(state.char_id, friend.friend_id)
        CharacterFriend.remove(friend.friend_id, state.char_id)

        send(
          state.conn_pid,
          {:send_packet,
           %Server.L2Friend{
             type: 3,
             obj_id: friend.friend_id,
             name: friend.friend_name,
             online: false
           }}
        )

        {:noreply, state}
    end
  end

  defp handle_packet(
         %Client.RequestSendFriendMsg{char_name: target_name, message: message},
         state
       ) do
    case Registry.lookup(L2E.Session.Registry, target_name) do
      [{target_pid, _}] ->
        send(target_pid, {:friend_msg, state.char_name, message})

      [] ->
        Logger.debug("[PlayerSession] SendFriendMsg: #{target_name} not online")
    end

    {:noreply, state}
  end

  # ---- M74-A: Macro handlers --------------------------------------------------

  defp handle_packet(%Client.RequestMakeMacro{} = pkt, state) do
    attrs = %{
      character_id: state.char_id,
      macro_id: pkt.macro_id,
      name: pkt.name,
      descr: pkt.descr,
      keybind: pkt.keybind,
      icon: pkt.icon,
      commands: pkt.commands
    }

    changeset = CharacterMacro.changeset(%CharacterMacro{}, attrs)

    case L2E.Repo.insert(changeset,
           on_conflict: {:replace, [:name, :descr, :keybind, :icon, :commands]},
           conflict_target: [:character_id, :macro_id]
         ) do
      {:ok, macro} ->
        new_macros = Enum.reject(state.macros, &(&1.macro_id == macro.macro_id)) ++ [macro]

        send(
          state.conn_pid,
          {:send_packet, %L2E.Packet.Server.SendMacroList{revision: 1, macros: new_macros}}
        )

        {:noreply, %{state | macros: new_macros}}

      {:error, _cs} ->
        {:noreply, state}
    end
  end

  defp handle_packet(%Client.RequestDeleteMacro{macro_id: mid}, state) do
    L2E.Repo.delete_all(
      from(m in CharacterMacro, where: m.character_id == ^state.char_id and m.macro_id == ^mid)
    )

    new_macros = Enum.reject(state.macros, &(&1.macro_id == mid))

    send(
      state.conn_pid,
      {:send_packet, %L2E.Packet.Server.SendMacroList{revision: 1, macros: new_macros}}
    )

    {:noreply, %{state | macros: new_macros}}
  end

  # ---- M73-A: Alliance stubs --------------------------------------------------

  defp handle_packet(%Client.RequestJoinAlly{}, state) do
    {:noreply, state}
  end

  defp handle_packet(%Client.RequestAnswerJoinAlly{}, state) do
    {:noreply, state}
  end

  defp handle_packet(%Client.RequestDismissAlly{}, state) do
    {:noreply, state}
  end

  defp handle_packet(%Client.AllyLeave{}, state) do
    {:noreply, state}
  end

  # ---- M68: Sub-class ---------------------------------------------------------

  defp handle_packet(%Client.RequestSubclassInfo{}, state) do
    subclasses =
      if state.subclasses == [] do
        CharacterSubclass.load_for_character(state.char_db_id)
      else
        state.subclasses
      end

    send(
      state.conn_pid,
      {:send_packet,
       %Server.ExSubclassInfo{
         subclasses: subclasses,
         active_index: state.active_subclass || 0
       }}
    )

    {:noreply, %{state | subclasses: subclasses}}
  end

  defp handle_packet(%Client.RequestSubclassChange{class_index: class_index}, state) do
    do_subclass_change(class_index, state)
  end

  defp handle_packet(%Client.RequestExAddSubclass{class_id: new_class_id}, state) do
    sub_count = length(state.subclasses)

    if sub_count < 3 && L2E.Data.SubclassData.valid_subclass?(state.class_id, new_class_id) do
      next_index = sub_count + 1

      case CharacterSubclass.add(state.char_db_id, new_class_id, next_index) do
        {:ok, new_sub} ->
          updated_subs = state.subclasses ++ [new_sub]

          send(
            state.conn_pid,
            {:send_packet,
             %Server.ExSubclassInfo{
               subclasses: updated_subs,
               active_index: state.active_subclass || 0
             }}
          )

          {:noreply, %{state | subclasses: updated_subs}}

        _ ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  # ---- M69: Duel --------------------------------------------------------------

  defp handle_packet(
         %Client.RequestDuelStart{target_name: target_name, party_duel: party_duel},
         state
       ) do
    if DuelManager.in_duel?(state.char_id) do
      {:noreply, state}
    else
      case Registry.lookup(L2E.Session.Registry, target_name) do
        [{target_pid, _}] ->
          send(target_pid, {:duel_invite, state.char_id, state.char_name, party_duel})

        [] ->
          Logger.debug("[PlayerSession] DuelStart: #{target_name} not online")
      end

      {:noreply, state}
    end
  end

  defp handle_packet(%Client.RequestDuelAnswerStart{response: response}, state) do
    case state.pending_duel do
      nil ->
        {:noreply, state}

      {inviter_id, _inviter_name, party_duel} ->
        if response == 1 do
          case Registry.lookup(L2E.Session.Registry, inviter_id) do
            [{inviter_pid, _}] ->
              duel_id = DuelManager.new_duel_id()
              L2E.Duel.Supervisor.start_duel(duel_id, inviter_pid, self())

              send(inviter_pid, {:duel_start, duel_id, party_duel})
              send(self(), {:duel_start, duel_id, party_duel})

            [] ->
              Logger.debug("[PlayerSession] DuelAnswer: inviter #{inviter_id} not online")
          end
        end

        {:noreply, %{state | pending_duel: nil}}
    end
  end

  defp handle_packet(%Client.RequestDuelSurrender{}, state) do
    case state.active_duel_id do
      nil ->
        {:noreply, state}

      duel_id ->
        L2E.Duel.Session.surrender(duel_id, state.char_id)
        {:noreply, state}
    end
  end

  # ---- M70: Olympiad ----------------------------------------------------------

  defp handle_packet(%Client.RequestOlympiadMatchList{}, state) do
    mode = if OlympiadManager.active?(), do: 3, else: 0
    send(state.conn_pid, {:send_packet, %Server.ExOlympiadMode{mode: mode}})
    {:noreply, state}
  end

  # ---- M71: Siege -------------------------------------------------------------
  # RequestSiegeInfo (0x47) has no body in Interlude — just acknowledges.
  # Return basic info for all castles in a future pass; for now, no-op.

  defp handle_packet(%Client.RequestSiegeInfo{}, state) do
    {:noreply, state}
  end

  # ---- M72: Pet ---------------------------------------------------------------

  defp handle_packet(%Client.RequestPetUseItem{object_id: object_id}, state) do
    case state.pet_pid do
      nil ->
        {:noreply, state}

      pet_pid ->
        send(pet_pid, {:use_item, object_id})
        L2E.Pet.Session.feed(pet_pid, 10)
        {:noreply, state}
    end
  end

  defp handle_packet(%Client.RequestPetGetItem{object_id: object_id}, state) do
    case state.pet_pid do
      nil ->
        {:noreply, state}

      pet_pid ->
        send(pet_pid, {:pickup_item, object_id})
        {:noreply, state}
    end
  end

  defp handle_packet(packet, state) do
    Logger.debug("[PlayerSession] Unhandled packet: #{inspect(packet.__struct__)}")
    {:noreply, state}
  end

  # -----------------------------------------------------------------------
  # Region helpers
  # -----------------------------------------------------------------------

  defp enter_region(state) do
    region_pid = Region.get_or_start(state.position)

    entity_info = %{
      char_id: state.char_id,
      char_name: state.char_name,
      position: state.position,
      heading: state.heading,
      hp: trunc(state.hp),
      max_hp: trunc(state.max_hp)
    }

    {existing, npc_packets} = GenServer.call(region_pid, {:player_enter, self(), entity_info})

    # Send existing players to this client
    for info <- existing do
      packet = %Server.CharInfo{
        char_id: info.char_id,
        char_name: info.char_name,
        x: elem(info.position, 0),
        y: elem(info.position, 1),
        z: elem(info.position, 2),
        heading: info.heading
      }

      send(state.conn_pid, {:send_packet, packet})
    end

    # Send nearby NPCs to this client
    for npc_pkt <- npc_packets do
      send(state.conn_pid, {:send_packet, npc_pkt})
    end

    region_pid
  end

  defp leave_region(%{region_pid: nil}), do: :ok

  defp leave_region(%{region_pid: region_pid, char_id: char_id}) do
    GenServer.cast(region_pid, {:player_leave, char_id, self()})
  end

  # -----------------------------------------------------------------------
  # DB helpers
  # -----------------------------------------------------------------------

  defp list_characters(username) when is_binary(username) do
    Repo.all(from(c in Character, where: c.account_name == ^username, order_by: c.inserted_at))
  end

  defp build_char_select_info(username) do
    chars = list_characters(username)

    char_maps =
      Enum.map(chars, fn c ->
        %{
          name: c.name,
          object_id: c.id,
          class_id: c.class_id,
          race: c.race,
          sex: c.sex,
          level: c.level,
          exp: c.exp,
          sp: c.sp,
          hp: c.hp,
          max_hp: c.max_hp,
          mp: c.mp,
          max_mp: c.max_mp,
          x: c.x,
          y: c.y,
          z: c.z,
          karma: 0,
          hair_style: c.hair_style,
          hair_color: c.hair_color,
          face: c.face,
          is_active: true
        }
      end)

    %Server.CharSelectInfo{
      login_name: username,
      session_id: :rand.uniform(0x7FFFFFFF),
      characters: char_maps
    }
  end

  # Persist the character's current position + vitals to DB before shutdown.
  defp persist_position(%{char_db_id: nil}), do: :ok

  defp persist_position(%{char_db_id: char_db_id, position: {x, y, z}, heading: h} = state) do
    Repo.update_all(
      from(c in Character, where: c.id == ^char_db_id),
      set: [
        x: x,
        y: y,
        z: z,
        heading: h,
        hp: state.hp,
        mp: state.mp,
        exp: state.exp,
        sp: state.sp,
        level: state.level,
        karma: state.karma,
        pvp_kills: state.pvp_kills,
        pk_kills: state.pk_kills
      ]
    )
  end

  # -----------------------------------------------------------------------
  # Combat helpers
  # -----------------------------------------------------------------------

  defp start_auto_attack(%{target_id: nil} = state), do: state

  defp start_auto_attack(state) do
    cancel_timer(state.attack_timer)

    if npc_pid = find_npc_pid(state.target_id) do
      L2E.NPC.Instance.add_hate(npc_pid, self(), 1)
    end

    timer = schedule_attack(state)
    %{state | attacking: true, attack_timer: timer}
  end

  defp schedule_attack(state) do
    atk_ms = atk_speed_ms(state)
    Process.send_after(self(), :auto_attack_tick, atk_ms)
  end

  defp atk_speed_ms(%{stats: %{atk_speed: spd}}) when spd > 0 do
    # atk_speed is swings-per-minute equivalent; 500 = 1 swing/s base
    round(500 / (spd / 500.0) * 1000 / 500)
  end

  defp atk_speed_ms(_state), do: 2000

  defp player_combat_stats(%{stats: stats}) when not is_nil(stats) do
    %{
      p_atk: stats.p_atk,
      m_atk: stats.m_atk,
      p_def: stats.p_def,
      m_def: stats.m_def,
      accuracy: stats.accuracy,
      evasion: stats.evasion,
      crit_rate: stats.crit_rate,
      atk_speed: stats.atk_speed,
      level: stats.level
    }
  end

  defp player_combat_stats(_state) do
    %{
      p_atk: 10,
      m_atk: 3,
      p_def: 50,
      m_def: 20,
      accuracy: 20,
      evasion: 15,
      crit_rate: 4,
      atk_speed: 253,
      level: 1
    }
  end

  # Level color hint for target selection (0=same, positive=stronger)
  defp level_color(%{stats: %{level: my_level}}, _target_id) do
    # TODO: look up target level for proper color; for now return 0
    _ = my_level
    0
  end

  defp level_color(_state, _target_id), do: 0

  # Look up a live NPC process by object_id
  defp find_npc_pid(object_id) do
    case Registry.lookup(L2E.Session.Registry, {:npc, object_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp find_player_pid(char_id) do
    case Registry.lookup(L2E.Session.Registry, char_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  # Returns true if `pid` is a registered PlayerSession (not an NPC or other process)
  defp player_pid?(pid) when is_pid(pid) do
    Registry.keys(L2E.Session.Registry, pid) != []
  end

  defp player_pid?(_), do: false

  # Broadcast current UserInfo to this player (and nearby via region if needed)
  defp broadcast_user_info(%{auth_state: :in_world} = state) do
    pkt = %Server.UserInfo{
      char_id: state.char_id,
      char_name: state.char_name,
      x: elem(state.position, 0),
      y: elem(state.position, 1),
      z: elem(state.position, 2),
      heading: state.heading,
      hp: trunc(state.hp),
      max_hp: state.max_hp,
      pvp_flag: state.pvp_flag,
      karma: state.karma
    }

    send(state.conn_pid, {:send_packet, pkt})
  end

  defp broadcast_user_info(_state), do: :ok

  # ---- M45: Class Advancement -----------------------------------------------

  defp do_class_change(state, target_class_id) do
    if ClassAdvancementTable.can_advance?(state.class_id || 0, target_class_id, state.level) do
      # Persist the new class_id to DB
      if state.char_db_id do
        Repo.get!(Character, state.char_db_id)
        |> Ecto.Changeset.change(%{class_id: target_class_id})
        |> Repo.update!()
      end

      # Merge starting skills (level 1 skills of new class) into player's skill map
      new_skills =
        SkillLearnTable.get_learnable_skills(target_class_id, 1)
        |> Enum.reduce(state.skills, fn %{skill_id: sid, skill_level: slvl}, acc ->
          if state.char_db_id do
            CharacterSkill.upsert_skill(state.char_db_id, sid, slvl)
          end

          Map.put(acc, sid, slvl)
        end)

      new_state = %{state | class_id: target_class_id, skills: new_skills}

      # Level-up animation (action_id 16)
      send(
        state.conn_pid,
        {:send_packet, %Server.SocialAction{object_id: state.char_id, action_id: 16}}
      )

      # Refresh UserInfo for the client
      broadcast_user_info(new_state)

      Logger.info(
        "[PlayerSession] char_id=#{state.char_id} advanced to class_id=#{target_class_id}"
      )

      {:noreply, new_state}
    else
      send(
        state.conn_pid,
        {:send_packet,
         %Server.CreatureSay{
           char_id: state.char_id,
           chat_type: 2,
           char_name: "System",
           message: "Requirements not met for this class change."
         }}
      )

      {:noreply, state}
    end
  end

  defp find_session_by_name(char_name) do
    # Iterate registry to find a session by character name
    # This is O(n) but acceptable for now; a name→id ETS table could speed this up.
    match = Registry.match(L2E.Session.Registry, :_, :_)

    Enum.find_value(match, fn {key, pid, _} ->
      case key do
        {:npc, _} ->
          nil

        {:party, _} ->
          nil

        {:party_member, _} ->
          nil

        {:clan, _} ->
          nil

        {:clan_member, _} ->
          nil

        _char_id when is_integer(key) ->
          try do
            case GenServer.call(pid, :get_party_info, 500) do
              {:ok, %{char_name: ^char_name}} -> pid
              _ -> nil
            end
          catch
            :exit, _ -> nil
          end

        _ ->
          nil
      end
    end)
  end

  defp find_session_by_id(char_id) do
    case Registry.lookup(L2E.Session.Registry, char_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  # M62: Crystal item IDs by grade (Interlude item IDs)
  defp crystal_data_for_grade(:d, count), do: {1458, max(1, count)}
  defp crystal_data_for_grade(:c, count), do: {1459, max(1, count)}
  defp crystal_data_for_grade(:b, count), do: {1460, max(1, count)}
  defp crystal_data_for_grade(:a, count), do: {1461, max(1, count)}
  defp crystal_data_for_grade(:s, count), do: {1462, max(1, count)}
  defp crystal_data_for_grade(_, _), do: {1458, 1}

  defp resolve_char_id(pid) do
    case GenServer.call(pid, :get_party_info, 500) do
      {:ok, %{char_id: id}} -> id
      _ -> 0
    end
  rescue
    _ -> 0
  end

  # M16: Open NPC dialog — send an NpcHtmlMessage with a basic dialog
  defp open_npc_dialog(npc_pid, obj_id, state) do
    npc_info = L2E.NPC.Instance.get_info(npc_pid)
    template = npc_info[:template]
    npc_name = if template, do: template.name, else: "NPC"
    npc_id = if template, do: template.npc_id, else: 0

    html =
      case L2E.Data.HtmCache.get("default/#{npc_id}.htm", %{
             "npc_name" => npc_name,
             "char_name" => state.char_name,
             "obj_id" => obj_id
           }) do
        nil -> build_default_npc_html(npc_id, obj_id, npc_name, state)
        content -> content
      end

    send(
      state.conn_pid,
      {:send_packet, %Server.NpcHtmlMessage{npc_object_id: obj_id, html: html}}
    )
  end

  defp build_default_npc_html(npc_id, obj_id, npc_name, state) do
    teleport_links =
      case TeleporterTable.get_normal(npc_id) do
        [] ->
          ""

        dests ->
          links =
            Enum.map_join(dests, "", fn d ->
              fee_str = if d.fee_count > 0, do: " (#{d.fee_count} adena)", else: ""

              "<a action=\"bypass -h npc_#{obj_id}_teleport_#{d.x}_#{d.y}_#{d.z}_#{d.fee_count}\">#{d.name}#{fee_str}</a><br>"
            end)

          "<br>[ Teleport ]<br>" <> links
      end

    trade_link =
      case BuyListTable.get_by_npc(npc_id) do
        nil -> ""
        _ -> "<a action=\"bypass -h npc_#{obj_id}_Trade\">Trade</a><br>"
      end

    warehouse_links =
      "<a action=\"bypass -h npc_#{obj_id}_warehouse_deposit\">Warehouse Deposit</a><br>" <>
        "<a action=\"bypass -h npc_#{obj_id}_warehouse_withdraw\">Warehouse Withdraw</a><br>"

    clan_warehouse_links =
      if state.clan_id != 0 do
        "<a action=\"bypass -h npc_#{obj_id}_clan_warehouse_deposit\">Clan WH Deposit</a><br>" <>
          "<a action=\"bypass -h npc_#{obj_id}_clan_warehouse_withdraw\">Clan WH Withdraw</a><br>"
      else
        ""
      end

    """
    <html><body>
    <title>#{npc_name}</title>
    <br>
    Hello, #{state.char_name}.<br>
    How can I help you?<br>
    #{trade_link}
    #{warehouse_links}
    #{clan_warehouse_links}
    #{teleport_links}
    </body></html>
    """
  end

  # M16: Handle bypass commands from NPC dialogs
  defp handle_bypass(cmd, state) do
    cond do
      String.starts_with?(cmd, "npc_") ->
        # e.g. "npc_12345_Trade" or "npc_12345_teleport_x_y_z_fee"
        case String.split(cmd, "_", parts: 3) do
          ["npc", npc_id_str, action] ->
            npc_id = String.to_integer(npc_id_str)
            handle_npc_bypass(npc_id, action, state)

          _ ->
            {:noreply, state}
        end

      String.starts_with?(cmd, "admin_") and state.access_level > 0 ->
        case L2E.Admin.CommandHandler.parse(cmd) do
          {:ok, {:spawn_npc, npc_id}} ->
            {x, y, z} = state.position
            L2E.NPC.SpawnTable.admin_spawn(npc_id, x, y, z)
            {:noreply, state}

          {:ok, {:teleport, x, y, z}} ->
            {:noreply, do_teleport({x, y, z}, state)}

          {:ok, {:kick, char_name}} ->
            case Repo.get_by(Character, name: char_name) do
              %Character{id: kicked_id} ->
                case Registry.lookup(L2E.Session.Registry, kicked_id) do
                  [{pid, _}] -> GenServer.cast(pid, :connection_closed)
                  _ -> :ok
                end

              nil ->
                :ok
            end

            {:noreply, state}

          {:ok, :toggle_invisible} ->
            {:noreply, %{state | invisible: !state.invisible}}

          :ignored ->
            {:noreply, state}
        end

      String.starts_with?(cmd, "ClassChange ") ->
        target_class_id =
          cmd
          |> String.split(" ", parts: 2)
          |> List.last()
          |> String.to_integer()

        do_class_change(state, target_class_id)

      cmd == "ClassList" ->
        transitions = ClassAdvancementTable.get_transitions(state.class_id || 0)

        html =
          if transitions == [] do
            "<html><body>No class changes are available for your current class.</body></html>"
          else
            links =
              Enum.map_join(transitions, "", fn t ->
                ~s[<a action="bypass ClassChange #{t.target_class_id}">#{t.name} (Level #{t.min_level}+)</a><br>]
              end)

            "<html><body>Choose your class advancement:<br>" <> links <> "</body></html>"
          end

        send(state.conn_pid, {:send_packet, %Server.NpcHtmlMessage{npc_object_id: 0, html: html}})
        {:noreply, state}

      String.starts_with?(cmd, "Quest ") ->
        "Quest " <> rest = cmd

        case String.split(rest, " ", parts: 2) do
          [npc_template_id_str | _] ->
            case Integer.parse(npc_template_id_str) do
              {npc_template_id, _} ->
                player_info = %{
                  char_id: state.char_id,
                  level: state.level,
                  class_id: state.class_id
                }

                {html, new_quests} =
                  L2E.Quest.Handler.dispatch_talk(
                    state.target_id || 0,
                    npc_template_id,
                    player_info,
                    state.quests
                  )

                if html do
                  send(
                    state.conn_pid,
                    {:send_packet,
                     %Server.NpcHtmlMessage{
                       npc_object_id: state.target_id || 0,
                       html: html
                     }}
                  )
                end

                {:noreply, %{state | quests: new_quests}}

              _ ->
                {:noreply, state}
            end

          _ ->
            {:noreply, state}
        end

      true ->
        {:noreply, state}
    end
  end

  defp handle_npc_bypass(npc_id, "Trade", state) do
    buy_list_items =
      case BuyListTable.get_by_npc(npc_id) do
        nil -> []
        items -> Enum.map(items, &%{item_id: &1.item_id, price: &1.price})
      end

    adena_count = Inventory.get_adena_count(state.char_id)

    send(
      state.conn_pid,
      {:send_packet,
       %Server.BuyList{
         npc_object_id: npc_id,
         my_adena: adena_count,
         items: buy_list_items
       }}
    )

    {:noreply, state}
  end

  # M25: Teleport bypass — "teleport_x_y_z_fee"
  defp handle_npc_bypass(_npc_id, "teleport_" <> rest, state) do
    case String.split(rest, "_") do
      [x_str, y_str, z_str, fee_str] ->
        x = String.to_integer(x_str)
        y = String.to_integer(y_str)
        z = String.to_integer(z_str)
        fee = String.to_integer(fee_str)

        adena = Inventory.get_adena_count(state.char_id)

        if adena >= fee do
          Inventory.spend_adena(state.char_id, fee)
          new_state = do_teleport({x, y, z}, state)
          {:noreply, new_state}
        else
          {:noreply, state}
        end

      _ ->
        {:noreply, state}
    end
  end

  defp handle_npc_bypass(_npc_id, "warehouse_deposit", state) do
    items = Inventory.get_items(state.char_id)

    adena =
      Enum.find_value(items, 0, fn {inst, _tmpl} ->
        if inst.item_id == 57, do: inst.count || 0, else: nil
      end)

    # Filter: adena (57) cannot be deposited
    depositable =
      Enum.reject(items, fn {inst, _} -> inst.item_id == 57 end)
      |> Enum.map(fn {inst, _tmpl} -> inst end)

    pkt = %Server.WareHouseDepositList{
      player_adena: adena,
      items: depositable
    }

    send(state.conn_pid, {:send_packet, pkt})
    {:noreply, %{state | warehouse_context: :personal}}
  end

  defp handle_npc_bypass(_npc_id, "warehouse_withdraw", state) do
    wh_items = Warehouse.list(state.char_id)

    pkt = %Server.WareHouseWithdrawList{items: wh_items}
    send(state.conn_pid, {:send_packet, pkt})
    {:noreply, %{state | warehouse_context: :personal}}
  end

  defp handle_npc_bypass(_npc_id, "clan_warehouse_deposit", state) when state.clan_id != 0 do
    items = Inventory.get_items(state.char_id)

    adena =
      Enum.find_value(items, 0, fn {inst, _tmpl} ->
        if inst.item_id == 57, do: inst.count || 0, else: nil
      end)

    depositable =
      Enum.reject(items, fn {inst, _} -> inst.item_id == 57 end)
      |> Enum.map(fn {inst, _tmpl} -> inst end)

    pkt = %Server.WareHouseDepositList{
      player_adena: adena,
      items: depositable
    }

    send(state.conn_pid, {:send_packet, pkt})
    {:noreply, %{state | warehouse_context: :clan}}
  end

  defp handle_npc_bypass(_npc_id, "clan_warehouse_withdraw", state) when state.clan_id != 0 do
    clan_items = L2E.Warehouse.ClanWarehouse.list(state.clan_id)
    pkt = %Server.WareHouseWithdrawList{items: clan_items}
    send(state.conn_pid, {:send_packet, pkt})
    {:noreply, %{state | warehouse_context: :clan}}
  end

  defp handle_npc_bypass(_npc_id, action, state)
       when action in ["clan_warehouse_deposit", "clan_warehouse_withdraw"] do
    # Player has no clan
    {:noreply, state}
  end

  defp handle_npc_bypass(_npc_id, _action, state), do: {:noreply, state}

  # Execute a teleport: leave current region, move to new coords, enter new region
  defp do_teleport({x, y, z}, state) do
    # Leave current region
    if state.region_pid do
      Region.remove_entity(state.region_pid, {:player, state.char_id})
    end

    new_region_pid = Region.get_or_start({x, y})
    Region.add_entity(new_region_pid, {:player, state.char_id}, self())

    send(
      state.conn_pid,
      {:send_packet, %Server.TeleportToLocation{object_id: state.char_id, x: x, y: y, z: z}}
    )

    %{state | position: {x, y, z}, region_pid: new_region_pid}
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  # M37: Drop a random subset of inventory items on death when karma > 0
  defp maybe_drop_karma_items(%{karma: 0}), do: :ok

  defp maybe_drop_karma_items(%{
         karma: karma,
         char_id: char_id,
         position: pos,
         region_pid: region_pid
       }) do
    drop_chance = min(4 + div(karma, 1000), 40)
    {x, y, z} = pos

    Inventory.get_items(char_id)
    |> Enum.each(fn {instance, _template} ->
      if not instance.is_equipped and :rand.uniform(100) <= drop_chance do
        count = instance.count || 1

        case Inventory.remove_item(char_id, instance.id, count) do
          {:ok, _, _} ->
            if region_pid do
              obj_id = :erlang.unique_integer([:positive, :monotonic])
              GenServer.cast(region_pid, {:drop_item, obj_id, instance.item_id, x, y, z, count})
            end

          _ ->
            :ok
        end
      end
    end)
  end

  # M39: Consume one soulshot/spiritshot and boost p_atk by 1.5x if equipped
  defp consume_shot_and_boost(%{autoshot_item_id: nil}, stats), do: stats

  defp consume_shot_and_boost(%{autoshot_item_id: item_id, char_id: char_id}, stats) do
    case Enum.find(Inventory.get_items(char_id), fn {inst, _} -> inst.item_id == item_id end) do
      nil ->
        stats

      {inst, _} ->
        Inventory.remove_item(char_id, inst.id, 1)
        %{stats | p_atk: round(stats.p_atk * 1.5)}
    end
  end

  # M35: Validate buyer's requested items against the seller's store list
  defp validate_store_items(seller_pid, req_items) do
    {_seller_char_id, store_list} = GenServer.call(seller_pid, :get_store_list)

    result =
      Enum.reduce_while(req_items, {:ok, 0, []}, fn req, {:ok, acc_cost, acc_items} ->
        case Enum.find(store_list, fn entry -> entry.object_id == req.object_id end) do
          nil ->
            {:halt, :not_in_store}

          entry ->
            if req.price != entry.price or req.count > entry.count do
              {:halt, :price_mismatch}
            else
              line_cost = entry.price * req.count

              validated = %{
                obj_id: entry.object_id,
                item_id: entry.item_id,
                count: req.count,
                price: entry.price
              }

              {:cont, {:ok, acc_cost + line_cost, [validated | acc_items]}}
            end
        end
      end)

    case result do
      {:ok, total, items} -> {:ok, total, Enum.reverse(items)}
      err -> {:error, err}
    end
  end

  defp check_buyer_adena(char_id, cost) do
    if Inventory.get_adena_count(char_id) >= cost, do: :ok, else: {:error, :insufficient_adena}
  end

  # M43: Validate that a seller's offered items match the owner's buy list.
  # Returns {:ok, total_cost, validated_items} or {:error, reason}.
  defp validate_buy_from_request(buy_list, items) do
    result =
      Enum.reduce_while(items, {:ok, 0, []}, fn item, {:ok, acc_cost, acc_valid} ->
        case Enum.find(buy_list, fn e -> e.item_id == item.item_id end) do
          nil ->
            {:halt, {:error, :item_not_in_buy_list}}

          entry ->
            if item.count > entry.count do
              {:halt, {:error, :count_exceeds_buy_list}}
            else
              cost = entry.price * item.count

              validated = %{
                item_id: item.item_id,
                count: item.count,
                price: entry.price,
                object_id: Map.get(item, :object_id, 0)
              }

              {:cont, {:ok, acc_cost + cost, [validated | acc_valid]}}
            end
        end
      end)

    case result do
      {:ok, total, validated} -> {:ok, total, Enum.reverse(validated)}
      err -> err
    end
  end

  # M43: Subtract sold counts from the buy list; remove fully-filled entries.
  defp reduce_buy_list(buy_list, sold_items) do
    sold_map = Map.new(sold_items, fn item -> {item.item_id, item.count} end)

    buy_list
    |> Enum.map(fn entry ->
      sold = Map.get(sold_map, entry.item_id, 0)
      %{entry | count: entry.count - sold}
    end)
    |> Enum.reject(fn entry -> entry.count <= 0 end)
  end

  # M43: Check the seller actually holds all offered items (prevents phantom sells).
  defp validate_seller_has_items(char_id, items) do
    inv_items = Inventory.get_items(char_id)
    inv_map = Map.new(inv_items, fn {inst, _} -> {inst.id, inst.count || 1} end)

    Enum.all?(items, fn item ->
      obj_id = Map.get(item, :object_id, 0)
      Map.get(inv_map, obj_id, 0) >= Map.get(item, :count, 1)
    end)
  end

  # -----------------------------------------------------------------------
  # Inventory helpers
  # -----------------------------------------------------------------------

  defp stop_inventory(%{char_id: nil}), do: :ok

  defp stop_inventory(%{char_id: char_id}) do
    try do
      GenServer.stop(Inventory.via_tuple(char_id), :normal)
    catch
      :exit, _ -> :ok
    end
  end

  defp recalculate_stats_with_equipment(state) do
    template = ClassTemplates.get_or_default(state.class_id)
    base_stats = Stats.compute(template, state.level)
    bonuses = Inventory.get_equip_bonuses(state.char_id)
    new_stats = base_stats |> Stats.apply_equipment(bonuses) |> Stats.apply_buffs(state.buffs)

    status_pkt = Server.StatusUpdate.from_char_stats(state.char_id, new_stats, state.hp, state.mp)
    send(state.conn_pid, {:send_packet, status_pkt})

    %{state | stats: new_stats}
  end

  defp apply_item_effect(state, template) do
    cond do
      template.hp_restore > 0 ->
        new_hp = min(state.hp + template.hp_restore, state.max_hp)

        send(
          state.conn_pid,
          {:send_packet, Server.StatusUpdate.hp_mp(state.char_id, new_hp, state.mp)}
        )

        %{state | hp: new_hp}

      template.mp_restore > 0 ->
        new_mp = min(state.mp + template.mp_restore, state.max_mp)

        send(
          state.conn_pid,
          {:send_packet, Server.StatusUpdate.hp_mp(state.char_id, state.hp, new_mp)}
        )

        %{state | mp: new_mp}

      true ->
        state
    end
  end

  defp change_type_to_int(:added), do: 1
  defp change_type_to_int(:modified), do: 2
  defp change_type_to_int(:removed), do: 3

  # Checks whether the item's grade matches the enchant scroll's target_grade string.
  # Item template has a :grade field (:S, :A, :B, :C, :D, or :none).
  defp grades_match?(item_tmpl, target_grade_str) do
    item_grade =
      case Map.get(item_tmpl, :grade, :none) do
        g when is_atom(g) -> Atom.to_string(g) |> String.upcase()
        g when is_binary(g) -> String.upcase(g)
        _ -> "NONE"
      end

    item_grade == String.upcase(target_grade_str)
  end

  # -----------------------------------------------------------------------
  # Skill helpers
  # -----------------------------------------------------------------------

  # Default skill set: all characters get these 5 skills in M8.
  # Per-class skill assignment will be done in M16.
  @default_skills %{1 => 1, 3 => 1, 4 => 1, 68 => 1, 84 => 1}

  defp load_char_skills(char_id) do
    case CharacterSkill.load_for_character(char_id) do
      [] -> @default_skills
      rows -> Map.new(rows, fn s -> {s.skill_id, s.skill_level} end)
    end
  end

  # M47: Load all quest rows for this character into the in-memory quests map.
  defp load_char_shortcuts(char_id) do
    L2E.DB.CharacterShortcut.load_for_character(char_id)
  end

  # M56: Persist henna slot changes to the characters table.
  defp update_henna_in_db(char_id, hennas) do
    Repo.update_all(
      from(c in Character, where: c.id == ^char_id),
      set: [
        henna1: Map.get(hennas, 1),
        henna2: Map.get(hennas, 2),
        henna3: Map.get(hennas, 3)
      ]
    )
  end

  # M56: Build a HennaInfo server packet from the current henna slot map.
  defp build_henna_info_packet(hennas) do
    henna_list =
      Enum.flat_map(1..3, fn slot ->
        case Map.get(hennas, slot) do
          nil -> []
          hid -> [L2E.Data.HennaTable.get(hid)]
        end
      end)
      |> Enum.filter(& &1)

    {int_bonus, str_bonus, con_bonus, men_bonus, dex_bonus, wit_bonus} =
      Enum.reduce(henna_list, {0, 0, 0, 0, 0, 0}, fn h, {i, s, c, m, d, w} ->
        sb = Map.get(h.stat_bonus, :str, 0)
        db = Map.get(h.stat_bonus, :dex, 0)
        cb = Map.get(h.stat_bonus, :con, 0)
        ib = Map.get(h.stat_bonus, :int, 0)
        wb = Map.get(h.stat_bonus, :wit, 0)
        mb = Map.get(h.stat_bonus, :men, 0)
        {i + ib, s + sb, c + cb, m + mb, d + db, w + wb}
      end)

    entries =
      Enum.map(henna_list, fn h ->
        %{henna_id: h.henna_id, dye_id: h.dye_id}
      end)

    %Server.HennaInfo{
      int_bonus: int_bonus,
      str_bonus: str_bonus,
      con_bonus: con_bonus,
      men_bonus: men_bonus,
      dex_bonus: dex_bonus,
      wit_bonus: wit_bonus,
      hennas: entries
    }
  end

  defp load_char_quests(char_id) do
    CharacterQuest.load_for_character(char_id)
    |> Enum.into(%{}, fn q ->
      {q.quest_id, %{state: q.state, cond: q.cond, count: q.count, reward_taken: q.reward_taken}}
    end)
  end

  # ---------------------------------------------------------------------------
  # Sub-class switch: saves current sub state, loads target sub state + skills
  # ---------------------------------------------------------------------------
  defp do_subclass_change(target_index, state) do
    target = Enum.find(state.subclasses, fn s -> s.class_index == target_index end)
    current_index = state.active_subclass || 0

    cond do
      is_nil(target) ->
        {:noreply, state}

      target.class_index == current_index ->
        {:noreply, state}

      true ->
        # 1. Persist current sub's level/exp/sp + skills
        CharacterSubclass.save(
          state.char_db_id,
          current_index,
          state.level,
          state.exp,
          state.sp
        )

        CharacterSubclass.save_skills(state.char_db_id, current_index, state.skills)

        # 2. Load target sub's skills (snapshot or empty if first time)
        new_skills =
          case CharacterSubclass.load_skills(state.char_db_id, target_index) do
            nil -> %{}
            skills -> skills
          end

        # 3. Build new state with target sub's stats + skills
        new_state = %{
          state
          | level: target.level,
            exp: target.exp,
            sp: target.sp,
            class_id: target.class_id,
            active_subclass: target_index,
            skills: new_skills
        }

        # 4. Broadcast updated sub info + skills + user info
        send(state.conn_pid, {:send_packet, %Server.ExSubclassInfo{
          subclasses: state.subclasses,
          active_index: target_index
        }})

        send(state.conn_pid, {:send_packet, build_skill_list_packet(new_skills)})

        {:noreply, new_state}
    end
  end

  defp build_skill_list_packet(skills) do
    skill_maps =
      Enum.map(skills, fn {skill_id, level} ->
        template = TemplateTable.get(skill_id, level)
        passive = template && template.type == :passive

        %{skill_id: skill_id, level: level, passive: passive || false, disabled: false}
      end)

    %Server.SkillList{skills: skill_maps}
  end

  defp level_from_skills(skills, skill_id) do
    Map.get(skills, skill_id, 1)
  end

  defp fetch_skill_template(skill_id, level) do
    case TemplateTable.get(skill_id, level) do
      nil -> {:error, :not_found}
      template -> {:ok, template}
    end
  end

  defp check_not_casting(%{casting: true}), do: {:error, :casting}
  defp check_not_casting(_state), do: :ok

  defp check_cooldown(cooldowns, skill_id) do
    now = System.monotonic_time(:millisecond)
    expires = Map.get(cooldowns, skill_id, 0)

    if now >= expires, do: :ok, else: {:error, :on_cooldown}
  end

  defp check_mp(current_mp, mp_cost) when current_mp >= mp_cost, do: :ok
  defp check_mp(_current_mp, _mp_cost), do: {:error, :no_mp}

  # Returns stats map for a target — NPC or a player with fallback defaults.
  defp get_target_stats(target_id, state) do
    cond do
      target_id == state.char_id ->
        player_combat_stats(state)

      npc_pid = find_npc_pid(target_id) ->
        L2E.NPC.Instance.get_stats(npc_pid)

      true ->
        %{p_def: 50, m_def: 20}
    end
  end

  # Deals damage to an NPC or player target.
  defp deal_damage_to_target(target_id, damage, state) do
    case find_npc_pid(target_id) do
      nil -> :ok
      npc_pid -> L2E.NPC.Instance.take_damage(npc_pid, damage, self())
    end

    _ = {target_id, damage, state}
    :ok
  end

  # M49: Send CC to target (NPC or player)
  defp apply_cc_to_target(target_id, cc_type, duration_ms, state) do
    case find_npc_pid(target_id) do
      nil ->
        case Registry.lookup(L2E.Session.Registry, target_id) do
          [{pid, _}] -> GenServer.cast(pid, {:apply_cc, cc_type, duration_ms})
          [] -> :ok
        end

      npc_pid ->
        L2E.NPC.Instance.apply_cc(npc_pid, cc_type, duration_ms)
    end

    _ = state
    :ok
  end

  # M49: Send DoT to target (NPC or player)
  defp apply_dot_to_target(
         target_id,
         skill_id,
         level,
         damage_per_tick,
         tick_ms,
         ticks_left,
         state
       ) do
    case find_npc_pid(target_id) do
      nil ->
        case Registry.lookup(L2E.Session.Registry, target_id) do
          [{pid, _}] ->
            GenServer.cast(
              pid,
              {:apply_dot, skill_id, level, damage_per_tick, tick_ms, ticks_left}
            )

          [] ->
            :ok
        end

      npc_pid ->
        L2E.NPC.Instance.apply_dot(npc_pid, skill_id, damage_per_tick, tick_ms, ticks_left)
    end

    _ = state
    :ok
  end

  # -----------------------------------------------------------------------
  # Initial equipment helpers
  # -----------------------------------------------------------------------

  # Per-class starting item list: [{item_id, count, equipped}]
  @initial_equipment %{
    0 => [{2369, 1, true}, {10, 1, false}, {1146, 1, true}, {1147, 1, true}, {5588, 1, false}],
    10 => [{6, 1, true}, {425, 1, true}, {461, 1, true}, {5588, 1, false}],
    18 => [{2369, 1, true}, {10, 1, false}, {1146, 1, true}, {1147, 1, true}, {5588, 1, false}],
    25 => [{6, 1, true}, {425, 1, true}, {461, 1, true}, {5588, 1, false}],
    31 => [{2369, 1, true}, {10, 1, false}, {1146, 1, true}, {1147, 1, true}, {5588, 1, false}],
    38 => [{6, 1, true}, {425, 1, true}, {461, 1, true}, {5588, 1, false}],
    44 => [{2369, 1, false}, {2368, 1, true}, {1146, 1, true}, {1147, 1, true}, {5588, 1, false}],
    49 => [{2368, 1, true}, {425, 1, true}, {461, 1, true}, {5588, 1, false}],
    53 => [{2370, 1, true}, {10, 1, false}, {1146, 1, true}, {1147, 1, true}, {5588, 1, false}]
  }

  defp grant_initial_equipment(char_id, class_id) do
    items = Map.get(@initial_equipment, class_id, [])

    Enum.each(items, fn {item_id, count, equipped} ->
      slot =
        if equipped do
          case ItemTemplateTable.get(item_id) do
            %{slot: s} when not is_nil(s) -> Atom.to_string(s)
            _ -> nil
          end
        end

      Repo.insert!(%Item{
        char_id: char_id,
        item_id: item_id,
        count: count,
        enchant_level: 0,
        is_equipped: equipped && slot != nil,
        slot: slot
      })
    end)
  end

  # M55-B: Zone enter/exit event handler
  defp handle_zone_change(%{zone_type: same} = state, same), do: state

  defp handle_zone_change(state, new_zone) do
    # Cancel existing damage tick timer if leaving a damage/swamp zone
    state =
      if state.zone_type in [:damage, :swamp] and new_zone not in [:damage, :swamp] do
        if state.zone_damage_timer, do: Process.cancel_timer(state.zone_damage_timer)
        %{state | zone_damage_timer: nil}
      else
        state
      end

    # Start damage tick if entering damage/swamp zone
    state =
      if new_zone in [:damage, :swamp] and state.zone_type not in [:damage, :swamp] do
        tick_ms = if new_zone == :damage, do: 2000, else: 4000
        timer = Process.send_after(self(), {:zone_damage_tick, new_zone}, tick_ms)
        %{state | zone_damage_timer: timer}
      else
        state
      end

    # Broadcast zone change via PubSub for AOI system
    Phoenix.PubSub.broadcast(
      L2E.PubSub,
      "player:#{state.char_id}",
      {:zone_changed, state.zone_type, new_zone}
    )

    %{state | zone_type: new_zone, in_water: new_zone == :water}
  end
end
