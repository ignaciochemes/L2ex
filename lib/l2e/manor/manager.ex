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
  # 6 hours
  @approved_ms 6 * 60 * 60 * 1000
  # 4 hours
  @modifiable_ms 4 * 60 * 60 * 1000
  # 5 minutes
  @maintenance_ms 5 * 60 * 1000

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

  defstruct [:mode, :timer, :castles, production: %{}, procure: %{}]

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def get_mode, do: GenServer.call(__MODULE__, :get_mode)
  def get_castles, do: GenServer.call(__MODULE__, :get_castles)

  def sow_seed(castle_id, seed_id, amount),
    do: GenServer.call(__MODULE__, {:sow_seed, castle_id, seed_id, amount})

  def set_crop_procure(castle_id, item_id, amount),
    do: GenServer.call(__MODULE__, {:set_crop_procure, castle_id, item_id, amount})

  def get_production_list(castle_id),
    do: GenServer.call(__MODULE__, {:get_production_list, castle_id})

  def get_procure_list(castle_id),
    do: GenServer.call(__MODULE__, {:get_procure_list, castle_id})

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

  def handle_call({:get_production_list, castle_id}, _from, state) do
    {:reply, Map.get(state.production, castle_id, []), state}
  end

  def handle_call({:get_procure_list, castle_id}, _from, state) do
    {:reply, Map.get(state.procure, castle_id, []), state}
  end

  def handle_call({:sow_seed, _castle_id, _seed_id, _amount}, _from, state)
      when state.mode != :modifiable do
    {:reply, {:error, :wrong_mode}, state}
  end

  def handle_call({:sow_seed, castle_id, seed_id, amount}, _from, state) do
    entry = %{seed_id: seed_id, amount: amount, start_amount: amount, price: 0, period: 1}

    existing = Map.get(state.production, castle_id, [])
    updated = Enum.reject(existing, &(&1.seed_id == seed_id))
    new_list = [entry | updated]
    new_production = Map.put(state.production, castle_id, new_list)

    attrs = %{
      castle_id: castle_id,
      seed_id: seed_id,
      amount: amount,
      start_amount: amount,
      sold: 0,
      price: 0
    }

    %L2E.DB.ManorProduction{}
    |> L2E.DB.ManorProduction.changeset(attrs)
    |> L2E.Repo.insert(on_conflict: :replace_all, conflict_target: [:castle_id, :seed_id])

    {:reply, :ok, %{state | production: new_production}}
  end

  def handle_call({:set_crop_procure, _castle_id, _item_id, _amount}, _from, state)
      when state.mode != :modifiable do
    {:reply, {:error, :wrong_mode}, state}
  end

  def handle_call({:set_crop_procure, castle_id, item_id, amount}, _from, state) do
    entry = %{
      item_id: item_id,
      amount: amount,
      start_amount: amount,
      reward_type: 0,
      price: 0,
      period: 1
    }

    existing = Map.get(state.procure, castle_id, [])
    updated = Enum.reject(existing, &(&1.item_id == item_id))
    new_list = [entry | updated]
    new_procure = Map.put(state.procure, castle_id, new_list)

    attrs = %{
      castle_id: castle_id,
      item_id: item_id,
      amount: amount,
      start_amount: amount,
      reward_type: 0,
      cost: 0
    }

    %L2E.DB.ManorProcure{}
    |> L2E.DB.ManorProcure.changeset(attrs)
    |> L2E.Repo.insert(on_conflict: :replace_all, conflict_target: [:castle_id, :item_id])

    {:reply, :ok, %{state | procure: new_procure}}
  end

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
