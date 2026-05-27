defmodule L2E.Olympiad.Match do
  @moduledoc """
  Olympiad 1v1 match process.

  Lifecycle:
    :countdown  — players notified, 10s before arena teleport
    :active     — both players in arena, 5-min timer running
    :ended      — result recorded, 5s before return teleport, then stops

  Behavioral reference: OlympiadGame.java / OlympiadGameTask.java
  OTP design: temporary GenServer (crash = match lost, not server restart).
  """

  use GenServer, restart: :temporary
  require Logger

  @arena_positions [
    {186_304, -87776, -3520},
    {186_344, -87448, -3520},
    {186_368, -87712, -3520}
  ]
  @countdown_ms 10_000
  @match_timeout_ms 300_000
  @return_delay_ms 5_000
  @points_per_match 10

  # Default return point — Olympiad village (Goddard)
  @default_return_pos {82696, 148_032, -3469}

  defstruct [
    :match_id,
    :player1,
    :player2,
    :arena_pos,
    :status,
    :winner_id,
    :ref1,
    :ref2,
    :timeout_ref
  ]

  # --- Public API ---

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, [])

  @doc "Called by player_session when the player dies during an olympiad match."
  def player_died(pid, char_id), do: GenServer.cast(pid, {:player_died, char_id})

  @doc "Called by player_session when the player surrenders."
  def surrender(pid, char_id), do: GenServer.cast(pid, {:surrender, char_id})

  # --- GenServer callbacks ---

  @impl GenServer
  def init(opts) do
    match_id = Map.get(opts, :match_id, System.unique_integer([:positive]))
    player1 = Map.get(opts, :player1)
    player2 = Map.get(opts, :player2)

    arena_pos = Enum.random(@arena_positions)

    ref1 = Process.monitor(player1.pid)
    ref2 = Process.monitor(player2.pid)

    # Notify players a match is starting (opponent info for UI)
    send(
      player1.pid,
      {:olympiad_match_start, self(), Map.take(player2, [:char_id, :char_name, :class_id])}
    )

    send(
      player2.pid,
      {:olympiad_match_start, self(), Map.take(player1, [:char_id, :char_name, :class_id])}
    )

    Process.send_after(self(), :match_start, @countdown_ms)

    Logger.info("[Olympiad.Match #{match_id}] #{player1.char_name} vs #{player2.char_name}")

    state = %__MODULE__{
      match_id: match_id,
      player1: player1,
      player2: player2,
      arena_pos: arena_pos,
      status: :countdown,
      winner_id: nil,
      ref1: ref1,
      ref2: ref2,
      timeout_ref: nil
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:match_start, state) do
    {x, y, z} = state.arena_pos
    send(state.player1.pid, {:olympiad_arena_teleport, x, y, z})
    send(state.player2.pid, {:olympiad_arena_teleport, x, y, z})

    # Activate arena UI on both clients
    send(
      state.player1.pid,
      {:send_olympiad_ui_packet, %L2E.Packet.Server.ExOlympiadMode{mode: 1}}
    )

    send(
      state.player2.pid,
      {:send_olympiad_ui_packet, %L2E.Packet.Server.ExOlympiadMode{mode: 1}}
    )

    # Show opponent HP bar (placeholder stats — player structs only carry char_id/name/class)
    send(
      state.player1.pid,
      {:send_olympiad_ui_packet,
       %L2E.Packet.Server.ExOlympiadUserInfo{
         char_id: state.player2.char_id,
         char_name: state.player2.char_name || "Opponent",
         class_id: state.player2.class_id || 0,
         cur_hp: 100,
         max_hp: 100,
         cur_mp: 50,
         max_mp: 50,
         level: 1,
         side: 2
       }}
    )

    send(
      state.player2.pid,
      {:send_olympiad_ui_packet,
       %L2E.Packet.Server.ExOlympiadUserInfo{
         char_id: state.player1.char_id,
         char_name: state.player1.char_name || "Opponent",
         class_id: state.player1.class_id || 0,
         cur_hp: 100,
         max_hp: 100,
         cur_mp: 50,
         max_mp: 50,
         level: 1,
         side: 1
       }}
    )

    timeout_ref = Process.send_after(self(), :match_timeout, @match_timeout_ms)
    {:noreply, %{state | status: :active, timeout_ref: timeout_ref}}
  end

  # Player process went down while match is active → that player loses
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{status: :active} = state) do
    loser_id =
      cond do
        ref == state.ref1 -> state.player1.char_id
        ref == state.ref2 -> state.player2.char_id
        true -> nil
      end

    if loser_id do
      winner_id =
        if loser_id == state.player1.char_id,
          do: state.player2.char_id,
          else: state.player1.char_id

      {:noreply, end_match(state, winner_id, :disconnect)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  def handle_info(:match_timeout, %{status: :active} = state) do
    Logger.info("[Olympiad.Match #{state.match_id}] Timeout — draw.")
    send(state.player1.pid, {:olympiad_match_result, :draw, nil, 0})
    send(state.player2.pid, {:olympiad_match_result, :draw, nil, 0})
    timer = Process.send_after(self(), :return_players, @return_delay_ms)
    {:noreply, %{state | status: :ended, timeout_ref: timer}}
  end

  def handle_info(:match_timeout, state), do: {:noreply, state}

  def handle_info(:return_players, state) do
    p1_pos = Map.get(state.player1, :start_pos, @default_return_pos)
    p2_pos = Map.get(state.player2, :start_pos, @default_return_pos)
    send(state.player1.pid, {:olympiad_return, p1_pos})
    send(state.player2.pid, {:olympiad_return, p2_pos})
    {:stop, :normal, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def handle_cast({:player_died, char_id}, %{status: :active} = state) do
    winner_id =
      if char_id == state.player1.char_id,
        do: state.player2.char_id,
        else: state.player1.char_id

    {:noreply, end_match(state, winner_id, :death)}
  end

  def handle_cast({:surrender, char_id}, %{status: :active} = state) do
    winner_id =
      if char_id == state.player1.char_id,
        do: state.player2.char_id,
        else: state.player1.char_id

    {:noreply, end_match(state, winner_id, :surrender)}
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp end_match(state, winner_id, _reason) do
    if state.timeout_ref, do: Process.cancel_timer(state.timeout_ref)

    {winner, loser} =
      if winner_id == state.player1.char_id,
        do: {state.player1, state.player2},
        else: {state.player2, state.player1}

    L2E.Olympiad.Manager.record_result(winner.char_id, loser.char_id, @points_per_match)

    send(winner.pid, {:olympiad_match_result, :win, loser.char_name, @points_per_match})
    send(loser.pid, {:olympiad_match_result, :loss, winner.char_name, @points_per_match})

    Logger.info("[Olympiad.Match #{state.match_id}] Winner: #{winner.char_name}")

    timer = Process.send_after(self(), :return_players, @return_delay_ms)
    %{state | status: :ended, winner_id: winner_id, timeout_ref: timer}
  end
end
