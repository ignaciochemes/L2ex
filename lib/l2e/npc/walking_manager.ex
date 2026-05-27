defmodule L2E.NPC.WalkingManager do
  @moduledoc """
  M124: WalkingManager GenServer.

  Manages patrol routes for NPCs. NPCs register a route (list of waypoints).
  WalkingManager ticks each registration on its own timer and sends
  {:advance_patrol, {x, y, z}} casts to the NPC pid.

  Design:
  - Each registered NPC has: {npc_pid, waypoints, current_index, speed_ms}
  - speed_ms: time (ms) between waypoint moves, default 3000
  - On :tick, WalkingManager advances the index and casts {:advance_patrol, pos} to the NPC
  - Uses per-registration timers (Process.send_after to self with {:tick, npc_pid})
  - If the NPC process dies, its registration is cleaned up via Process.monitor
  """

  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Register an NPC for patrol. waypoints = [{x,y,z}, ...]. speed_ms = ms between steps."
  def register_patrol(npc_pid, waypoints, speed_ms \\ 3_000) do
    GenServer.cast(__MODULE__, {:register, npc_pid, waypoints, speed_ms})
  end

  @doc "Unregister an NPC from patrol."
  def unregister(npc_pid) do
    GenServer.cast(__MODULE__, {:unregister, npc_pid})
  end

  # GenServer callbacks

  @impl true
  def init(_) do
    {:ok, %{routes: %{}}}
  end

  @impl true
  def handle_cast({:register, pid, waypoints, speed_ms}, state)
      when length(waypoints) > 1 do
    monitor_ref = Process.monitor(pid)
    timer_ref = Process.send_after(self(), {:tick, pid}, speed_ms)

    route = %{
      waypoints: waypoints,
      index: 0,
      speed_ms: speed_ms,
      timer_ref: timer_ref,
      monitor_ref: monitor_ref
    }

    {:noreply, put_in(state.routes[pid], route)}
  end

  def handle_cast({:register, _pid, _waypoints, _speed_ms}, state) do
    # Ignore registrations with fewer than 2 waypoints
    {:noreply, state}
  end

  def handle_cast({:unregister, pid}, state) do
    {:noreply, maybe_cancel_route(state, pid)}
  end

  @impl true
  def handle_info({:tick, pid}, state) do
    case state.routes[pid] do
      nil ->
        {:noreply, state}

      route ->
        next_index = rem(route.index + 1, length(route.waypoints))
        next_pos = Enum.at(route.waypoints, next_index)

        if Process.alive?(pid) do
          GenServer.cast(pid, {:advance_patrol, next_pos})
        end

        timer_ref = Process.send_after(self(), {:tick, pid}, route.speed_ms)
        new_route = %{route | index: next_index, timer_ref: timer_ref}
        {:noreply, put_in(state.routes[pid], new_route)}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    Logger.debug("[WalkingManager] NPC #{inspect(pid)} down, removing patrol route")
    {:noreply, Map.update!(state, :routes, &Map.delete(&1, pid))}
  end

  # Private helpers

  defp maybe_cancel_route(state, pid) do
    case state.routes[pid] do
      nil ->
        state

      route ->
        Process.cancel_timer(route.timer_ref)
        Process.demonitor(route.monitor_ref, [:flush])
        %{state | routes: Map.delete(state.routes, pid)}
    end
  end
end
