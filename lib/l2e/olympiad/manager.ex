defmodule L2E.Olympiad.Manager do
  @moduledoc """
  Olympiad Manager — period state machine, registration, point tracking, hero election.

  Behavioral reference: OlympiadManager.java

  OTP design: GenServer with ETS for fast reads. Scheduled periods via
  Process.send_after (no polling). Each match spawns a supervised process.
  Pairing runs every 5 minutes during the competition period.

  Period state machine:
    :competition  — players register and matches are paired every 5 min
    :validation   — period ended, heroes elected, waiting for next cycle
    :non_active   — server startup / not yet initialised

  M97 additions:
  - Full period state machine (:competition → :validation → :competition)
  - Periodic match pairing (every 5 min during :competition)
  - Class-based hero election via L2E.DB.Hero.elect/1
  - PubSub broadcasts on period transitions
  - Explicit register_player/4, deregister_player/1, get_registered/0, get_period/0 API
  """

  use GenServer
  require Logger

  @table :olympiad_data

  # Dev timers (override in prod config for 14-day competition / 7-day validation)
  @competition_ms :timer.minutes(60)
  @validation_ms :timer.minutes(30)
  @pairing_interval_ms :timer.minutes(5)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Register a player with a session pid (M97 API)."
  def register_player(char_id, class_id, char_name, char_pid),
    do: GenServer.call(__MODULE__, {:register_player, char_id, class_id, char_name, char_pid})

  @doc "Deregister a player from the Olympiad."
  def deregister_player(char_id),
    do: GenServer.call(__MODULE__, {:deregister_player, char_id})

  @doc "Get the current list of registered players."
  def get_registered, do: GenServer.call(__MODULE__, :registration_list)

  @doc "Get current period atom (:competition | :validation | :non_active)."
  def get_period, do: GenServer.call(__MODULE__, :get_period)

  @doc "Add (or subtract) points for a player after a match."
  def add_points(char_id, amount),
    do: GenServer.cast(__MODULE__, {:add_points, char_id, amount})

  @doc "Record a full match result (winner/loser ids + delta). Called by Match.end_match."
  def record_result(winner_id, loser_id, points_delta),
    do: GenServer.cast(__MODULE__, {:record_result, winner_id, loser_id, points_delta})

  # --- Legacy API (kept for backward compat) ---

  @doc "Register a player without a pid."
  def register(char_id, char_name, class_id),
    do: GenServer.call(__MODULE__, {:register_player, char_id, class_id, char_name, nil})

  @doc "Register a player with a pid (legacy 4-arg form)."
  def register(char_id, char_name, class_id, pid) when is_pid(pid),
    do: register_player(char_id, class_id, char_name, pid)

  @doc "Unregister a player (legacy cast form)."
  def unregister(char_id),
    do: GenServer.cast(__MODULE__, {:unregister, char_id})

  @doc "Get the registration list (legacy alias)."
  def registration_list, do: get_registered()

  @doc "Get current Olympiad points for a player (ETS fast-path)."
  def get_points(char_id) do
    case :ets.lookup(@table, {:points, char_id}) do
      [{_, pts}] -> pts
      [] -> 0
    end
  end

  @doc "True when the competition period is active."
  def active? do
    case :ets.lookup(@table, :period) do
      [{:period, :competition}] -> true
      _ -> false
    end
  end

  @doc "Get the current elected heroes list (ETS fast-path)."
  def get_heroes do
    case :ets.lookup(@table, :heroes) do
      [{:heroes, heroes}] -> heroes
      [] -> []
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer init
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(_) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    :ets.insert(@table, {:period, :competition})

    Process.send_after(self(), :end_competition_period, @competition_ms)
    Process.send_after(self(), :pair_matches, @pairing_interval_ms)

    {:ok,
     %{
       period: :competition,
       registered_players: %{},
       match_count: 0,
       points: %{}
     }}
  end

  # ---------------------------------------------------------------------------
  # handle_call
  # ---------------------------------------------------------------------------

  @impl GenServer
  def handle_call({:register_player, char_id, class_id, char_name, char_pid}, _from, state) do
    cond do
      state.period != :competition ->
        {:reply, {:error, :wrong_period}, state}

      Map.has_key?(state.registered_players, char_id) ->
        {:reply, {:error, :already_registered}, state}

      true ->
        entry = %{
          char_id: char_id,
          char_name: char_name,
          class_id: class_id,
          pid: char_pid,
          registered_at: System.monotonic_time()
        }

        new_state = %{
          state
          | registered_players: Map.put(state.registered_players, char_id, entry)
        }

        {:reply, :ok, new_state}
    end
  end

  def handle_call({:deregister_player, char_id}, _from, state) do
    new_state = %{state | registered_players: Map.delete(state.registered_players, char_id)}
    {:reply, :ok, new_state}
  end

  def handle_call(:registration_list, _from, state) do
    {:reply, Map.values(state.registered_players), state}
  end

  def handle_call(:get_period, _from, state) do
    {:reply, state.period, state}
  end

  # ---------------------------------------------------------------------------
  # handle_cast
  # ---------------------------------------------------------------------------

  @impl GenServer
  def handle_cast({:unregister, char_id}, state) do
    {:noreply, %{state | registered_players: Map.delete(state.registered_players, char_id)}}
  end

  def handle_cast({:add_points, char_id, amount}, state) do
    current = Map.get(state.points, char_id, 0)
    new_pts = max(0, current + amount)
    :ets.insert(@table, {{:points, char_id}, new_pts})
    new_points = Map.put(state.points, char_id, new_pts)
    Task.start(fn -> persist_points(char_id, new_pts) end)
    {:noreply, %{state | points: new_points}}
  end

  def handle_cast({:record_result, winner_id, loser_id, points_delta}, state) do
    state1 =
      if winner_id do
        current = Map.get(state.points, winner_id, 0)
        new_pts = current + points_delta
        :ets.insert(@table, {{:points, winner_id}, new_pts})
        %{state | points: Map.put(state.points, winner_id, new_pts)}
      else
        state
      end

    state2 =
      if loser_id do
        current = Map.get(state1.points, loser_id, 0)
        new_pts = max(0, current - points_delta)
        :ets.insert(@table, {{:points, loser_id}, new_pts})
        %{state1 | points: Map.put(state1.points, loser_id, new_pts)}
      else
        state1
      end

    winner_reg = winner_id && Map.get(state.registered_players, winner_id)
    loser_reg = loser_id && Map.get(state.registered_players, loser_id)

    if winner_reg && loser_reg do
      Task.start(fn ->
        L2E.DB.OlympiadHistory.insert(1, winner_reg, loser_reg, points_delta)
      end)
    end

    {:noreply, state2}
  end

  # ---------------------------------------------------------------------------
  # handle_info — period state machine
  # ---------------------------------------------------------------------------

  @impl GenServer
  def handle_info(:end_competition_period, state) do
    Logger.info("[Olympiad] Competition period ended. Entering validation.")
    :ets.insert(@table, {:period, :validation})

    elect_heroes(state.points, state.registered_players)

    Phoenix.PubSub.broadcast(L2E.PubSub, "olympiad", {:olympiad_period_changed, :validation})
    Process.send_after(self(), :start_competition_period, @validation_ms)

    {:noreply, %{state | period: :validation, match_count: 0}}
  end

  def handle_info(:start_competition_period, state) do
    Logger.info("[Olympiad] New competition period started.")
    :ets.insert(@table, {:period, :competition})

    Phoenix.PubSub.broadcast(L2E.PubSub, "olympiad", {:olympiad_period_changed, :competition})
    Process.send_after(self(), :end_competition_period, @competition_ms)
    Process.send_after(self(), :pair_matches, @pairing_interval_ms)

    {:noreply,
     %{state | period: :competition, registered_players: %{}, points: %{}, match_count: 0}}
  end

  def handle_info(:pair_matches, %{period: :competition} = state) do
    players =
      state.registered_players
      |> Map.values()
      |> Enum.filter(&(&1.pid != nil))
      |> Enum.shuffle()

    pairs = do_pair(players, [])

    paired_ids = Enum.flat_map(pairs, fn {p1, p2} -> [p1.char_id, p2.char_id] end)

    Enum.each(pairs, fn {p1, p2} ->
      L2E.Olympiad.Supervisor.start_match(%{
        match_id: System.unique_integer([:positive]),
        player1: p1,
        player2: p2
      })
    end)

    if length(pairs) > 0 do
      Logger.info("[Olympiad] Paired #{length(pairs)} matches from #{length(players)} waiting.")
    end

    remaining = Map.drop(state.registered_players, paired_ids)

    Process.send_after(self(), :pair_matches, @pairing_interval_ms)

    {:noreply,
     %{
       state
       | registered_players: remaining,
         match_count: state.match_count + length(pairs)
     }}
  end

  # During validation/non_active periods, discard pairing ticks
  def handle_info(:pair_matches, state), do: {:noreply, state}

  # Legacy message compat
  def handle_info(:period_end, state), do: handle_info(:end_competition_period, state)
  def handle_info(:period_start, state), do: handle_info(:start_competition_period, state)

  def handle_info(_, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_pair([], acc), do: acc
  defp do_pair([_], acc), do: acc
  defp do_pair([p1, p2 | rest], acc), do: do_pair(rest, [{p1, p2} | acc])

  # Elect heroes: top-points player per class, persisted to DB.Hero.
  # Falls back to top-5 overall if registration data is sparse.
  defp elect_heroes(points_map, _registered_players) when map_size(points_map) == 0, do: :ok

  defp elect_heroes(points_map, registered_players) do
    # Group char_ids by class, then pick the top-points winner per class
    heroes =
      points_map
      |> Enum.reduce(%{}, fn {char_id, pts}, acc ->
        case Map.get(registered_players, char_id) do
          nil ->
            acc

          reg ->
            class_id = reg.class_id
            existing_pts = acc |> Map.get(class_id, {nil, -1}) |> elem(1)

            if pts > existing_pts,
              do: Map.put(acc, class_id, {reg, pts}),
              else: acc
        end
      end)
      |> Map.values()
      |> Enum.map(fn {reg, _pts} ->
        %{char_id: reg.char_id, char_name: reg.char_name, class_id: reg.class_id}
      end)

    if heroes == [] do
      :ok
    else
      elected_ids = Enum.map(heroes, & &1.char_id)
      :ets.insert(@table, {:heroes, heroes})

      Task.start(fn ->
        L2E.DB.Hero.elect(heroes)

        Phoenix.PubSub.broadcast(
          L2E.PubSub,
          "world:hero_update",
          {:heroes_elected, elected_ids}
        )
      end)
    end
  end

  # No-op placeholder for point persistence (extend with DB write if needed)
  defp persist_points(_char_id, _points), do: :ok
end
