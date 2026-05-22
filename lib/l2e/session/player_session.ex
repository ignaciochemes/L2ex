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

  alias L2E.{Repo, DB.Character, DB.Item}
  alias L2E.Packet.Server
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
      # [{skill_id, level}]
      skills: [],
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
      # Current zone type at player's position (:normal | :peace | :pvp | :siege | :no_pvp | :other)
      zone_type: :normal,
      # PvP state
      pvp_flag: 0,
      karma: 0,
      pvp_kills: 0,
      pk_kills: 0,
      pvp_flag_timer: nil,
      # Regen tick timer (3-second interval when alive)
      regen_timer: nil,
      # Auto-save timer (5-minute interval)
      save_timer: nil
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

      Process.send_after(self(), :respawn, @respawn_ms)
      {:noreply, %{new_state | dead: true, attacking: false, attack_timer: nil, regen_timer: nil}}
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
  def handle_cast({:player_killed, _victim_pid, victim_pvp_flag, victim_karma, victim_level}, state) do
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
            my_stats = player_combat_stats(state)
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
        my_stats = player_combat_stats(state)
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

  # -----------------------------------------------------------------------
  # Packet handlers (auth state machine)
  # -----------------------------------------------------------------------

  # ---- AuthLogin (state :protocol_ok) ------------------------------------

  defp handle_packet(%L2E.Packet.Client.AuthLogin{} = pkt, %{auth_state: :protocol_ok} = state) do
    case L2E.LoginServer.AccountStore.pop(pkt.login_name, pkt.play_ok1, pkt.play_ok2) do
      {:ok, _session_key} ->
        Logger.info("[PlayerSession] AuthLogin ok for #{pkt.login_name}")
        new_state = %{state | username: pkt.login_name, auth_state: :authenticated}
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
            auth_state: :char_selected
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

    region_pid = enter_region(new_state)

    regen_timer = Process.send_after(self(), :regen_tick, 3_000)
    save_timer = Process.send_after(self(), :auto_save, 300_000)

    Logger.info(
      "[PlayerSession] #{char_name} (id=#{char_id}) entered the world (class=#{state.class_id}, level=#{state.level})"
    )

    {:noreply, %{new_state | region_pid: region_pid, skills: skills,
                             regen_timer: regen_timer, save_timer: save_timer}}
  end

  # ---- MoveToLocation (state :in_world) ----------------------------------

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
    zone_type = ZoneTable.zone_type_at(x, y, z)
    {:noreply, %{state | position: {x, y, z}, heading: h, zone_type: zone_type}}
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
          nil -> :ok
          npc_pid -> open_npc_dialog(npc_pid, obj_id, state)
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

  # ---- UseItem (0x19) — equip/consume an item ----------------------------

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
      {:ok, {instance, template}} ->
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
      {:ok, {instance, template}} ->
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
      case Warehouse.withdraw(state.char_id, inst_id, qty) do
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
          case Warehouse.deposit(state.char_id, inst.item_id, qty, inst.enchant_level || 0) do
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

    html = """
    <html><body>
    <title>#{npc_name}</title>
    <br>
    Hello, #{state.char_name}.<br>
    How can I help you?<br>
    #{trade_link}
    #{warehouse_links}
    #{teleport_links}
    </body></html>
    """

    send(
      state.conn_pid,
      {:send_packet, %Server.NpcHtmlMessage{npc_object_id: obj_id, html: html}}
    )
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
    {:noreply, state}
  end

  defp handle_npc_bypass(_npc_id, "warehouse_withdraw", state) do
    wh_items = Warehouse.list(state.char_id)

    pkt = %Server.WareHouseWithdrawList{items: wh_items}
    send(state.conn_pid, {:send_packet, pkt})
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
  @default_skills [{1, 1}, {3, 1}, {4, 1}, {68, 1}, {84, 1}]

  defp load_char_skills(char_id) do
    case Repo.all(
           from(s in "char_skills",
             where: s.char_id == ^char_id,
             select: {s.skill_id, s.level}
           )
         ) do
      [] -> @default_skills
      rows -> rows
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
    case Enum.find(skills, fn {id, _lvl} -> id == skill_id end) do
      {_id, lvl} -> lvl
      nil -> 1
    end
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
end
