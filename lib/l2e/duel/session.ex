defmodule L2E.Duel.Session do
  @moduledoc """
  One GenServer per active duel.

  Manages duel lifecycle:
  1. :pending — waiting for defender acceptance
  2. :countdown — both accepted, 5-second countdown
  3. :active — fight in progress
  4. :ended — winner determined

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

  @impl GenServer
  def init(opts) do
    duel_id = Keyword.fetch!(opts, :duel_id)
    attacker_pid = Keyword.fetch!(opts, :attacker_pid)
    defender_pid = Keyword.fetch!(opts, :defender_pid)
    party_duel = Keyword.get(opts, :party_duel, false)

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
      phase: :pending,
      request_timer: request_timer,
      duel_timer: nil
    }

    # Register in manager
    L2E.Duel.Manager.register(duel_id, self(), get_char_id(attacker_pid), get_char_id(defender_pid))

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
    winner_pid = if char_id == get_char_id(state.attacker_pid), do: state.defender_pid, else: state.attacker_pid
    end_duel_with_winner(state, winner_pid, :surrender)
    {:stop, :normal, state}
  end

  def handle_cast({:player_died, char_id}, %{phase: :active} = state) do
    winner_pid = if char_id == get_char_id(state.attacker_pid), do: state.defender_pid, else: state.attacker_pid
    end_duel_with_winner(state, winner_pid, :death)
    {:stop, :normal, state}
  end

  def handle_cast(_, state), do: {:noreply, state}

  @impl GenServer
  def handle_info(:start_duel, %{phase: :countdown} = state) do
    Process.send_after(state.attacker_pid, {:duel_event, :duel_started, state.duel_id}, 0)
    Process.send_after(state.defender_pid, {:duel_event, :duel_started, state.duel_id}, 0)
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
    Process.send_after(state.attacker_pid, {:duel_event, :duel_ended, state.duel_id, :draw, reason}, 0)
    Process.send_after(state.defender_pid, {:duel_event, :duel_ended, state.duel_id, :draw, reason}, 0)
    L2E.Duel.Manager.unregister(state.duel_id)
  end

  defp end_duel_with_winner(state, winner_pid, reason) do
    loser_pid = if winner_pid == state.attacker_pid, do: state.defender_pid, else: state.attacker_pid
    Process.send_after(winner_pid, {:duel_event, :duel_ended, state.duel_id, :win, reason}, 0)
    Process.send_after(loser_pid, {:duel_event, :duel_ended, state.duel_id, :lose, reason}, 0)
    L2E.Duel.Manager.unregister(state.duel_id)
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
