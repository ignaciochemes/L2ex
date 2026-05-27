defmodule L2E.Pet.Session do
  @moduledoc """
  One GenServer per summoned pet.

  Behavioral reference: L2Pet.java (Java) — behavior ONLY, not patterns.

  OTP design:
  - Supervised under L2E.Pet.Supervisor (DynamicSupervisor)
  - Monitors owner session; exits if owner disconnects
  - Follow AI is event-driven: owner movement sends {:pet_follow_target, pos}
  - No polling loop — Process.send_after for hunger/regen ticks

  Crash semantics: :temporary — do NOT restart.
  """

  use GenServer, restart: :temporary
  require Logger

  # Follow tick: every 1 second
  @follow_tick_ms 1_000
  # Hunger tick: every 60 seconds
  @hunger_tick_ms 60_000
  # Regen tick: every 3 seconds
  @regen_tick_ms 3_000
  # Distance threshold before pet moves toward owner
  @follow_distance 150

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Command pet to follow its owner."
  def follow(pet_pid), do: GenServer.cast(pet_pid, :follow)

  @doc "Command pet to stop."
  def stop_action(pet_pid), do: GenServer.cast(pet_pid, :stop)

  @doc "Notify pet of owner's new position (for follow AI)."
  def owner_moved(pet_pid, position), do: GenServer.cast(pet_pid, {:owner_moved, position})

  @doc "Get pet info (for PetInfo packet)."
  def get_info(pet_pid), do: GenServer.call(pet_pid, :get_info)

  @doc "Feed the pet with a food item. Restores 25 food points (capped at 100)."
  def feed(pet_pid, item_id), do: GenServer.cast(pet_pid, {:feed, item_id})

  @doc "List items carried by the pet (initially empty)."
  def get_items(pid), do: GenServer.call(pid, :get_items)

  @doc "Apply damage to the pet. Sends {:pet_died} to owner if HP reaches 0."
  def take_damage(pid, amount), do: GenServer.cast(pid, {:take_damage, amount})

  @impl GenServer
  def init(opts) do
    owner_pid = Keyword.fetch!(opts, :owner_pid)
    pet_item_obj_id = Keyword.fetch!(opts, :pet_item_obj_id)
    npc_id = Keyword.fetch!(opts, :npc_id)

    owner_ref = Process.monitor(owner_pid)

    # Look up combat stats from PetTable; fall back to safe defaults
    pet_template =
      case L2E.Data.PetTable.get(npc_id) do
        {:ok, tpl} ->
          tpl

        :error ->
          %{max_hp: 100.0, max_mp: 50.0, p_atk: 20.0, food_item_id: 2515, hungry_limit: 10}
      end

    # Start follow, hunger, and regen timers
    follow_timer = Process.send_after(self(), :follow_tick, @follow_tick_ms)
    hunger_timer = Process.send_after(self(), :hunger_tick, @hunger_tick_ms)
    regen_timer = Process.send_after(self(), :regen_tick, @regen_tick_ms)

    state = %{
      owner_pid: owner_pid,
      owner_ref: owner_ref,
      pet_item_obj_id: pet_item_obj_id,
      npc_id: npc_id,
      # Position (follows owner)
      position: {0, 0, 0},
      heading: 0,
      # Stats
      level: 1,
      hp: pet_template.max_hp,
      max_hp: pet_template.max_hp,
      mp: pet_template.max_mp,
      max_mp: pet_template.max_mp,
      exp: 0,
      sp: 0,
      # Pet state
      food_level: 100,
      hungry: false,
      # Pet inventory PID (started below)
      inventory_pid: nil,
      # Behavior
      action: :follow,
      follow_timer: follow_timer,
      hunger_timer: hunger_timer,
      regen_timer: regen_timer,
      # Combat
      in_combat: false,
      current_target_pid: nil,
      attack_timer: nil,
      # Region process this pet currently belongs to (for AOI broadcasts)
      region_pid: nil
    }

    # Start pet inventory process (linked to this process)
    {:ok, inv_pid} = L2E.Pet.Inventory.start_link(pet_item_obj_id: pet_item_obj_id)
    state = %{state | inventory_pid: inv_pid}

    # Announce this pet to the world so nearby players can see it on summon.
    Phoenix.PubSub.broadcast(L2E.PubSub, "world:pets", {:pet_spawned, state})

    {:ok, state, {:continue, :summon_broadcast}}
  end

  @impl GenServer
  def handle_continue(:summon_broadcast, state) do
    # Get owner's position to locate the region, then broadcast PetInfo there.
    new_state =
      try do
        case GenServer.call(state.owner_pid, :get_position, 500) do
          {:ok, ox, oy, oz} ->
            region_pid = L2E.World.Region.get_or_start({ox, oy, oz})

            pet_info = %{
              obj_id: state.pet_item_obj_id,
              npc_id: state.npc_id,
              position: {ox, oy, oz},
              hp: state.hp,
              max_hp: state.max_hp,
              mp: state.mp,
              max_mp: state.max_mp,
              level: state.level
            }

            GenServer.cast(region_pid, {:summon_pet, self(), pet_info})
            %{state | region_pid: region_pid, position: {ox, oy, oz}}

          _ ->
            state
        end
      catch
        _, _ -> state
      end

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call(:get_info, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_items, _from, state) do
    items =
      if state.inventory_pid != nil do
        L2E.Pet.Inventory.get_items(state.inventory_pid)
      else
        []
      end

    {:reply, items, state}
  end

  @impl GenServer
  def handle_cast(:follow, state) do
    {:noreply, %{state | action: :follow}}
  end

  def handle_cast(:stop, state) do
    {:noreply, %{state | action: :idle}}
  end

  def handle_cast({:owner_moved, {ox, oy, oz}}, %{action: :follow} = state) do
    # Follow AI: position pet 100 units behind the owner on the X axis.
    # A full implementation would use pathfinding and proper heading math.
    follow_pos = {ox - 100, oy, oz}
    {:noreply, %{state | position: follow_pos}}
  end

  def handle_cast({:feed, _item_id}, state) do
    new_food = min(100, state.food_level + 25)
    hungry = new_food < 20
    send(state.owner_pid, {:pet_hunger_updated, new_food})
    {:noreply, %{state | food_level: new_food, hungry: hungry}}
  end

  def handle_cast({:take_damage, amount}, state) do
    new_hp = max(0.0, state.hp - amount)
    new_state = %{state | hp: new_hp}

    new_state =
      if new_hp == 0.0 do
        send(state.owner_pid, {:pet_died})
        %{new_state | action: :dying}
      else
        new_state
      end

    {:noreply, new_state}
  end

  # Owner tells the pet to attack a target
  def handle_cast({:attack_target, target_pid}, state) do
    if state.in_combat and state.current_target_pid == target_pid do
      {:noreply, state}
    else
      cancel_timer(state.attack_timer)
      timer = Process.send_after(self(), :pet_attack_tick, 2_000)
      {:noreply, %{state | in_combat: true, current_target_pid: target_pid, attack_timer: timer}}
    end
  end

  def handle_cast(:stop_combat, state) do
    cancel_timer(state.attack_timer)
    {:noreply, %{state | in_combat: false, current_target_pid: nil, attack_timer: nil}}
  end

  # Pet receives damage from a target attacking it back
  def handle_cast({:take_damage, amount, _type, _from_pid}, state) do
    new_hp = max(0.0, state.hp - amount)

    if new_hp <= 0.0 do
      send(state.owner_pid, {:pet_died})
      {:stop, :normal, %{state | hp: 0.0}}
    else
      {:noreply, %{state | hp: new_hp}}
    end
  end

  # EXP gain from owner kills
  def handle_cast({:gain_exp, amount}, state) do
    new_exp = state.exp + amount
    new_state = %{state | exp: new_exp}
    new_state = check_level_up(new_state)
    send(state.owner_pid, {:pet_exp_updated, new_state.exp, new_state.level})
    {:noreply, new_state}
  end

  # ---- M110: Unsummon on owner death -------------------------------------
  def handle_cast(:unsummon, state) do
    Logger.info("[Pet] Unsummoning pet #{state.pet_item_obj_id} — owner died")
    {:stop, :normal, state}
  end

  def handle_cast(_, state), do: {:noreply, state}

  def handle_info(:pet_attack_tick, %{in_combat: true, current_target_pid: target_pid} = state)
      when not is_nil(target_pid) do
    alive =
      try do
        GenServer.call(target_pid, :is_alive, 1_000)
      catch
        _, _ -> false
      end

    if alive do
      damage = calculate_pet_damage(state)
      GenServer.cast(target_pid, {:take_damage, damage, :pet, self()})
      timer = Process.send_after(self(), :pet_attack_tick, 2_000)
      {:noreply, %{state | attack_timer: timer}}
    else
      {:noreply, %{state | in_combat: false, current_target_pid: nil, attack_timer: nil}}
    end
  end

  def handle_info(:pet_attack_tick, state) do
    {:noreply, %{state | in_combat: false, current_target_pid: nil, attack_timer: nil}}
  end

  @impl GenServer
  def handle_info(:hunger_tick, state) do
    new_food = max(0, state.food_level - 5)
    hungry = new_food < 20

    cond do
      new_food == 0 ->
        send(state.owner_pid, {:pet_starved, self()})
        {:stop, :normal, %{state | food_level: 0, hungry: true}}

      new_food <= 10 ->
        send(state.owner_pid, {:pet_hunger_low, new_food})
        timer = Process.send_after(self(), :hunger_tick, @hunger_tick_ms)
        {:noreply, %{state | food_level: new_food, hungry: true, hunger_timer: timer}}

      true ->
        if hungry != state.hungry do
          send(state.owner_pid, {:pet_hungry, hungry})
        end

        timer = Process.send_after(self(), :hunger_tick, @hunger_tick_ms)
        {:noreply, %{state | food_level: new_food, hungry: hungry, hunger_timer: timer}}
    end
  end

  def handle_info(:follow_tick, state) do
    new_state =
      try do
        case GenServer.call(state.owner_pid, :get_position, 100) do
          {:ok, ox, oy, oz} ->
            {px, py, _pz} = state.position
            dx = ox - px
            dy = oy - py
            dist = :math.sqrt(dx * dx + dy * dy)

            if dist > @follow_distance do
              step = min(100.0, dist)
              ratio = step / dist
              new_x = trunc(px + dx * ratio)
              new_y = trunc(py + dy * ratio)

              Phoenix.PubSub.broadcast(
                L2E.PubSub,
                "world:pets",
                {:pet_moved, self(), new_x, new_y, oz}
              )

              if state.region_pid != nil do
                GenServer.cast(
                  state.region_pid,
                  {:pet_moved, self(),
                   %{obj_id: state.pet_item_obj_id, x: new_x, y: new_y, z: oz}}
                )
              end

              %{state | position: {new_x, new_y, oz}}
            else
              state
            end

          _ ->
            state
        end
      catch
        _, _ -> state
      end

    timer = Process.send_after(self(), :follow_tick, @follow_tick_ms)
    {:noreply, %{new_state | follow_timer: timer}}
  end

  def handle_info(:regen_tick, state) do
    new_hp = min(state.max_hp, state.hp + state.max_hp * 0.05)
    new_mp = min(state.max_mp, state.mp + state.max_mp * 0.05)
    timer = Process.send_after(self(), :regen_tick, @regen_tick_ms)
    {:noreply, %{state | hp: new_hp, mp: new_mp, regen_timer: timer}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    if ref == state.owner_ref do
      Logger.debug("[Pet] Owner disconnected, shutting down pet #{state.pet_item_obj_id}")
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    Logger.debug("[Pet] Terminating pet #{state.pet_item_obj_id}")
    :ok
  end

  # -----------------------------------------------------------------------
  # Private helpers
  # -----------------------------------------------------------------------

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(ref) when is_reference(ref) do
    Process.cancel_timer(ref)
    :ok
  end

  defp calculate_pet_damage(state) do
    template =
      case L2E.Data.PetDataTable.get(Map.get(state, :npc_id, 0)) do
        {:ok, t} -> t
        _ -> %{}
      end

    base = Map.get(template, :p_atk, 20)
    base + state.level * 2 + :rand.uniform(10) - 5
  end

  defp check_level_up(%{level: 85} = state), do: state

  defp check_level_up(state) do
    threshold = state.level * state.level * 100

    if state.exp >= threshold do
      new_state = %{state | level: state.level + 1, exp: state.exp - threshold}
      send(state.owner_pid, {:pet_level_up, new_state.level})
      check_level_up(new_state)
    else
      state
    end
  end
end
