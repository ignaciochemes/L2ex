defmodule L2E.World.DayNightManager do
  use GenServer
  require Logger

  @moduledoc """
  M73-B: Tracks the in-game day/night cycle.

  L2 Interlude cycle: 4 hours per full rotation (2h day, 2h night).
  Broadcasts :day / :night phase changes via Phoenix.PubSub.
  """

  # 2 hours per phase in milliseconds
  @phase_duration_ms 2 * 60 * 60 * 1000
  @topic "world:day_night"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def current_phase do
    GenServer.call(__MODULE__, :get_phase)
  end

  def init(:ok) do
    schedule_transition()
    {:ok, %{phase: :day}}
  end

  def handle_call(:get_phase, _from, state) do
    {:reply, state.phase, state}
  end

  def handle_info(:transition, state) do
    new_phase = if state.phase == :day, do: :night, else: :day
    Logger.info("[DayNightManager] Phase changed to #{new_phase}")
    Phoenix.PubSub.broadcast(L2E.PubSub, @topic, {:phase_changed, new_phase})
    schedule_transition()
    {:noreply, %{state | phase: new_phase}}
  end

  defp schedule_transition do
    Process.send_after(self(), :transition, @phase_duration_ms)
  end
end
