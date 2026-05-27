defmodule L2E.Manor.Manager do
  @moduledoc """
  M115 — Castle Manor System state machine.
  Cycles through :approved → :modifiable → :maintenance → :approved.
  Broadcasts {:manor_mode_changed, new_mode} on L2E.PubSub "world:manor".
  """
  use GenServer
  require Logger

  @topic "world:manor"
  # Default period lengths in ms (can be overridden via config)
  @approved_ms 6 * 60 * 60 * 1000    # 6 hours
  @modifiable_ms 4 * 60 * 60 * 1000  # 4 hours
  @maintenance_ms 5 * 60 * 1000      # 5 minutes

  # Castle data: list of %{id, name, seeds: [], crops: []}
  # Seeds and crops loaded at startup from ETS/config; empty list until DB milestone
  @castles [
    %{id: 1, name: "gludio"},
    %{id: 2, name: "dion"},
    %{id: 3, name: "giran"},
    %{id: 4, name: "oren"},
    %{id: 5, name: "aden"},
    %{id: 6, name: "innadril"},
    %{id: 7, name: "goddard"},
    %{id: 8, name: "rune"},
    %{id: 9, name: "schuttgart"}
  ]

  defstruct [:mode, :timer, :castles]

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def get_mode, do: GenServer.call(__MODULE__, :get_mode)
  def get_castles, do: GenServer.call(__MODULE__, :get_castles)

  @impl GenServer
  def init(:ok) do
    mode = :approved
    timer = schedule_transition(mode)
    Logger.info("[Manor] Initialized — mode=#{mode}")
    {:ok, %__MODULE__{mode: mode, timer: timer, castles: @castles}}
  end

  @impl GenServer
  def handle_call(:get_mode, _from, state), do: {:reply, state.mode, state}
  def handle_call(:get_castles, _from, state), do: {:reply, state.castles, state}

  @impl GenServer
  def handle_info(:transition, state) do
    next_mode = next_mode(state.mode)
    timer = schedule_transition(next_mode)
    Phoenix.PubSub.broadcast(L2E.PubSub, @topic, {:manor_mode_changed, next_mode})
    Logger.info("[Manor] Mode transition: #{state.mode} → #{next_mode}")
    {:noreply, %{state | mode: next_mode, timer: timer}}
  end

  defp next_mode(:approved), do: :modifiable
  defp next_mode(:modifiable), do: :maintenance
  defp next_mode(:maintenance), do: :approved

  defp schedule_transition(:approved) do
    ms = Application.get_env(:l2e, :manor_approved_ms, @approved_ms)
    Process.send_after(self(), :transition, ms)
  end

  defp schedule_transition(:modifiable) do
    ms = Application.get_env(:l2e, :manor_modifiable_ms, @modifiable_ms)
    Process.send_after(self(), :transition, ms)
  end

  defp schedule_transition(:maintenance) do
    ms = Application.get_env(:l2e, :manor_maintenance_ms, @maintenance_ms)
    Process.send_after(self(), :transition, ms)
  end
end
