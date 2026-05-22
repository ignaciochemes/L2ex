defmodule L2E.Olympiad.Manager do
  @moduledoc """
  Olympiad Manager — ETS-backed registration and point tracking.

  Behavioral reference: OlympiadManager.java
  
  OTP design: GenServer with ETS for registrations. Scheduled periods
  via Process.send_after (no polling). Each match spawns a supervised process.
  
  Foundation scope (M70):
  - Registration list
  - Point tracking  
  - Match list query
  - Period state (STARTED / ENDED)
  """

  use GenServer
  require Logger

  @table :olympiad_data

  # Period duration (1 week = 604800 seconds in production; 1 hour for dev)
  @period_ms :timer.hours(1)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Register a player for the Olympiad."
  def register(char_id, char_name, class_id) do
    GenServer.call(__MODULE__, {:register, char_id, char_name, class_id})
  end

  @doc "Unregister a player from the Olympiad."
  def unregister(char_id) do
    GenServer.cast(__MODULE__, {:unregister, char_id})
  end

  @doc "Get current Olympiad points for a player."
  def get_points(char_id) do
    case :ets.lookup(@table, {:points, char_id}) do
      [{_, points}] -> points
      [] -> 0
    end
  end

  @doc "Add points to a player (after winning a match)."
  def add_points(char_id, points) do
    GenServer.cast(__MODULE__, {:add_points, char_id, points})
  end

  @doc "Check if Olympiad period is active."
  def active? do
    case :ets.lookup(@table, :state) do
      [{:state, :started}] -> true
      _ -> false
    end
  end

  @doc "Get registration list for display."
  def registration_list do
    GenServer.call(__MODULE__, :registration_list)
  end

  @impl GenServer
  def init(_) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    :ets.insert(@table, {:state, :started})

    # Schedule period end
    Process.send_after(self(), :period_end, @period_ms)

    {:ok, %{registrations: %{}}}
  end

  @impl GenServer
  def handle_call({:register, char_id, char_name, class_id}, _from, state) do
    if Map.has_key?(state.registrations, char_id) do
      {:reply, {:error, :already_registered}, state}
    else
      entry = %{char_id: char_id, char_name: char_name, class_id: class_id, registered_at: System.monotonic_time()}
      {:reply, :ok, %{state | registrations: Map.put(state.registrations, char_id, entry)}}
    end
  end

  def handle_call(:registration_list, _from, state) do
    list = Map.values(state.registrations)
    {:reply, list, state}
  end

  @impl GenServer
  def handle_cast({:unregister, char_id}, state) do
    {:noreply, %{state | registrations: Map.delete(state.registrations, char_id)}}
  end

  def handle_cast({:add_points, char_id, points}, state) do
    current = get_points(char_id)
    :ets.insert(@table, {{:points, char_id}, current + points})
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:period_end, state) do
    Logger.info("[Olympiad] Period ended. Calculating hero points.")
    :ets.insert(@table, {:state, :ended})
    # Schedule next period
    Process.send_after(self(), :period_start, :timer.hours(1))
    {:noreply, %{state | registrations: %{}}}
  end

  def handle_info(:period_start, state) do
    Logger.info("[Olympiad] New period started.")
    :ets.insert(@table, {:state, :started})
    Process.send_after(self(), :period_end, @period_ms)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}
end
