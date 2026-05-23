defmodule L2E.GrandBoss.Manager do
  use GenServer
  require Logger

  @moduledoc """
  M61-A: Grand Boss respawn window tracking.

  Tracks the alive/dead/waiting state of all Interlude grand bosses.
  Persists state in ETS. Actual NPC spawning is delegated to SpawnTable.
  """

  # Boss IDs from L2J Mobius CT0 data
  @bosses %{
    29022 => %{name: "Antharas",  respawn_min_h: 192, respawn_max_h: 200},
    29028 => %{name: "Valakas",   respawn_min_h: 264, respawn_max_h: 280},
    29020 => %{name: "Baium",     respawn_min_h: 121, respawn_max_h: 143},
    29026 => %{name: "Zaken",     respawn_min_h: 60,  respawn_max_h: 84},
    29006 => %{name: "Core",      respawn_min_h: 36,  respawn_max_h: 44},
    29014 => %{name: "Orfen",     respawn_min_h: 36,  respawn_max_h: 44},
    29001 => %{name: "Queen Ant", respawn_min_h: 19,  respawn_max_h: 35},
    29045 => %{name: "Frintezza", respawn_min_h: 48,  respawn_max_h: 52},
    29046 => %{name: "Sailren",   respawn_min_h: 12,  respawn_max_h: 36}
  }

  # State: %{boss_id => %{state: :alive | :dead | :waiting, respawn_at: DateTime | nil}}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    :ets.new(:grand_boss_states, [:named_table, :public, read_concurrency: true])

    Enum.each(@bosses, fn {id, _info} ->
      :ets.insert(:grand_boss_states, {id, :alive, nil})
    end)

    Logger.info("[GrandBossManager] initialized #{map_size(@bosses)} boss slots")
    {:ok, %{}}
  end

  # ─── Public API ────────────────────────────────────────────────────────────

  def get_state(boss_id) do
    case :ets.lookup(:grand_boss_states, boss_id) do
      [{^boss_id, state, respawn_at}] -> {state, respawn_at}
      [] -> {:unknown, nil}
    end
  end

  def set_dead(boss_id) do
    GenServer.cast(__MODULE__, {:boss_died, boss_id})
  end

  def set_alive(boss_id) do
    :ets.insert(:grand_boss_states, {boss_id, :alive, nil})
  end

  # ─── Internals ─────────────────────────────────────────────────────────────

  def handle_cast({:boss_died, boss_id}, state) do
    case Map.get(@bosses, boss_id) do
      nil ->
        {:noreply, state}

      %{respawn_min_h: min_h, respawn_max_h: max_h} ->
        range_ms = (max_h - min_h) * 3_600_000
        delay_ms = min_h * 3_600_000 + :rand.uniform(max(1, range_ms))
        respawn_at = DateTime.utc_now() |> DateTime.add(div(delay_ms, 1000), :second)
        :ets.insert(:grand_boss_states, {boss_id, :dead, respawn_at})
        Process.send_after(self(), {:respawn_window_open, boss_id}, delay_ms)
        Logger.info("[GrandBossManager] #{boss_id} dead — respawn at #{respawn_at}")
        {:noreply, state}
    end
  end

  def handle_info({:respawn_window_open, boss_id}, state) do
    :ets.insert(:grand_boss_states, {boss_id, :waiting, nil})
    Logger.info("[GrandBossManager] #{boss_id} respawn window open")
    {:noreply, state}
  end
end
