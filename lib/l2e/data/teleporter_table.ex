defmodule L2E.Data.TeleporterTable do
  @moduledoc """
  ETS-backed GenServer holding all teleporter NPC destinations.

  Loads `L2J_Mobius_CT_0_Interlude/dist/game/data/teleporters/**/*.xml`.

  Structure per NPC:
    `{npc_id, [%{name, x, y, z, fee_count, fee_id, type}]}`

  `type` is `:normal | :nobles_token | :nobles_adena | :castle | :clan_hall | :dungeon`
  Only `:normal` and `:nobles_adena` teleports charge adena directly.

  Reference: TeleporterData.java
  """

  use GenServer
  require Logger

  import SweetXml

  @table :teleporters

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Returns the list of teleport destinations for an NPC, or nil."
  @spec get(pos_integer()) :: [map()] | nil
  def get(npc_id) do
    case :ets.lookup(@table, npc_id) do
      [{^npc_id, destinations}] -> destinations
      [] -> nil
    end
  end

  @doc "Returns only the NORMAL (adena-fee) teleport list for an NPC."
  @spec get_normal(pos_integer()) :: [map()]
  def get_normal(npc_id) do
    npc_id
    |> get()
    |> Kernel.||([])
    |> Enum.filter(&(&1.type == :normal))
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {npc_count, dest_count} = load_all()

    Logger.info(
      "[TeleporterTable] Loaded #{npc_count} teleporter NPCs (#{dest_count} destinations)"
    )

    {:ok, %{}}
  end

  # -----------------------------------------------------------------------
  # XML loading
  # -----------------------------------------------------------------------

  defp data_dir do
    Path.join([
      File.cwd!(),
      "L2J_Mobius_CT_0_Interlude",
      "dist",
      "game",
      "data",
      "teleporters"
    ])
  end

  defp load_all do
    files = Path.wildcard(Path.join(data_dir(), "**/*.xml"))

    Enum.reduce(files, {0, 0}, fn path, {npcs, dests} ->
      case load_file(path) do
        {:ok, entries} ->
          Enum.reduce(entries, {npcs, dests}, fn {npc_id, destinations}, {n, d} ->
            :ets.insert(@table, {npc_id, destinations})
            {n + 1, d + length(destinations)}
          end)

        {:error, _} ->
          {npcs, dests}
      end
    end)
  end

  defp load_file(path) do
    case File.read(path) do
      {:ok, content} ->
        parse_file(content, path)

      {:error, reason} ->
        Logger.warning("[TeleporterTable] Cannot read #{path}: #{reason}")
        {:error, reason}
    end
  end

  defp parse_file(content, path) do
    try do
      doc = parse(content)

      entries =
        doc
        |> xpath(~x"//npc"l, id: ~x"./@id"i, teleports: ~x"./teleport"l)
        |> Enum.map(fn npc ->
          destinations =
            npc.teleports
            |> Enum.flat_map(fn teleport_node ->
              type_str = teleport_node |> xpath(~x"./@type"s)
              type = parse_type(type_str)

              teleport_node
              |> xpath(
                ~x"./location"l,
                name: ~x"./@name"s,
                x: ~x"./@x"i,
                y: ~x"./@y"i,
                z: ~x"./@z"i,
                fee_count: ~x"./@feeCount"i,
                fee_id: ~x"./@feeId"i
              )
              |> Enum.map(fn loc ->
                %{
                  name: loc.name,
                  x: loc.x,
                  y: loc.y,
                  z: loc.z,
                  # Default 0 = adena when no feeId
                  fee_id: if(loc.fee_id == 0, do: 57, else: loc.fee_id),
                  fee_count: loc.fee_count,
                  type: type
                }
              end)
            end)

          {npc.id, destinations}
        end)
        |> Enum.filter(fn {npc_id, dests} -> npc_id > 0 and dests != [] end)

      {:ok, entries}
    rescue
      e ->
        Logger.warning("[TeleporterTable] Failed to parse #{path}: #{inspect(e)}")
        {:error, :parse_error}
    end
  end

  defp parse_type("NOBLES_TOKEN"), do: :nobles_token
  defp parse_type("NOBLES_ADENA"), do: :nobles_adena
  defp parse_type("CASTLE"), do: :castle
  defp parse_type("CLAN_HALL"), do: :clan_hall
  defp parse_type("DUNGEON"), do: :dungeon
  defp parse_type(_), do: :normal
end
