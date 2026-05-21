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
  alias L2E.Item.DropResolver

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
          target_pid: pid() | nil,
          target_id: pos_integer() | nil,
          region_pid: pid() | nil,
          attack_timer: reference() | nil,
          leash_timer: reference() | nil
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

  @doc "Returns the NPC's current stats map (for combat resolver)."
  def get_stats(npc_pid) do
    GenServer.call(npc_pid, :get_stats)
  end

  @doc "Returns the NPC's current position and object_id."
  def get_info(npc_pid) do
    GenServer.call(npc_pid, :get_info)
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

    state = %{
      object_id: object_id,
      template: template,
      position: position,
      heading: heading,
      spawn_pos: position,
      hp: template.max_hp * 1.0,
      ai_state: :idle,
      target_pid: nil,
      target_id: nil,
      region_pid: region_pid,
      attack_timer: nil,
      leash_timer: leash_timer
    }

    Logger.debug(
      "[NPC.Instance] #{template.name} (id=#{object_id}) spawned at #{inspect(position)}"
    )

    {:ok, state}
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
    new_hp = max(0.0, state.hp - amount)

    Logger.debug(
      "[NPC.Instance] #{state.template.name} took #{amount} dmg, hp=#{new_hp}/#{state.template.max_hp}"
    )

    if new_hp <= 0 do
      {:noreply, handle_death(state)}
    else
      new_state = %{state | hp: new_hp}
      # Broadcast HP update so nearby players see the HP bar change
      hp_update = Server.StatusUpdate.hp_mp(state.object_id, new_hp, 0)
      broadcast_to_region(new_state, hp_update)
      # Always aggro on attacker regardless of is_aggressive flag
      new_state = enter_combat(new_state, from_pid)
      {:noreply, new_state}
    end
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
          new_state = enter_combat(state, player_pid)
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
    # If our current target left, drop combat
    case Registry.lookup(@registry, char_id) do
      [{pid, _}] when pid == state.target_pid ->
        {:noreply, drop_target(state)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:broadcast, :player_moved, _info}, state), do: {:noreply, state}

  # -----------------------------------------------------------------------
  # Auto-attack tick
  # -----------------------------------------------------------------------

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

      {:noreply,
       %{state | position: state.spawn_pos, ai_state: :idle, hp: state.template.max_hp * 1.0}}
    else
      # Step toward spawn (simplified: teleport at walk speed steps)
      step =
        min(state.template.walk_speed * @return_tick_ms / 1000, distance({x, y, z}, {sx, sy, sz}))

      dist = distance({x, y, z}, {sx, sy, sz})
      ratio = step / dist

      new_pos = {
        round(x + (sx - x) * ratio),
        round(y + (sy - y) * ratio),
        round(z + (sz - z) * ratio)
      }

      _timer = Process.send_after(self(), :return_tick, @return_tick_ms)
      {:noreply, %{state | position: new_pos}}
    end
  end

  def handle_info(:return_tick, state), do: {:noreply, state}

  def handle_info(msg, state) do
    Logger.debug("[NPC.Instance] Unexpected: #{inspect(msg)}")
    {:noreply, state}
  end

  # -----------------------------------------------------------------------
  # Private helpers
  # -----------------------------------------------------------------------

  defp enter_combat(state, target_pid) do
    if state.ai_state == :combat and state.target_pid == target_pid do
      state
    else
      cancel_timer(state.attack_timer)
      atk_ms = round(1000 / (state.template.atk_speed / 500.0))
      timer = Process.send_after(self(), :auto_attack_tick, atk_ms)
      %{state | ai_state: :combat, target_pid: target_pid, attack_timer: timer}
    end
  end

  defp drop_target(state) do
    cancel_timer(state.attack_timer)
    %{state | target_pid: nil, target_id: nil, ai_state: :idle, attack_timer: nil}
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

        # Schedule next attack
        atk_ms = round(1000 / (state.template.atk_speed / 500.0))
        timer = Process.send_after(self(), :auto_attack_tick, atk_ms)
        {:noreply, %{state | attack_timer: timer}}

      _error ->
        {:noreply, drop_target(state)}
    end
  end

  defp handle_death(state) do
    cancel_timer(state.attack_timer)
    cancel_timer(state.leash_timer)

    # Broadcast Die to region
    die_packet = %Server.Die{object_id: state.object_id, can_sweep: false}
    broadcast_to_region(state, die_packet)

    # M18: Drop items as ground items in the region (visible to all players)
    drops = DropResolver.resolve(state.template)

    unless drops == [] or is_nil(state.region_pid) do
      {x, y, z} = state.position

      Enum.each(drops, fn {item_id, count} ->
        obj_id = :erlang.unique_integer([:positive, :monotonic])
        GenServer.cast(state.region_pid, {:drop_item, obj_id, item_id, x, y, z, count})
      end)
    end

    # Send EXP/SP reward to the killer
    if is_pid(state.target_pid) and Process.alive?(state.target_pid) and
         (state.template.exp_reward > 0 or state.template.sp_reward > 0) do
      GenServer.cast(
        state.target_pid,
        {:receive_xp_sp, state.template.exp_reward, state.template.sp_reward}
      )
    end

    # Notify SpawnTable for respawn scheduling
    send(
      L2E.NPC.SpawnTable,
      {:npc_died, state.object_id, state.template.npc_id, state.spawn_pos, state.heading}
    )

    Logger.info("[NPC.Instance] #{state.template.name} (id=#{state.object_id}) died")

    %{
      state
      | hp: 0.0,
        ai_state: :dead,
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

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)
end
