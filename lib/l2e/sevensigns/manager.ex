defmodule L2E.SevenSigns.Manager do
  use GenServer
  require Logger

  @moduledoc """
  M61-B: Seven Signs Quest (SSQ) state machine.

  Tracks the server-wide period, cabal scores, and seal ownership.
  Period transitions are timer-driven; default period duration is
  configurable via `config :l2e, :ssq_period_ms` (default: 1 hour for dev).

  ## Periods
    - 1: Competition  — players earn seal stones, register cabals
    - 2: Seal Validation — seals awarded to winners, penalties to losers

  ## PubSub events
    - `{:ssq_period_changed, new_period, cycle}` on L2E.PubSub "world:ssq"
    - `{:ssq_cabal_registered, char_id, cabal}` on L2E.PubSub "world:ssq"

  ## Client packets
    - RequestSSQStatus (0xC7, 1-byte page) — status query; handled in packet pipeline.
      Cabal registration is NPC bypass-driven, not a dedicated packet.
  """

  @topic "world:ssq"

  defstruct [
    # 1 = Competition, 2 = Seal Validation
    :current_period,
    :current_cycle,
    :dawn_score,
    :dusk_score,
    :dawn_stones,
    :dusk_stones,
    # :dawn | :dusk | :none
    :seal_avarice,
    :seal_gnosis,
    :seal_strife,
    :period_timer
  ]

  # ─── API ──────────────────────────────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def get_period, do: GenServer.call(__MODULE__, :get_period)
  def get_scores, do: GenServer.call(__MODULE__, :get_scores)
  def get_seals, do: GenServer.call(__MODULE__, :get_seals)

  def register_cabal(char_id, cabal) when cabal in ["dawn", "dusk"] do
    GenServer.cast(__MODULE__, {:register_cabal, char_id, cabal})
  end

  def add_score(cabal, score, stone_type, stone_count) when cabal in ["dawn", "dusk"] do
    GenServer.cast(__MODULE__, {:add_score, cabal, score, stone_type, stone_count})
  end

  # ─── Init ─────────────────────────────────────────────────────────────────

  def init(:ok) do
    # 1 hour default
    period_ms = Application.get_env(:l2e, :ssq_period_ms, 3_600_000)
    timer = Process.send_after(self(), :period_transition, period_ms)

    state = %__MODULE__{
      current_period: 1,
      current_cycle: 1,
      dawn_score: 0,
      dusk_score: 0,
      dawn_stones: 0,
      dusk_stones: 0,
      seal_avarice: :none,
      seal_gnosis: :none,
      seal_strife: :none,
      period_timer: timer
    }

    Logger.info("[SevenSigns] Initialized — Period 1 (Competition), Cycle 1")
    {:ok, state}
  end

  # ─── Calls ────────────────────────────────────────────────────────────────

  def handle_call(:get_period, _from, state) do
    {:reply, {state.current_period, state.current_cycle}, state}
  end

  def handle_call(:get_scores, _from, state) do
    {:reply, %{dawn: state.dawn_score, dusk: state.dusk_score}, state}
  end

  def handle_call(:get_seals, _from, state) do
    {:reply, %{avarice: state.seal_avarice, gnosis: state.seal_gnosis, strife: state.seal_strife},
     state}
  end

  # ─── Casts ────────────────────────────────────────────────────────────────

  def handle_cast({:register_cabal, char_id, cabal}, state) do
    # Only during Competition period
    if state.current_period == 1 do
      Phoenix.PubSub.broadcast(L2E.PubSub, @topic, {:ssq_cabal_registered, char_id, cabal})
    end

    {:noreply, state}
  end

  def handle_cast({:add_score, cabal, score, stone_type, stone_count}, state) do
    state =
      case cabal do
        "dawn" ->
          new_state = update_stones(state, :dawn, stone_type, stone_count)
          %{new_state | dawn_score: new_state.dawn_score + score}

        "dusk" ->
          new_state = update_stones(state, :dusk, stone_type, stone_count)
          %{new_state | dusk_score: new_state.dusk_score + score}
      end

    {:noreply, state}
  end

  # ─── Period Transition ────────────────────────────────────────────────────

  def handle_info(:period_transition, state) do
    period_ms = Application.get_env(:l2e, :ssq_period_ms, 3_600_000)

    {new_period, new_cycle, new_state} =
      case state.current_period do
        1 ->
          # Competition ended → Seal Validation
          new_state = %{state | current_period: 2}
          {2, state.current_cycle, new_state}

        2 ->
          # Seal Validation ended → award seals, reset scores, new cycle
          next_cycle = state.current_cycle + 1
          new_state = award_seals(state)

          new_state = %{
            new_state
            | current_period: 1,
              current_cycle: next_cycle,
              dawn_score: 0,
              dusk_score: 0,
              dawn_stones: 0,
              dusk_stones: 0
          }

          {1, next_cycle, new_state}
      end

    timer = Process.send_after(self(), :period_transition, period_ms)
    new_state = %{new_state | period_timer: timer}

    Logger.info("[SevenSigns] Period #{new_period} started — Cycle #{new_cycle}")
    Phoenix.PubSub.broadcast(L2E.PubSub, @topic, {:ssq_period_changed, new_period, new_cycle})
    {:noreply, new_state}
  end

  # ─── Helpers ──────────────────────────────────────────────────────────────

  defp award_seals(state) do
    winner =
      cond do
        state.dawn_score > state.dusk_score -> :dawn
        state.dusk_score > state.dawn_score -> :dusk
        true -> :none
      end

    %{state | seal_avarice: winner, seal_gnosis: winner, seal_strife: winner}
  end

  defp update_stones(state, cabal, stone_type, count) do
    case {cabal, stone_type} do
      {:dawn, :blue} -> %{state | dawn_stones: state.dawn_stones + count}
      {:dawn, :green} -> %{state | dawn_stones: state.dawn_stones + count}
      {:dawn, :red} -> %{state | dawn_stones: state.dawn_stones + count}
      {:dusk, :blue} -> %{state | dusk_stones: state.dusk_stones + count}
      {:dusk, :green} -> %{state | dusk_stones: state.dusk_stones + count}
      {:dusk, :red} -> %{state | dusk_stones: state.dusk_stones + count}
      _ -> state
    end
  end
end
