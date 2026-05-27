defmodule L2E.Duel.Session do
  @moduledoc """
  One GenServer per active duel.

  Manages duel lifecycle:
  1. :pending — waiting for defender acceptance
  2. :countdown — both accepted, 5-second countdown
  3. :active — fight in progress
  4. :ended — winner determined

  M112 additions:
  - Auto-winner detection at 10% HP threshold (per party side for party duels)
  - Zone boundary enforcement: cancel if player moves > 1600 units from start
  - Party duel mode: attacker_members + defender_members track all participants

  Event-driven: no polling. Uses Process.send_after for countdown and timeout.
  Crash semantics: :temporary — do NOT restart.
  """

  use GenServer, restart: :temporary

  require Logger

  # Duel timeout: 5 minutes max
  @duel_timeout_ms 300_000
  # Countdown before duel starts
  @countdown_ms 5_000
  # Pending duel request timeout: 30 seconds
  @request_timeout_ms 30_000
  # M112: Zone boundary in L2 world units (2D Euclidean)
  @boundary_distance 1600

  def start_link(opts) do
    duel_id = Keyword.fetch!(opts, :duel_id)
    GenServer.start_link(__MODULE__, opts, name: via(duel_id))
  end

  def via(duel_id), do: {:via, Registry, {L2E.Duel.Registry, duel_id}}

  @doc "Attacker confirms duel start (after defender accepted)."
  def start(duel_id), do: GenServer.cast(via(duel_id), :start)

  @doc "Accept the duel (called by defender)."
  def accept(duel_id), do: GenServer.cast(via(duel_id), :accept)

  @doc "Decline the duel (called by defender or attacker)."
  def decline(duel_id), do: GenServer.cast(via(duel_id), :decline)

  @doc "Surrender (called by a player)."
  def surrender(duel_id, char_id), do: GenServer.cast(via(duel_id), {:surrender, char_id})

  @doc "Notify the duel session that one player died."
  def player_died(duel_id, char_id), do: GenServer.cast(via(duel_id), {:player_died, char_id})

  @doc "M112: Notify duel session of a player HP update (10% threshold check)."
  def notify_hp_update(duel_id, player_pid, current_hp, max_hp) do
    case Registry.lookup(L2E.Duel.Registry, duel_id) do
      [{pid, _}] -> GenServer.cast(pid, {:player_hp_update, player_pid, current_hp, max_hp})
      [] -> :ok
    end
  end

  @doc "M112: Notify duel session that a player moved (zone boundary check)."
  def notify_move(duel_id, player_pid, x, y, z) do
    case Registry.lookup(L2E.Duel.Registry, duel_id) do
      [{pid, _}] -> GenServer.cast(pid, {:player_moved, player_pid, x, y, z})
      [] -> :ok
    end
  end

  @impl GenServer
  def init(opts) do
    duel_id = Keyword.fetch!(opts, :duel_id)
    attacker_pid = Keyword.fetch!(opts, :attacker_pid)
    defender_pid = Keyword.fetch!(opts, :defender_pid)
    party_duel = Keyword.get(opts, :party_duel, false)
    # M112: Party member PID lists — empty for solo duel
    attacker_members = Keyword.get(opts, :attacker_members, [])
    defender_members = Keyword.get(opts, :defender_members, [])

    # Monitor both players
    attacker_ref = Process.monitor(attacker_pid)
    defender_ref = Process.monitor(defender_pid)

    # Request timeout — if defender doesn't respond in 30s, cancel
    request_timer = Process.send_after(self(), :request_timeout, @request_timeout_ms)

    state = %{
      duel_id: duel_id,
      attacker_pid: attacker_pid,
      defender_pid: defender_pid,
      attacker_ref: attacker_ref,
      defender_ref: defender_ref,
      party_duel: party_duel,
      duel_type: if(party_duel, do: :party, else: :solo),
      # M112: Full member lists (solo: empty → falls back to main pids)
      attacker_members: attacker_members,
      defender_members: defender_members,
      # M112: Zone boundary — recorded on each player's first move report
      attacker_start: nil,
      defender_start: nil,
      # M112: Track which member pids have crossed the 10% HP threshold
      attacker_below_threshold: MapSet.new(),
      defender_below_threshold: MapSet.new(),
      phase: :pending,
      request_timer: request_timer,
      duel_timer: nil
    }

    # Register in manager
    L2E.Duel.Manager.register(
      duel_id,
      self(),
      get_char_id(attacker_pid),
      get_char_id(defender_pid)
    )

    {:ok, state}
  end

  @impl GenServer
  def handle_cast(:accept, %{phase: :pending} = state) do
    Process.cancel_timer(state.request_timer)
    # Start countdown
    Process.send_after(state.attacker_pid, {:duel_event, :countdown_start, state.duel_id}, 0)
    Process.send_after(state.defender_pid, {:duel_event, :countdown_start, state.duel_id}, 0)
    duel_timer = Process.send_after(self(), :start_duel, @countdown_ms)
    {:noreply, %{state | phase: :countdown, request_timer: nil, duel_timer: duel_timer}}
  end

  def handle_cast(:decline, state) do
    end_duel(state, :declined)
    {:stop, :normal, state}
  end

  def handle_cast({:surrender, char_id}, %{phase: :active} = state) do
    winner_pid =
      if char_id == get_char_id(state.attacker_pid),
        do: state.defender_pid,
        else: state.attacker_pid

    end_duel_with_winner(state, winner_pid, :surrender)
    {:stop, :normal, state}
  end

  def handle_cast({:player_died, char_id}, %{phase: :active} = state) do
    winner_pid =
      if char_id == get_char_id(state.attacker_pid),
        do: state.defender_pid,
        else: state.attacker_pid

    end_duel_with_winner(state, winner_pid, :death)
    {:stop, :normal, state}
  end

  # M112: 10% HP threshold — end duel early when a whole side is below threshold
  def handle_cast(
        {:player_hp_update, player_pid, current_hp, max_hp},
        %{phase: :active} = state
      ) do
    hp_pct = if max_hp > 0, do: current_hp / max_hp, else: 0.0

    if hp_pct <= 0.1 do
      {new_state, loser_side} = mark_eliminated(state, player_pid)

      case loser_side do
        nil ->
          {:noreply, new_state}

        :attacker ->
          end_duel_with_winner(new_state, new_state.defender_pid, :hp_threshold)
          {:stop, :normal, new_state}

        :defender ->
          end_duel_with_winner(new_state, new_state.attacker_pid, :hp_threshold)
          {:stop, :normal, new_state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_cast({:player_hp_update, _pid, _hp, _max}, state), do: {:noreply, state}

  # M112: Zone boundary enforcement — first report sets start; subsequent reports enforce
  def handle_cast({:player_moved, player_pid, x, y, z}, %{phase: :active} = state) do
    cond do
      player_pid == state.attacker_pid and is_nil(state.attacker_start) ->
        {:noreply, %{state | attacker_start: {x, y, z}}}

      player_pid == state.defender_pid and is_nil(state.defender_start) ->
        {:noreply, %{state | defender_start: {x, y, z}}}

      player_pid == state.attacker_pid ->
        if distance(state.attacker_start, {x, y, z}) > @boundary_distance do
          end_duel(state, :boundary_exceeded)
          {:stop, :normal, state}
        else
          {:noreply, state}
        end

      player_pid == state.defender_pid ->
        if distance(state.defender_start, {x, y, z}) > @boundary_distance do
          end_duel(state, :boundary_exceeded)
          {:stop, :normal, state}
        else
          {:noreply, state}
        end

      true ->
        {:noreply, state}
    end
  end

  def handle_cast({:player_moved, _pid, _x, _y, _z}, state), do: {:noreply, state}

  def handle_cast(_, state), do: {:noreply, state}

  @impl GenServer
  def handle_info(:start_duel, %{phase: :countdown} = state) do
    # Notify all participants — covers party members in addition to the two leaders
    all_pids = get_side_pids(state, :attacker) ++ get_side_pids(state, :defender)

    Enum.each(all_pids, fn pid ->
      Process.send_after(pid, {:duel_event, :duel_started, state.duel_id}, 0)
    end)

    duel_timer = Process.send_after(self(), :duel_timeout, @duel_timeout_ms)
    {:noreply, %{state | phase: :active, duel_timer: duel_timer}}
  end

  def handle_info(:request_timeout, %{phase: :pending} = state) do
    end_duel(state, :timeout)
    {:stop, :normal, state}
  end

  def handle_info(:duel_timeout, %{phase: :active} = state) do
    # Timeout = draw
    end_duel(state, :timeout)
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    if ref == state.attacker_ref or ref == state.defender_ref do
      end_duel(state, :disconnect)
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  defp end_duel(state, reason) do
    all_pids = get_side_pids(state, :attacker) ++ get_side_pids(state, :defender)

    Enum.each(all_pids, fn pid ->
      Process.send_after(pid, {:duel_event, :duel_ended, state.duel_id, :draw, reason}, 0)
    end)

    L2E.Duel.Manager.unregister(state.duel_id)
  end

  defp end_duel_with_winner(state, winner_pid, reason) do
    winner_side = if winner_pid == state.attacker_pid, do: :attacker, else: :defender
    loser_side = if winner_side == :attacker, do: :defender, else: :attacker

    Enum.each(get_side_pids(state, winner_side), fn pid ->
      Process.send_after(pid, {:duel_event, :duel_ended, state.duel_id, :win, reason}, 0)
    end)

    Enum.each(get_side_pids(state, loser_side), fn pid ->
      Process.send_after(pid, {:duel_event, :duel_ended, state.duel_id, :lose, reason}, 0)
    end)

    L2E.Duel.Manager.unregister(state.duel_id)
  end

  # Returns all PIDs for a side; falls back to the main leader pid if no member list
  defp get_side_pids(state, :attacker) do
    case state.attacker_members do
      [] -> [state.attacker_pid]
      members -> members
    end
  end

  defp get_side_pids(state, :defender) do
    case state.defender_members do
      [] -> [state.defender_pid]
      members -> members
    end
  end

  # Mark a player pid as below threshold; returns {new_state, loser_side | nil}
  defp mark_eliminated(state, player_pid) do
    attacker_pids = get_side_pids(state, :attacker)
    defender_pids = get_side_pids(state, :defender)

    cond do
      player_pid in attacker_pids ->
        new_elim = MapSet.put(state.attacker_below_threshold, player_pid)
        new_state = %{state | attacker_below_threshold: new_elim}

        if MapSet.size(new_elim) >= length(attacker_pids),
          do: {new_state, :attacker},
          else: {new_state, nil}

      player_pid in defender_pids ->
        new_elim = MapSet.put(state.defender_below_threshold, player_pid)
        new_state = %{state | defender_below_threshold: new_elim}

        if MapSet.size(new_elim) >= length(defender_pids),
          do: {new_state, :defender},
          else: {new_state, nil}

      true ->
        {state, nil}
    end
  end

  # 2D Euclidean distance — ignores Z for terrain-independent boundary check
  defp distance({x1, y1, _z1}, {x2, y2, _z2}) do
    :math.sqrt(:math.pow(x2 - x1, 2) + :math.pow(y2 - y1, 2))
  end

  defp get_char_id(session_pid) do
    # Ask the player session for its char_id
    try do
      GenServer.call(session_pid, :get_char_id, 1000)
    catch
      _, _ -> nil
    end
  end
end
