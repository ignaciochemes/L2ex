defmodule L2E.Zone.ZoneTable do
  @moduledoc """
  ETS-backed GenServer that loads all zone definitions from XML.

  Zones are stored in two ETS tables:
    - `:zone_by_id`   — keyed by auto-assigned integer id → Zone.t()
    - `:zone_by_name` — keyed by name string → Zone.t()

  ## Queries
    - `get_zones_at(x, y, z)` — returns all zones that contain the given point
    - `zone_type_at(x, y, z)` — returns the most restrictive zone type at a point:
        :peace > :no_pvp > :siege > :pvp > :other (or :normal if no zone matches)

  ## Data source
  All XML files under `L2J_Mobius_CT_0_Interlude/dist/game/data/zones/`
  are loaded. Only files with `enabled="true"` on the root `<list>` element
  are processed.
  """

  use GenServer
  require Logger

  import SweetXml

  @table :zone_by_id
  @name_table :zone_by_name

  @zone_dir "L2J_Mobius_CT_0_Interlude/dist/game/data/zones"

  # Zone types in priority order for conflict resolution (most restrictive first)
  @priority [:peace, :no_pvp, :siege, :boss, :pvp, :damage, :swamp, :water, :other]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Returns all Zone.t() structs that contain point {x, y, z}."
  @spec get_zones_at(integer(), integer(), integer()) :: [L2E.Zone.t()]
  def get_zones_at(x, y, z) do
    :ets.foldl(
      fn {_id, zone}, acc ->
        if L2E.Zone.contains?(zone, x, y, z), do: [zone | acc], else: acc
      end,
      [],
      @table
    )
  end

  @doc """
  Returns the most gameplay-relevant zone type at the given coordinates.

  Priority: :peace > :no_pvp > :siege > :pvp > :other.
  Returns :normal if no zones cover the point.
  """
  @spec zone_type_at(integer(), integer(), integer()) :: L2E.Zone.zone_type() | :normal
  def zone_type_at(x, y, z) do
    zones = get_zones_at(x, y, z)

    case zones do
      [] ->
        :normal

      _ ->
        types = MapSet.new(zones, & &1.type)

        Enum.find(@priority, :other, fn t -> MapSet.member?(types, t) end)
    end
  end

  @doc "Returns the Zone.t() by name, or nil."
  @spec get_by_name(String.t()) :: L2E.Zone.t() | nil
  def get_by_name(name) do
    case :ets.lookup(@name_table, name) do
      [{_, zone}] -> zone
      [] -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    :ets.new(@name_table, [:set, :public, :named_table, read_concurrency: true])
    count = load_all()
    Logger.info("[ZoneTable] Loaded #{count} zones from #{@zone_dir}")
    {:ok, %{count: count}}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp load_all do
    case File.ls(@zone_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".xml"))
        |> Enum.reject(&(&1 == "documentation.txt" or &1 == "dummy.xml"))
        |> Enum.reduce(0, fn file, acc ->
          acc + load_file(Path.join(@zone_dir, file))
        end)

      {:error, reason} ->
        Logger.warning("[ZoneTable] Cannot list #{@zone_dir}: #{inspect(reason)}")
        0
    end
  end

  defp load_file(path) do
    with {:ok, xml} <- File.read(path),
         "true" <- parse_enabled(xml) do
      zones = parse_zones(xml)
      Enum.each(zones, &insert_zone/1)
      length(zones)
    else
      _ -> 0
    end
  end

  defp parse_enabled(xml) do
    xpath(xml, ~x"/list/@enabled"s)
  end

  defp parse_zones(xml) do
    xpath(xml, ~x"//zone"l,
      name: ~x"./@name"s,
      type: ~x"./@type"s,
      min_z: ~x"./@minZ"i,
      max_z: ~x"./@maxZ"i,
      nodes: [
        ~x"./node"l,
        x: ~x"./@X"i,
        y: ~x"./@Y"i
      ]
    )
    |> Enum.map(&to_zone/1)
    |> Enum.reject(&is_nil/1)
  end

  defp to_zone(%{name: name, type: type_str, min_z: min_z, max_z: max_z, nodes: raw_nodes})
       when is_list(raw_nodes) and length(raw_nodes) >= 3 do
    nodes = Enum.map(raw_nodes, fn %{x: x, y: y} -> {x, y} end)

    %L2E.Zone{
      name: name,
      type: L2E.Zone.classify_type(type_str),
      nodes: nodes,
      min_z: min_z,
      max_z: max_z
    }
  end

  defp to_zone(_), do: nil

  defp insert_zone(zone) do
    id = :erlang.unique_integer([:positive])
    :ets.insert(@table, {id, zone})
    :ets.insert(@name_table, {zone.name, zone})
  end
end
