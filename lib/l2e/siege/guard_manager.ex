defmodule L2E.Siege.GuardManager do
  @moduledoc """
  Spawns and despawns siege guard NPCs for active castle sieges.
  Guards defend the castle from a fixed position list per castle.

  Backed by an ETS table (:siege_guard_pids) that maps castle_id → [pid].
  Started as a worker under L2E.Siege.Supervisor.
  """

  use GenServer
  require Logger

  @table :siege_guard_pids

  # Guard NPC IDs follow L2J convention: 35006 + castle_id (approximate)
  @guard_npc_base 35_006

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Spawn guards for a castle when its siege goes active."
  @spec spawn_guards(pos_integer()) :: :ok
  def spawn_guards(castle_id) do
    GenServer.call(__MODULE__, {:spawn_guards, castle_id})
  end

  @doc "Despawn all guards for a castle when siege ends."
  @spec despawn_guards(pos_integer()) :: :ok
  def despawn_guards(castle_id) do
    GenServer.call(__MODULE__, {:despawn_guards, castle_id})
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl GenServer
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:spawn_guards, castle_id}, _from, state) do
    npc_id = @guard_npc_base + castle_id

    pids =
      castle_id
      |> guard_positions()
      |> Enum.flat_map(fn {x, y, z, _heading} ->
        case L2E.NPC.SpawnTable.admin_spawn(npc_id, x, y, z) do
          {:ok, pid} -> [pid]
          _ -> []
        end
      end)

    :ets.insert(@table, {castle_id, pids})
    Logger.info("[SiegeGuardManager] Spawned #{length(pids)} guards for castle #{castle_id}")
    {:reply, :ok, state}
  end

  def handle_call({:despawn_guards, castle_id}, _from, state) do
    case :ets.lookup(@table, castle_id) do
      [{_, pids}] ->
        Enum.each(pids, fn pid ->
          if Process.alive?(pid), do: GenServer.stop(pid, :normal)
        end)

        :ets.delete(@table, castle_id)
        Logger.info("[SiegeGuardManager] Despawned guards for castle #{castle_id}")

      [] ->
        :ok
    end

    {:reply, :ok, state}
  end

  # -----------------------------------------------------------------------
  # Private — guard positions per castle
  # -----------------------------------------------------------------------

  # 4 guards near the castle main entrance.
  # In a full implementation these would come from a data table (XML/DB).
  # Each castle has a small x-offset to avoid stacking across castle zones.
  defp guard_positions(castle_id) do
    offset_x = (castle_id - 1) * 1000

    [
      {149_344 + offset_x, 46_723, -2200, 0},
      {149_644 + offset_x, 46_723, -2200, 0},
      {149_344 + offset_x, 47_023, -2200, 16_384},
      {149_644 + offset_x, 47_023, -2200, 16_384}
    ]
  end
end
