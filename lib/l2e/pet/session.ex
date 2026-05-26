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

  # Hunger tick: every 60 seconds
  @hunger_tick_ms 60_000
  # Regen tick: every 3 seconds
  @regen_tick_ms 3_000

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

  @doc "Feed the pet. food_amount is added to food_level (capped at 100)."
  def feed(pid, food_amount), do: GenServer.cast(pid, {:feed, food_amount})

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

    # Start hunger and regen timers
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
      hp: 100.0,
      max_hp: 100.0,
      mp: 100.0,
      max_mp: 100.0,
      exp: 0,
      sp: 0,
      # Pet state
      food_level: 100,
      hungry: false,
      # Pet inventory (future expansion)
      pet_items: [],
      # Behavior
      action: :follow,
      hunger_timer: hunger_timer,
      regen_timer: regen_timer
    }

    # Announce this pet to the world so nearby players can see it on summon.
    Phoenix.PubSub.broadcast(L2E.PubSub, "world:pets", {:pet_spawned, state})

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_info, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_items, _from, state) do
    {:reply, state.pet_items, state}
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

  def handle_cast({:feed, food_amount}, state) do
    new_food = min(100, state.food_level + food_amount)
    hungry = new_food < 20
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

  def handle_cast(_, state), do: {:noreply, state}

  @impl GenServer
  def handle_info(:hunger_tick, state) do
    new_food = max(0, state.food_level - 5)
    hungry = new_food < 20

    if hungry != state.hungry do
      # Notify owner of hunger status change
      send(state.owner_pid, {:pet_hungry, hungry})
    end

    # Damage if starving
    new_hp = if new_food == 0, do: max(1.0, state.hp - 10.0), else: state.hp

    timer = Process.send_after(self(), :hunger_tick, @hunger_tick_ms)
    {:noreply, %{state | food_level: new_food, hungry: hungry, hp: new_hp, hunger_timer: timer}}
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
end
