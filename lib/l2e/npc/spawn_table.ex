defmodule L2E.NPC.SpawnTable do
  @moduledoc """
  GenServer that owns NPC spawn definitions and drives the respawn cycle.

  On startup, loads spawn definitions from L2J Mobius XML files and spawns
  all defined NPCs via NPC.Supervisor. When an NPC dies it sends
  `{:npc_died, object_id, npc_id, spawn_pos, heading}` here.
  SpawnTable schedules a `Process.send_after` for the template's respawn_ms,
  then restarts a fresh NPC.Instance with a new object_id.

  Object IDs are generated as monotonically increasing integers starting at
  100_000 (below this range is reserved for player character IDs from Postgres).
  """

  use GenServer
  require Logger

  import SweetXml

  alias L2E.NPC.{TemplateTable, Supervisor}

  @name __MODULE__

  # Starting offset for NPC object IDs (players use DB integer IDs starting at 1)
  @npc_id_base 100_000

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: @name)

  @doc """
  Admin shortcut: spawn one NPC by id at the given coordinates.
  Returns `{:ok, pid}` or `{:error, reason}`.
  """
  @spec admin_spawn(pos_integer(), integer(), integer(), integer()) ::
          {:ok, pid()} | {:error, term()}
  def admin_spawn(npc_id, x, y, z) do
    GenServer.call(@name, {:admin_spawn, npc_id, x, y, z})
  end

  # -----------------------------------------------------------------------
  # GenServer
  # -----------------------------------------------------------------------

  @impl true
  def init(:ok) do
    state = %{next_id: @npc_id_base}
    Process.send_after(self(), :spawn_all, 500)
    {:ok, state}
  end

  @impl true
  def handle_info(:spawn_all, state) do
    spawn_defs = load_spawn_defs()

    {new_state, count} =
      Enum.reduce(spawn_defs, {state, 0}, fn spawn_def, {s, n} ->
        {new_s, _pid} = do_spawn(s, spawn_def)
        {new_s, n + 1}
      end)

    Logger.info("[SpawnTable] Spawned #{count} NPCs from XML definitions")
    {:noreply, new_state}
  end

  def handle_info({:npc_died, _object_id, npc_id, spawn_pos, heading}, state) do
    case TemplateTable.get(npc_id) do
      nil ->
        Logger.warning("[SpawnTable] Unknown npc_id #{npc_id} for respawn")
        {:noreply, state}

      template ->
        spawn_def =
          {npc_id, elem(spawn_pos, 0), elem(spawn_pos, 1), elem(spawn_pos, 2), heading,
           template.respawn_ms}

        Process.send_after(self(), {:respawn, spawn_def}, template.respawn_ms)

        Logger.debug(
          "[SpawnTable] Scheduled respawn for #{template.name} in #{template.respawn_ms}ms"
        )

        {:noreply, state}
    end
  end

  def handle_info({:respawn, spawn_def}, state) do
    {new_state, _pid} = do_spawn(state, spawn_def)
    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.debug("[SpawnTable] Unexpected: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:admin_spawn, npc_id, x, y, z}, _from, state) do
    {new_state, pid} = do_spawn(state, {npc_id, x, y, z, 0, 0})
    result = if pid, do: {:ok, pid}, else: {:error, :spawn_failed}
    {:reply, result, new_state}
  end

  # -----------------------------------------------------------------------
  # XML loading
  # -----------------------------------------------------------------------

  defp data_root do
    Path.join([File.cwd!(), "L2J_Mobius_CT_0_Interlude", "dist", "game", "data"])
  end

  defp spawn_files do
    base = Path.join(data_root(), "spawns")

    Path.wildcard(Path.join(base, "**/*.xml"))
    |> Enum.reject(&(String.contains?(&1, "/custom/") or String.contains?(&1, "\\custom\\")))
  end

  # Returns a list of {npc_id, x, y, z, heading, respawn_delay_ms}
  defp load_spawn_defs do
    xml_defs = spawn_files() |> Enum.flat_map(&load_file/1)

    if xml_defs == [] do
      Logger.info("[SpawnTable] No XML spawn files found — using hardcoded Talking Island fallback")
      hardcoded_spawn_defs()
    else
      xml_defs
    end
  end

  # Fallback spawn list for Talking Island Village.
  # Used only when no XML spawn files are present in the data directory.
  defp hardcoded_spawn_defs do
    [
      # NPC Village
      {30008, -84318, 243637, -3729, 0,      60_000},
      {30006, -83826, 244043, -3729, 0,      60_000},
      {30059, -82827, 242741, -3729, 0,      60_000},
      {30131, -82943, 243087, -3729, 0,      60_000},
      {30017, -83993, 243445, -3729, 0,      60_000},
      # Monsters
      {20446, -83568, 241898, -3729, 0,      30_000},
      {20446, -84100, 241500, -3729, 0,      30_000},
      {20446, -85000, 242000, -3729, 0,      30_000},
      {20447, -86000, 243000, -3729, 0,      35_000},
      {20447, -86500, 244000, -3729, 0,      35_000},
      {20456, -87000, 244500, -3729, 0,      40_000},
      {20456, -87500, 243500, -3729, 0,      40_000}
    ]
  end

  defp load_file(path) do
    case File.read(path) do
      {:ok, content} ->
        try do
          content
          |> parse()
          |> xpath(
            ~x"//spawn/npc"l,
            id: ~x"./@id"i,
            x: ~x"./@x"s,
            y: ~x"./@y"s,
            z: ~x"./@z"s,
            heading: ~x"./@heading"s,
            respawn_delay: ~x"./@respawnDelay"s
          )
          |> Enum.flat_map(fn row ->
            case {row.x, row.y, row.z} do
              {"", _, _} ->
                []

              {_, "", _} ->
                []

              {_, _, ""} ->
                []

              {x, y, z} ->
                respawn_ms = max(parse_int(row.respawn_delay, 60) * 1_000, 5_000)

                [
                  {row.id, String.to_integer(x), String.to_integer(y), String.to_integer(z),
                   parse_int(row.heading, 0), respawn_ms}
                ]
            end
          end)
        rescue
          e ->
            Logger.warning("[SpawnTable] Failed to parse #{path}: #{inspect(e)}")
            []
        end

      {:error, reason} ->
        Logger.warning("[SpawnTable] Cannot read #{path}: #{inspect(reason)}")
        []
    end
  end

  # -----------------------------------------------------------------------
  # Private
  # -----------------------------------------------------------------------

  defp do_spawn(state, {npc_id, x, y, z, heading, _respawn_ms}) do
    object_id = state.next_id
    template = TemplateTable.get(npc_id)

    if template do
      opts = [
        template: template,
        position: {x, y, z},
        heading: heading,
        object_id: object_id
      ]

      case Supervisor.spawn_npc(opts) do
        {:ok, pid} ->
          Logger.debug(
            "[SpawnTable] Spawned #{template.name} id=#{object_id} pid=#{inspect(pid)}"
          )

          {%{state | next_id: object_id + 1}, pid}

        {:error, reason} ->
          Logger.error("[SpawnTable] Failed to spawn npc_id=#{npc_id}: #{inspect(reason)}")
          {%{state | next_id: object_id + 1}, nil}
      end
    else
      Logger.debug("[SpawnTable] No template for npc_id=#{npc_id}, skipping")
      {%{state | next_id: object_id + 1}, nil}
    end
  end

  defp parse_int("", default), do: default
  defp parse_int(s, _), do: String.to_integer(s)
end
