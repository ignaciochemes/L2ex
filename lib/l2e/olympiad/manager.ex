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

  M70-B additions:
  - Match pairing and launch at period end
  - Result recording (winner/loser point deltas)
  - Hero determination (top-points player per class)
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

  @doc "Register a player with their session pid (required for match teleports)."
  def register(char_id, char_name, class_id, pid) when is_pid(pid) do
    GenServer.call(__MODULE__, {:register, char_id, char_name, class_id, pid})
  end

  @doc "Record a match result. winner_id/loser_id may be nil for draws."
  def record_result(winner_id, loser_id, points_delta) do
    GenServer.cast(__MODULE__, {:record_result, winner_id, loser_id, points_delta})
  end

  @doc "Get current heroes: top-points player per class."
  def get_heroes do
    case :ets.lookup(@table, :heroes) do
      [{:heroes, heroes}] -> heroes
      [] -> []
    end
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
      entry = %{
        char_id: char_id,
        char_name: char_name,
        class_id: class_id,
        pid: nil,
        registered_at: System.monotonic_time()
      }

      {:reply, :ok, %{state | registrations: Map.put(state.registrations, char_id, entry)}}
    end
  end

  def handle_call({:register, char_id, char_name, class_id, pid}, _from, state) do
    if Map.has_key?(state.registrations, char_id) do
      {:reply, {:error, :already_registered}, state}
    else
      entry = %{
        char_id: char_id,
        char_name: char_name,
        class_id: class_id,
        pid: pid,
        registered_at: System.monotonic_time()
      }

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

  def handle_cast({:record_result, winner_id, loser_id, points_delta}, state) do
    if winner_id do
      winner_pts = get_points(winner_id)
      :ets.insert(@table, {{:points, winner_id}, winner_pts + points_delta})
    end

    if loser_id do
      loser_pts = get_points(loser_id)
      :ets.insert(@table, {{:points, loser_id}, max(0, loser_pts - points_delta)})
    end

    # Persist match result
    winner_reg = winner_id && Map.get(state.registrations, winner_id)
    loser_reg = loser_id && Map.get(state.registrations, loser_id)
    if winner_reg && loser_reg do
      Task.start(fn ->
        L2E.DB.OlympiadHistory.insert(1, winner_reg, loser_reg, points_delta)
      end)
    end
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:period_end, state) do
    Logger.info("[Olympiad] Period ended. Pairing players and calculating heroes.")
    :ets.insert(@table, {:state, :ended})

    players = Map.values(state.registrations)

    # Pair registered players into 1v1 matches
    matches = pair_players(players)

    Enum.each(matches, fn {p1, p2} ->
      L2E.Olympiad.Supervisor.start_match(%{
        match_id: System.unique_integer([:positive]),
        player1: p1,
        player2: p2
      })
    end)

    Logger.info(
      "[Olympiad] Started #{length(matches)} matches from #{length(players)} registrants."
    )

    # Determine heroes (top-points player per class this period)
    heroes = determine_heroes(players)
    :ets.insert(@table, {:heroes, heroes})
    Phoenix.PubSub.broadcast(L2E.PubSub, "world:olympiad", {:heroes_determined, heroes})

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

  # --- Private ---

  defp pair_players(players) do
    players
    |> Enum.filter(&(&1.pid != nil))
    |> Enum.shuffle()
    |> do_pair([])
  end

  defp do_pair([], acc), do: acc
  defp do_pair([_], acc), do: acc
  defp do_pair([p1, p2 | rest], acc), do: do_pair(rest, [{p1, p2} | acc])

  defp determine_heroes([]), do: []

  defp determine_heroes(players) do
    players
    |> Enum.group_by(& &1.class_id)
    |> Enum.map(fn {class_id, class_players} ->
      hero = Enum.max_by(class_players, fn p -> get_points(p.char_id) end)
      %{class_id: class_id, char_id: hero.char_id, char_name: hero.char_name}
    end)
  end
end
