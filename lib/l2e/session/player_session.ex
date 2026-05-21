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
      cast_timer: nil
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
  def handle_cast({:take_damage, amount, _from_pid}, %{dead: false} = state) do
    new_hp = max(0.0, state.hp - amount)
    new_state = %{state | hp: new_hp}

    hp_update = Server.StatusUpdate.hp_mp(state.char_id, new_hp, state.mp)
    send(state.conn_pid, {:send_packet, hp_update})

    if new_hp <= 0 do
      Logger.info("[PlayerSession] #{state.char_name} died")
      die_pkt = %Server.Die{object_id: state.char_id, can_sweep: false}
      send(state.conn_pid, {:send_packet, die_pkt})
      if state.region_pid, do: GenServer.cast(state.region_pid, {:broadcast_packet, die_pkt})
      cancel_timer(state.attack_timer)
      Process.send_after(self(), :respawn, @respawn_ms)
      {:noreply, %{new_state | dead: true, attacking: false, attack_timer: nil}}
    else
      {:noreply, new_state}
    end
  end

  def handle_cast({:take_damage, _amount, _from_pid}, state), do: {:noreply, state}

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
          max_hp: new_stats.max_hp
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
        # Target gone — stop attack
        {:noreply, %{state | attacking: false, attack_timer: nil, target_id: nil}}

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

    new_state = %{state | dead: false, hp: new_hp, mp: new_mp}

    revive_pkt = %Server.Revive{object_id: state.char_id}
    send(state.conn_pid, {:send_packet, revive_pkt})
    hp_update = Server.StatusUpdate.hp_mp(state.char_id, new_hp, new_mp)
    send(state.conn_pid, {:send_packet, hp_update})

    Logger.info("[PlayerSession] #{state.char_name} respawned")
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

  def handle_info(msg, state) do
    Logger.debug("[PlayerSession] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # NPC calls this via GenServer.call to get combat stats before attacking
  @impl true
  def handle_call(:get_combat_stats, _from, state) do
    result = {:ok, state.char_id, player_combat_stats(state), state.position}
    {:reply, result, state}
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
      max_hp: derived.max_hp
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

    Logger.info(
      "[PlayerSession] #{char_name} (id=#{char_id}) entered the world (class=#{state.class_id}, level=#{state.level})"
    )

    {:noreply, %{new_state | region_pid: region_pid, skills: skills}}
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

        {:noreply, new_state}

      action_id == 1 ->
        # Shift-click: attack
        new_state = %{state | target_id: obj_id}
        {:noreply, start_auto_attack(new_state)}
    end
  end

  # ---- AttackRequest (0x0A) — direct attack ------------------------------

  defp handle_packet(%L2E.Packet.Client.AttackRequest{object_id: obj_id}, state) do
    new_state = %{state | target_id: obj_id}
    {:noreply, start_auto_attack(new_state)}
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

  # ---- RequestPickUpItem (0x16) — ground item pickup (M7: no ground items yet) --

  defp handle_packet(%L2E.Packet.Client.RequestPickUpItem{}, state) do
    {:noreply, state}
  end

  # ---- RequestSkillList (0x3F) — client requests skill window refresh ----

  defp handle_packet(%L2E.Packet.Client.RequestSkillList{}, %{auth_state: :in_world} = state) do
    send(state.conn_pid, {:send_packet, build_skill_list_packet(state.skills)})
    {:noreply, state}
  end

  # ---- RequestMagicSkillUse (0x2F) — player activates a skill ------------

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
        level: state.level
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
