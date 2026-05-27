defmodule L2E.NPC.Instance do
  @moduledoc """
  One GenServer per live NPC in the world.

  ## State machine

    :idle        — standing at spawn, waiting for events
    :combat      — actively attacking a target
    :returning   — walking back to spawn_pos after losing target/leash
    :dead        — waiting for SpawnTable to trigger respawn

  ## AI design (no polling)

  All behavior is event-driven:
  - {:broadcast, :player_entered, info}  → aggro check
  - {:broadcast, :player_left, char_id}  → drop target if it was that player
  - {:take_damage, amount, from_pid}     → always enter combat vs attacker
  - :auto_attack_tick                    → execute hit against target
  - :return_tick                         → step toward spawn_pos
  - :leash_check                         → cancel combat if too far from spawn

  Registered in L2E.Session.Registry by object_id (same registry, different key space).
  """

  use GenServer, restart: :temporary
  require Logger

  alias L2E.NPC.Template
  alias L2E.Combat.Resolver
  alias L2E.Packet.Server
  alias L2E.World.Region
  alias L2E.World.RegionCoords
  alias L2E.Item.DropResolver
  alias L2E.Party

  @registry L2E.Session.Registry

  # Leash check interval (ms)
  @leash_check_ms 3_000
  # How long to stay dead before SpawnTable respawns us (handled by SpawnTable)
  # Return movement step interval
  @return_tick_ms 500

  @type ai_state :: :idle | :combat | :returning | :dead

  @type state :: %{
          object_id: pos_integer(),
          template: Template.t(),
          position: {integer(), integer(), integer()},
          heading: non_neg_integer(),
          spawn_pos: {integer(), integer(), integer()},
          hp: float(),
          ai_state: ai_state(),
          hate_map: %{pid() => non_neg_integer()},
          target_pid: pid() | nil,
          target_id: pos_integer() | nil,
          region_pid: pid() | nil,
          attack_timer: reference() | nil,
          leash_timer: reference() | nil,
          skill_chance: float(),
          skills: list(),
          wander_timer: reference() | nil,
          wander_radius: non_neg_integer(),
          npc_can_see: boolean()
        }

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Notify the NPC that it took damage from a process."
  def take_damage(npc_pid, amount, from_pid) do
    GenServer.cast(npc_pid, {:take_damage, amount, from_pid})
  end

  @doc "Apply crowd control to this NPC."
  def apply_cc(pid, cc_type, duration_ms) do
    GenServer.cast(pid, {:apply_cc, cc_type, duration_ms})
  end

  @doc "Apply a damage-over-time effect to this NPC."
  def apply_dot(pid, skill_id, damage_per_tick, tick_ms, ticks_left) do
    GenServer.cast(pid, {:apply_dot, skill_id, damage_per_tick, tick_ms, ticks_left})
  end

  @doc "Returns the NPC's current stats map (for combat resolver)."
  def get_stats(npc_pid) do
    GenServer.call(npc_pid, :get_stats)
  end

  @doc "Returns the NPC's current position and object_id."
  def get_info(npc_pid) do
    GenServer.call(npc_pid, :get_info)
  end

  @doc "Add hate toward this NPC from a player process."
  def add_hate(pid, player_pid, amount) do
    GenServer.cast(pid, {:add_hate, player_pid, amount})
  end

  @doc "Mark this NPC as spoiled by the given char_id. No-op if already dead or spoiled."
  def apply_spoil(npc_pid, char_id) do
    GenServer.cast(npc_pid, {:apply_spoil, char_id})
  end

  @doc "Collect sweep drops. Returns {:ok, drops} or {:error, reason}."
  def sweep(npc_pid, char_id) do
    GenServer.call(npc_pid, {:sweep, char_id})
  end

  # -----------------------------------------------------------------------
  # GenServer init
  # -----------------------------------------------------------------------

  @impl true
  def init(opts) do
    template = Keyword.fetch!(opts, :template)
    position = Keyword.fetch!(opts, :position)
    heading = Keyword.get(opts, :heading, 0)
    object_id = Keyword.fetch!(opts, :object_id)

    Registry.register(@registry, {:npc, object_id}, self())

    region_pid = Region.get_or_start(position)
    announce_to_region(region_pid, object_id, template, position, heading, template.max_hp)

    leash_timer = Process.send_after(self(), :leash_check, @leash_check_ms)

    {gx, gy} = RegionCoords.to_grid(elem(position, 0), elem(position, 1))
    region_id = "#{gx}:#{gy}"

    faction_id = Map.get(template, :faction_id)

    # M88: Subscribe to faction topic so nearby faction members can coordinate
    if faction_id not in [nil, ""] do
      Phoenix.PubSub.subscribe(L2E.PubSub, "region:#{region_id}:faction:#{faction_id}")
    end

    state = %{
      object_id: object_id,
      template: template,
      position: position,
      heading: heading,
      spawn_pos: position,
      hp: template.max_hp * 1.0,
      ai_state: :idle,
      hate_map: %{},
      target_pid: nil,
      target_id: nil,
      region_pid: region_pid,
      attack_timer: nil,
      leash_timer: leash_timer,
      stunned: false,
      stun_timer: nil,
      skill_chance: template.skill_chance || 0.15,
      skills: template.skills || [],
      wander_timer: nil,
      wander_radius: template.wander_radius || 200,
      # M77: Spoil — char_id of the player who used Spoil skill, nil if not spoiled
      spoiled_by: nil,
      # M80: Fear CC state
      feared: false,
      fear_timer: nil,
      # M88: Faction aggro — region key string for PubSub topic construction
      region_id: region_id,
      faction_id: faction_id,
      # M90: LoS gate for ranged NPC attacks; set false only in tests
      npc_can_see: true,
      # M124: Walker patrol
      patrol_path: nil,
      patrol_index: 0
    }

    state =
      if template.can_walk do
        timer = Process.send_after(self(), :wander_tick, :rand.uniform(10_000) + 5_000)
        %{state | wander_timer: timer}
      else
        state
      end

    {:ok, state, {:continue, :after_init}}
  end

  @impl true
  def handle_continue(:after_init, state) do
    init_patrol(state)
    {:noreply, state}
  end

  # M124: Register a patrol route if the template carries one.
  defp init_patrol(state) do
    patrol = Map.get(state.template, :patrol_route)

    if is_list(patrol) and length(patrol) > 1 do
      L2E.NPC.WalkingManager.register_patrol(self(), patrol)
    end
  end

  # -----------------------------------------------------------------------
  # External calls
  # -----------------------------------------------------------------------

  @impl true
  def handle_call(:get_stats, _from, state) do
    t = state.template

    stats = %{
      p_atk: t.p_atk,
      m_atk: t.m_atk,
      p_def: t.p_def,
      m_def: t.m_def,
      accuracy: t.accuracy,
      evasion: t.evasion,
      crit_rate: t.crit_rate,
      atk_speed: t.atk_speed,
      level: t.level,
      max_hp: t.max_hp
    }

    {:reply, stats, state}
  end

  # M77: Sweep — collect spoil drops (caller must be the one who spoiled)
  def handle_call({:sweep, char_id}, _from, state) do
    cond do
      state.ai_state != :dead ->
        {:reply, {:error, :not_dead}, state}

      state.spoiled_by != char_id ->
        {:reply, {:error, :not_your_spoil}, state}

      true ->
        drops = generate_sweep_drops(state.template)
        {:reply, {:ok, drops}, %{state | spoiled_by: nil}}
    end
  end

  def handle_call(:get_info, _from, state) do
    info = %{
      object_id: state.object_id,
      position: state.position,
      heading: state.heading,
      hp: state.hp,
      max_hp: state.template.max_hp,
      template: state.template
    }

    {:reply, info, state}
  end

  # -----------------------------------------------------------------------
  # Damage
  # -----------------------------------------------------------------------

  @impl true
  def handle_cast({:take_damage, _amount, _from_pid}, %{ai_state: :dead} = state) do
    # Already dead — ignore
    {:noreply, state}
  end

  def handle_cast({:take_damage, amount, from_pid}, state) do
    new_hate = Map.update(state.hate_map, from_pid, amount, &(&1 + amount))
    new_target = select_top_hated(new_hate, state)
    new_hp = max(0.0, state.hp - amount)

    # M88: Faction aggro — broadcast to nearby faction members in the same region
    if state.faction_id not in [nil, ""] do
      {nx, ny, nz} = state.position

      Phoenix.PubSub.broadcast(
        L2E.PubSub,
        "region:#{state.region_id}:faction:#{state.faction_id}",
        {:faction_aggro, from_pid, nx, ny, nz}
      )
    end

    Logger.debug(
      "[NPC.Instance] #{state.template.name} took #{amount} dmg, hp=#{new_hp}/#{state.template.max_hp}"
    )

    if new_hp <= 0 do
      {:noreply, handle_death(%{state | hate_map: new_hate})}
    else
      hp_update = Server.StatusUpdate.hp_mp(state.object_id, new_hp, 0)
      broadcast_to_region(state, hp_update)
      base = %{state | hp: new_hp, hate_map: new_hate, target_pid: new_target}

      new_state =
        case state.ai_state do
          :combat ->
            base

          _ ->
            cancel_timer(base.attack_timer)
            atk_ms = round(1000 / (base.template.atk_speed / 500.0))
            timer = Process.send_after(self(), :auto_attack_tick, atk_ms)
            %{base | ai_state: :combat, attack_timer: timer}
        end

      {:noreply, new_state}
    end
  end

  # Backward-compatible clause: no from_pid — just deduct HP, no hate added
  def handle_cast({:take_damage, damage}, %{ai_state: :dead} = state) do
    _ = damage
    {:noreply, state}
  end

  def handle_cast({:take_damage, damage}, state) do
    new_hp = max(0.0, state.hp - damage)

    if new_hp <= 0 do
      {:noreply, handle_death(state)}
    else
      hp_update = Server.StatusUpdate.hp_mp(state.object_id, new_hp, 0)
      broadcast_to_region(state, hp_update)
      {:noreply, %{state | hp: new_hp}}
    end
  end

  def handle_cast({:add_hate, player_pid, amount}, %{ai_state: :dead} = state) do
    _ = {player_pid, amount}
    {:noreply, state}
  end

  def handle_cast({:add_hate, player_pid, amount}, state) do
    new_hate = Map.update(state.hate_map, player_pid, amount, &(&1 + amount))
    new_target = select_top_hated(new_hate, state)
    base = %{state | hate_map: new_hate, target_pid: new_target}

    new_state =
      if state.ai_state == :idle and new_target != nil do
        cancel_timer(base.attack_timer)
        atk_ms = round(1000 / (base.template.atk_speed / 500.0))
        timer = Process.send_after(self(), :auto_attack_tick, atk_ms)
        %{base | ai_state: :combat, attack_timer: timer}
      else
        base
      end

    {:noreply, new_state}
  end

  # M49: Apply crowd control
  def handle_cast({:apply_cc, :stun, duration_ms}, state) do
    if state.stun_timer, do: Process.cancel_timer(state.stun_timer)
    timer = Process.send_after(self(), :stun_expired, duration_ms)
    {:noreply, %{state | stunned: true, stun_timer: timer}}
  end

  # M77: Spoil — mark this NPC as spoiled by char_id
  def handle_cast({:apply_spoil, _char_id}, %{ai_state: :dead} = state), do: {:noreply, state}

  def handle_cast({:apply_spoil, _char_id}, %{spoiled_by: existing} = state)
      when existing != nil,
      do: {:noreply, state}

  def handle_cast({:apply_spoil, char_id}, state) do
    {:noreply, %{state | spoiled_by: char_id}}
  end

  def handle_cast({:apply_cc, _cc_type, _duration_ms}, state), do: {:noreply, state}

  # M124: Advance patrol — move NPC to next waypoint and broadcast movement
  def handle_cast({:advance_patrol, {nx, ny, nz}}, %{ai_state: :idle} = state) do
    {ox, oy, oz} = state.position

    move_pkt = %L2E.Packet.Server.CharMoveToLocation{
      char_id: state.object_id,
      x: nx,
      y: ny,
      z: nz,
      origin_x: ox,
      origin_y: oy,
      origin_z: oz
    }

    if is_pid(state.region_pid) and Process.alive?(state.region_pid) do
      GenServer.cast(state.region_pid, {:broadcast_packet, move_pkt})
    end

    {:noreply, %{state | position: {nx, ny, nz}}}
  end

  def handle_cast({:advance_patrol, _pos}, state) do
    # Skip patrol movement while in combat, returning, or dead
    {:noreply, state}
  end

  # M49: Apply DoT
  def handle_cast({:apply_dot, _skill_id, damage_per_tick, tick_ms, ticks_left}, state) do
    Process.send_after(self(), {:dot_tick, damage_per_tick, tick_ms, ticks_left}, tick_ms)
    {:noreply, state}
  end

  # -----------------------------------------------------------------------
  # AOI broadcasts from Region
  # -----------------------------------------------------------------------

  @impl true
  def handle_info({:broadcast, :player_entered, info}, %{ai_state: :idle} = state) do
    t = state.template

    if t.is_aggressive and in_aggro_range?(state.position, info.position, t.aggro_range) do
      case Registry.lookup(@registry, info.char_id) do
        [{player_pid, _}] ->
          new_hate = Map.put(state.hate_map, player_pid, 100)
          new_state = enter_combat(%{state | hate_map: new_hate}, player_pid)
          {:noreply, new_state}

        [] ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:broadcast, :player_entered, _info}, state), do: {:noreply, state}

  def handle_info({:broadcast, :player_left, char_id}, state) do
    case Registry.lookup(@registry, char_id) do
      [{pid, _}] ->
        new_hate = Map.delete(state.hate_map, pid)
        new_target = select_top_hated(new_hate, state)

        new_state =
          if new_target == nil do
            cancel_timer(state.attack_timer)

            %{
              state
              | hate_map: %{},
                target_pid: nil,
                target_id: nil,
                ai_state: :idle,
                attack_timer: nil
            }
          else
            %{state | hate_map: new_hate, target_pid: new_target}
          end

        {:noreply, new_state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:broadcast, :player_moved, _info}, state), do: {:noreply, state}

  # -----------------------------------------------------------------------
  # Auto-attack tick
  # -----------------------------------------------------------------------

  # M49: Block attack while stunned — reschedule without hitting
  def handle_info(:auto_attack_tick, %{stunned: true} = state) do
    atk_ms = round(1000 / (state.template.atk_speed / 500.0))
    timer = Process.send_after(self(), :auto_attack_tick, atk_ms)
    {:noreply, %{state | attack_timer: timer}}
  end

  def handle_info(:auto_attack_tick, %{ai_state: :combat, target_pid: target_pid} = state)
      when is_pid(target_pid) do
    if Process.alive?(target_pid) do
      execute_attack(state)
    else
      {:noreply, drop_target(state)}
    end
  end

  def handle_info(:auto_attack_tick, state), do: {:noreply, state}

  # -----------------------------------------------------------------------
  # Leash check
  # -----------------------------------------------------------------------

  def handle_info(:leash_check, %{ai_state: :dead} = state), do: {:noreply, state}

  def handle_info(:leash_check, %{ai_state: :combat} = state) do
    t = state.template

    if distance(state.position, state.spawn_pos) > t.leash_range do
      Logger.debug("[NPC.Instance] #{t.name} leash exceeded, returning")
      new_state = drop_target(%{state | ai_state: :returning})
      _timer = Process.send_after(self(), :return_tick, @return_tick_ms)
      leash_timer = Process.send_after(self(), :leash_check, @leash_check_ms)
      {:noreply, %{new_state | attack_timer: nil, leash_timer: leash_timer}}
    else
      leash_timer = Process.send_after(self(), :leash_check, @leash_check_ms)
      {:noreply, %{state | leash_timer: leash_timer}}
    end
  end

  def handle_info(:leash_check, state) do
    leash_timer = Process.send_after(self(), :leash_check, @leash_check_ms)
    {:noreply, %{state | leash_timer: leash_timer}}
  end

  # -----------------------------------------------------------------------
  # Return movement
  # -----------------------------------------------------------------------

  def handle_info(:return_tick, %{ai_state: :returning} = state) do
    {sx, sy, sz} = state.spawn_pos
    {x, y, z} = state.position

    if distance({x, y, z}, {sx, sy, sz}) < 50 do
      # Arrived at spawn
      Logger.debug("[NPC.Instance] #{state.template.name} returned to spawn")

      wander_timer =
        if state.template.can_walk do
          Process.send_after(self(), :wander_tick, :rand.uniform(10_000) + 5_000)
        else
          nil
        end

      {:noreply,
       %{
         state
         | position: state.spawn_pos,
           ai_state: :idle,
           hp: state.template.max_hp * 1.0,
           wander_timer: wander_timer
       }}
    else
      # M90: Use pathfinding to navigate around obstacles toward spawn
      {tx, ty, tz} =
        case L2E.Geodata.find_path(x, y, z, sx, sy, sz) do
          [] -> {sx, sy, sz}
          [{wx, wy, wz} | _] -> {wx, wy, wz}
        end

      step =
        min(state.template.walk_speed * @return_tick_ms / 1000, distance({x, y, z}, {tx, ty, tz}))

      dist = distance({x, y, z}, {tx, ty, tz})
      ratio = if dist > 0, do: step / dist, else: 1.0

      new_pos = {
        round(x + (tx - x) * ratio),
        round(y + (ty - y) * ratio),
        round(z + (tz - z) * ratio)
      }

      _timer = Process.send_after(self(), :return_tick, @return_tick_ms)
      {:noreply, %{state | position: new_pos}}
    end
  end

  def handle_info(:return_tick, state), do: {:noreply, state}

  # Corpse disappears 7 seconds after death
  def handle_info(:corpse_decay, %{ai_state: :dead} = state) do
    broadcast_to_region(state, %Server.DeleteObject{object_id: state.object_id})
    {:stop, :normal, state}
  end

  def handle_info(:corpse_decay, state), do: {:noreply, state}

  # M49: Stun expired
  def handle_info(:stun_expired, state) do
    {:noreply, %{state | stunned: false, stun_timer: nil}}
  end

  # M49: DoT tick
  def handle_info(
        {:dot_tick, damage_per_tick, tick_ms, ticks_left},
        %{ai_state: ai_state} = state
      )
      when ai_state != :dead do
    new_hp = max(0.0, state.hp - damage_per_tick)

    hp_pkt = %Server.StatusUpdate{
      object_id: state.object_id,
      attributes: [{0x09, trunc(new_hp)}]
    }

    if state.region_pid, do: GenServer.cast(state.region_pid, {:broadcast_packet, hp_pkt})

    if new_hp <= 0 do
      {:noreply, handle_death(%{state | hp: 0.0})}
    else
      if ticks_left > 1 do
        Process.send_after(self(), {:dot_tick, damage_per_tick, tick_ms, ticks_left - 1}, tick_ms)
      end

      {:noreply, %{state | hp: new_hp}}
    end
  end

  def handle_info({:dot_tick, _, _, _}, state), do: {:noreply, state}

  # Wander AI — only moves in :idle state
  def handle_info(:wander_tick, %{ai_state: :idle} = state) do
    wander_radius = state.wander_radius
    {sx, sy, sz} = state.spawn_pos
    angle = :rand.uniform() * 2 * :math.pi()
    dist = if wander_radius > 0, do: :rand.uniform(wander_radius), else: 0
    nx = sx + round(:math.cos(angle) * dist)
    ny = sy + round(:math.sin(angle) * dist)

    move_pkt = %Server.CharMoveToLocation{
      char_id: state.object_id,
      x: nx,
      y: ny,
      z: sz,
      origin_x: elem(state.position, 0),
      origin_y: elem(state.position, 1),
      origin_z: elem(state.position, 2)
    }

    broadcast_to_region(state, move_pkt)

    next_ms = :rand.uniform(10_000) + 5_000
    timer = Process.send_after(self(), :wander_tick, next_ms)
    {:noreply, %{state | position: {nx, ny, sz}, wander_timer: timer}}
  end

  def handle_info(:wander_tick, state), do: {:noreply, state}

  # M80: Fear applied to this NPC — clear current target and enter fear state
  def handle_info({:apply_fear, _duration, _from_char_id}, %{ai_state: :dead} = state),
    do: {:noreply, state}

  def handle_info({:apply_fear, duration, _from_char_id}, state) do
    if state.fear_timer, do: Process.cancel_timer(state.fear_timer)
    timer = Process.send_after(self(), :fear_expired, duration)
    {:noreply, %{state | target_pid: nil, feared: true, fear_timer: timer}}
  end

  # M80: Fear timer expired — resume normal AI
  def handle_info(:fear_expired, state) do
    {:noreply, %{state | feared: false, fear_timer: nil}}
  end

  # M80: Dispel buffs — NPCs have no buff system, no-op
  def handle_info({:dispel_buffs, _count}, state), do: {:noreply, state}

  # M88: Faction aggro — a nearby faction member was attacked; join combat if idle and close enough
  def handle_info({:faction_aggro, _attacker_pid, _x, _y, _z}, %{ai_state: :dead} = state),
    do: {:noreply, state}

  def handle_info({:faction_aggro, attacker_pid, x, y, z}, %{ai_state: :idle} = state) do
    if distance(state.position, {x, y, z}) <= 1000 and is_pid(attacker_pid) and
         Process.alive?(attacker_pid) do
      new_hate = Map.update(state.hate_map, attacker_pid, 200, &(&1 + 200))
      new_state = enter_combat(%{state | hate_map: new_hate}, attacker_pid)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:faction_aggro, _attacker_pid, _x, _y, _z}, state), do: {:noreply, state}

  def handle_info(msg, state) do
    Logger.debug("[NPC.Instance] Unexpected: #{inspect(msg)}")
    {:noreply, state}
  end

  # -----------------------------------------------------------------------
  # Private helpers
  # -----------------------------------------------------------------------

  defp enter_combat(state, target_pid) do
    cancel_timer(state.attack_timer)
    cancel_timer(Map.get(state, :wander_timer))
    atk_ms = round(1000 / (state.template.atk_speed / 500.0))
    timer = Process.send_after(self(), :auto_attack_tick, atk_ms)
    %{state | ai_state: :combat, target_pid: target_pid, attack_timer: timer, wander_timer: nil}
  end

  defp drop_target(state) do
    cancel_timer(state.attack_timer)

    wander_timer =
      if state.template.can_walk do
        Process.send_after(self(), :wander_tick, :rand.uniform(10_000) + 5_000)
      else
        nil
      end

    %{
      state
      | hate_map: %{},
        target_pid: nil,
        target_id: nil,
        ai_state: :idle,
        attack_timer: nil,
        wander_timer: wander_timer
    }
  end

  defp execute_attack(state) do
    my_stats = %{
      p_atk: state.template.p_atk,
      accuracy: state.template.accuracy,
      crit_rate: state.template.crit_rate,
      atk_speed: state.template.atk_speed
    }

    # Get defender stats and deal damage
    case GenServer.call(state.target_pid, :get_combat_stats, 2000) do
      {:ok, target_id, target_stats, target_pos} ->
        # M90: ranged NPCs (attack_range > 100) respect line-of-sight
        is_ranged = state.template.attack_range > 100

        if is_ranged and state.npc_can_see and
             not L2E.Geodata.can_see?(
               elem(state.position, 0),
               elem(state.position, 1),
               elem(state.position, 2),
               elem(target_pos, 0),
               elem(target_pos, 1),
               elem(target_pos, 2)
             ) do
          # Target behind wall — skip this attack, reschedule
          atk_ms = round(1000 / (state.template.atk_speed / 500.0))
          timer = Process.send_after(self(), :auto_attack_tick, atk_ms)
          {:noreply, %{state | attack_timer: timer}}
        else
          {damage, result} = Resolver.resolve_hit(my_stats, target_stats)

          # Broadcast attack to region
          attack_packet = %Server.Attack{
            attacker_id: state.object_id,
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

          broadcast_to_region(state, attack_packet)

          # Tell target to take damage
          GenServer.cast(state.target_pid, {:take_damage, damage, self()})

          # Maybe cast a skill
          state = maybe_cast_skill(state, target_id)

          # Schedule next attack
          atk_ms = round(1000 / (state.template.atk_speed / 500.0))
          timer = Process.send_after(self(), :auto_attack_tick, atk_ms)
          {:noreply, %{state | attack_timer: timer}}
        end

      _error ->
        {:noreply, drop_target(state)}
    end
  end

  defp handle_death(state) do
    cancel_timer(state.attack_timer)
    cancel_timer(state.leash_timer)

    # Broadcast Die to region (can_sweep = true if this NPC has been spoiled)
    die_packet = %Server.Die{object_id: state.object_id, can_sweep: state.spoiled_by != nil}
    broadcast_to_region(state, die_packet)

    # M18: Drop items as ground items in the region (visible to all players)
    # M82 TODO: Loot distribution — when the killer has a party with a non-:finders_keepers
    # loot_mode, distribute drops to the appropriate party member instead of (or in addition to)
    # dropping on the ground. Requires:
    #   1. `handle_call(:get_party_pid, _from, state)` on PlayerSession returning state.party_pid
    #   2. `L2E.Party.get_loot_mode(party_pid)` to read the mode
    #   3. For :random — pick a random member pid from the party and send the item directly
    #   4. For :by_turn — read/advance `next_looter_index` in party state via a new handle_call
    # For now all drops fall through to the region as ground items (:finders_keepers behavior).
    drops = DropResolver.resolve(state.template)

    unless drops == [] or is_nil(state.region_pid) do
      {x, y, z} = state.position

      Enum.each(drops, fn {item_id, count} ->
        obj_id = :erlang.unique_integer([:positive, :monotonic])
        GenServer.cast(state.region_pid, {:drop_item, obj_id, item_id, x, y, z, count})
      end)
    end

    # Send EXP/SP reward to the killer — party-aware (M88)
    if is_pid(state.target_pid) and Process.alive?(state.target_pid) and
         (state.template.exp_reward > 0 or state.template.sp_reward > 0) do
      killer_party_pid =
        try do
          GenServer.call(state.target_pid, :get_party_pid, 1_000)
        catch
          _, _ -> nil
        end

      case killer_party_pid do
        nil ->
          GenServer.cast(
            state.target_pid,
            {:receive_xp_sp, state.template.exp_reward, state.template.sp_reward}
          )

        party_pid ->
          Party.distribute_exp(
            party_pid,
            state.template.exp_reward,
            state.template.sp_reward,
            state.template.level
          )
      end
    end

    # TODO M91: Quest.Engine.on_kill(state.target_pid, state.template.npc_id, 1)

    # M92: Soul crystal absorption — send event to killer session
    if is_pid(state.target_pid) and Process.alive?(state.target_pid) do
      send(
        state.target_pid,
        {:try_soul_crystal_absorb, state.template.npc_id, state.template.level}
      )
    end

    # M98: Grand Boss death — notify manager to set dead state and unlock instance
    if state.template.npc_id in L2E.GrandBoss.Manager.grand_boss_ids() do
      L2E.GrandBoss.Manager.boss_died(state.template.npc_id)
    end

    # Notify SpawnTable for respawn scheduling
    send(
      L2E.NPC.SpawnTable,
      {:npc_died, state.object_id, state.template.npc_id, state.spawn_pos, state.heading}
    )

    Logger.info("[NPC.Instance] #{state.template.name} (id=#{state.object_id}) died")

    Process.send_after(self(), :corpse_decay, 7_000)

    %{
      state
      | hp: 0.0,
        ai_state: :dead,
        hate_map: %{},
        target_pid: nil,
        target_id: nil,
        attack_timer: nil,
        leash_timer: nil
    }
  end

  defp announce_to_region(region_pid, object_id, template, position, heading, hp) do
    npc_info = %Server.NpcInfo{
      object_id: object_id,
      npc_type_id: template.npc_id,
      name: template.name,
      title: template.title || "",
      x: elem(position, 0),
      y: elem(position, 1),
      z: elem(position, 2),
      heading: heading,
      max_hp: round(template.max_hp),
      cur_hp: round(hp),
      max_mp: 0,
      cur_mp: 0,
      run_speed: template.run_speed,
      walk_speed: template.walk_speed,
      p_atk: template.p_atk,
      p_def: template.p_def,
      m_atk: template.m_atk,
      m_def: template.m_def,
      atk_speed: template.atk_speed,
      cast_speed: template.cast_speed,
      level: template.level,
      is_attackable: true
    }

    GenServer.call(region_pid, {:npc_enter, self(), object_id, npc_info})
  end

  # M77: Generate sweep drops from the template sweep_drops list
  defp generate_sweep_drops(template) do
    sweep_drops = Map.get(template, :sweep_drops, [])

    Enum.flat_map(sweep_drops, fn %{item_id: item_id, count: count, chance: chance} ->
      if :rand.uniform(100) <= chance, do: [%{item_id: item_id, count: count}], else: []
    end)
  end

  defp broadcast_to_region(%{region_pid: nil}, _packet), do: :ok

  defp broadcast_to_region(%{region_pid: region_pid}, packet) do
    GenServer.cast(region_pid, {:broadcast_packet, packet})
  end

  defp in_aggro_range?(npc_pos, player_pos, aggro_range) do
    distance(npc_pos, player_pos) <= aggro_range
  end

  defp distance({x1, y1, _z1}, {x2, y2, _z2}) do
    :math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
  end

  defp maybe_cast_skill(%{skills: []} = state, _target_id), do: state

  defp maybe_cast_skill(state, target_id) do
    if :rand.uniform() < state.skill_chance do
      {skill_id, skill_template} = Enum.random(state.skills)
      {x, y, z} = state.position

      case skill_template.effect_type do
        effect when effect in [:p_damage, :m_damage] ->
          damage = round(skill_template.power)
          GenServer.cast(state.target_pid, {:take_damage, damage, self()})

          broadcast_to_region(state, %Server.MagicSkillUse{
            caster_id: state.object_id,
            target_id: target_id,
            skill_id: skill_id,
            skill_level: skill_template.level,
            hit_time: skill_template.cast_time_ms,
            reuse_delay: skill_template.reuse_ms,
            x: x,
            y: y,
            z: z
          })

          broadcast_to_region(state, %Server.MagicSkillLaunched{
            caster_id: state.object_id,
            skill_id: skill_id,
            skill_level: skill_template.level,
            target_ids: [target_id]
          })

          state

        :stun ->
          GenServer.cast(state.target_pid, {:apply_cc, :stun, skill_template.buff_duration_ms})

          broadcast_to_region(state, %Server.MagicSkillUse{
            caster_id: state.object_id,
            target_id: target_id,
            skill_id: skill_id,
            skill_level: skill_template.level,
            hit_time: skill_template.cast_time_ms,
            reuse_delay: skill_template.reuse_ms,
            x: x,
            y: y,
            z: z
          })

          state

        :root ->
          GenServer.cast(state.target_pid, {:apply_cc, :rooted, skill_template.buff_duration_ms})

          broadcast_to_region(state, %Server.MagicSkillUse{
            caster_id: state.object_id,
            target_id: target_id,
            skill_id: skill_id,
            skill_level: skill_template.level,
            hit_time: skill_template.cast_time_ms,
            reuse_delay: skill_template.reuse_ms,
            x: x,
            y: y,
            z: z
          })

          state

        :heal ->
          new_hp = min(state.hp + skill_template.power, state.template.max_hp)
          broadcast_to_region(state, Server.StatusUpdate.hp_mp(state.object_id, new_hp, 0))

          broadcast_to_region(state, %Server.MagicSkillUse{
            caster_id: state.object_id,
            target_id: state.object_id,
            skill_id: skill_id,
            skill_level: skill_template.level,
            hit_time: skill_template.cast_time_ms,
            reuse_delay: skill_template.reuse_ms,
            x: x,
            y: y,
            z: z
          })

          %{state | hp: new_hp}

        :dot_hp ->
          tick_dmg = round(skill_template.power / 5)
          GenServer.cast(state.target_pid, {:apply_dot, skill_id, tick_dmg, 3_000, 5})

          broadcast_to_region(state, %Server.MagicSkillUse{
            caster_id: state.object_id,
            target_id: target_id,
            skill_id: skill_id,
            skill_level: skill_template.level,
            hit_time: skill_template.cast_time_ms,
            reuse_delay: skill_template.reuse_ms,
            x: x,
            y: y,
            z: z
          })

          state

        _ ->
          state
      end
    else
      state
    end
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  defp select_top_hated(hate_map, _state) when map_size(hate_map) == 0, do: nil

  defp select_top_hated(hate_map, _state) do
    hate_map
    |> Enum.filter(fn {pid, _} -> Process.alive?(pid) end)
    |> Enum.max_by(fn {_, hate} -> hate end, fn -> nil end)
    |> case do
      {pid, _} -> pid
      nil -> nil
    end
  end
end
