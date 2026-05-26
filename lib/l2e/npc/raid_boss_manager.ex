defmodule L2E.NPC.RaidBossManager do
  @moduledoc """
  Tracks live/dead state and respawn windows for raid-class bosses.
  Each boss_id maps to: :alive | {:respawning, respawn_at_unix_ms}

  Grand bosses (Antharas, Valakas, etc.) are managed separately in
  L2E.GrandBoss.Manager. This module covers all other raid-type NPCs.
  """
  use GenServer
  require Logger

  @table :raid_boss_state
  # Respawn window: 12h ± 6h
  @base_respawn_ms 12 * 60 * 60 * 1000
  @window_ms 6 * 60 * 60 * 1000

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def boss_died(boss_id, npc_template) do
    GenServer.cast(__MODULE__, {:boss_died, boss_id, npc_template})
  end

  def boss_alive?(boss_id) do
    case :ets.lookup(@table, boss_id) do
      [{_, :alive}] -> true
      _ -> false
    end
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    load_from_db()
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:boss_died, boss_id, template}, state) do
    jitter = :rand.uniform(@window_ms * 2) - @window_ms
    respawn_ms = @base_respawn_ms + jitter
    respawn_at = System.monotonic_time(:millisecond) + respawn_ms

    :ets.insert(@table, {boss_id, {:respawning, respawn_at}})
    persist_state(boss_id, "dead", respawn_at)

    Process.send_after(self(), {:respawn_boss, boss_id, template}, respawn_ms)

    Logger.info(
      "[RaidBossManager] Boss #{boss_id} died. Respawn in #{div(respawn_ms, 60_000)} min"
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:respawn_boss, boss_id, template}, state) do
    Logger.info("[RaidBossManager] Spawning raid boss #{boss_id}")
    :ets.insert(@table, {boss_id, :alive})
    persist_state(boss_id, "alive", 0)
    L2E.NPC.SpawnTable.spawn_boss(boss_id, template)
    {:noreply, state}
  end

  defp load_from_db do
    try do
      rows = L2E.Repo.all(L2E.DB.RaidBossState)
      now = System.monotonic_time(:millisecond)

      Enum.each(rows, fn row ->
        case row.state do
          "alive" ->
            :ets.insert(@table, {row.boss_id, :alive})

          "dead" ->
            remaining = row.respawn_time - now

            if remaining > 0 do
              :ets.insert(@table, {row.boss_id, {:respawning, row.respawn_time}})
              # TODO: reschedule respawn timer — requires template access at load time
            else
              :ets.insert(@table, {row.boss_id, :alive})
            end
        end
      end)
    rescue
      e -> Logger.warning("[RaidBossManager] load failed: #{inspect(e)}")
    end
  end

  defp persist_state(boss_id, state_str, respawn_time) do
    try do
      L2E.Repo.insert!(
        %L2E.DB.RaidBossState{boss_id: boss_id, state: state_str, respawn_time: respawn_time},
        on_conflict: {:replace, [:state, :respawn_time, :updated_at]},
        conflict_target: :boss_id
      )
    rescue
      e -> Logger.warning("[RaidBossManager] persist failed: #{inspect(e)}")
    end
  end
end
