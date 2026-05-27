defmodule L2E.Data.PetTable do
  @moduledoc """
  ETS-backed combat-stats table for pet templates, keyed by npc_id.

  Complements PetDataTable (which holds food/level/name data).
  This table holds the stats needed at runtime: max_hp, max_mp, p_atk.

  OTP design: single GenServer owns ETS creation; reads are lock-free.
  """

  use GenServer
  require Logger

  @table :pet_table

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Get pet stats template by npc_id. Returns {:ok, map} or :error."
  def get(npc_id) do
    case :ets.lookup(@table, npc_id) do
      [{^npc_id, data}] -> {:ok, data}
      [] -> :error
    end
  end

  @doc "All loaded pet stat templates."
  def get_all do
    :ets.tab2list(@table) |> Enum.map(fn {_, v} -> v end)
  end

  @impl GenServer
  def init(:ok) do
    :ets.new(@table, [:set, :protected, :named_table, read_concurrency: true])
    count = load_pets()
    Logger.info("[PetTable] Loaded #{count} pet stat templates.")
    {:ok, %{}}
  end

  defp load_pets do
    xml_path = Path.join(:code.priv_dir(:l2e), "game/data/xml/pets")

    entries =
      if File.dir?(xml_path) do
        load_from_xml(xml_path)
      else
        []
      end

    entries = if entries == [], do: fallback_pets(), else: entries

    Enum.each(entries, fn pet ->
      :ets.insert(@table, {pet.npc_id, pet})
    end)

    length(entries)
  end

  defp load_from_xml(path) do
    path
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".xml"))
    |> Enum.flat_map(fn file ->
      xml_path = Path.join(path, file)

      try do
        xml_path
        |> File.read!()
        |> SweetXml.stream_tags(:pet)
        |> Enum.map(&parse_pet/1)
      rescue
        _ -> []
      end
    end)
  end

  defp parse_pet({:pet, attrs, _}) do
    %{
      npc_id: parse_int(attrs[:npcId] || attrs[:npc_id] || "0"),
      min_level: parse_int(attrs[:minLevel] || attrs[:min_level] || "1"),
      max_level: parse_int(attrs[:maxLevel] || attrs[:max_level] || "80"),
      max_hp: parse_float(attrs[:hp] || "500"),
      max_mp: parse_float(attrs[:mp] || "200"),
      p_atk: parse_float(attrs[:patk] || "50"),
      food_item_id: parse_int(attrs[:foodItemId] || attrs[:food_item_id] || "2515"),
      hungry_limit: parse_int(attrs[:hungryLimit] || attrs[:hungry_limit] || "10")
    }
  end

  defp fallback_pets do
    [
      # Wolf
      %{
        npc_id: 12077,
        min_level: 1,
        max_level: 55,
        max_hp: 500.0,
        max_mp: 200.0,
        p_atk: 50.0,
        food_item_id: 2515,
        hungry_limit: 10
      },
      # Hatchling of Wind
      %{
        npc_id: 12311,
        min_level: 1,
        max_level: 55,
        max_hp: 350.0,
        max_mp: 250.0,
        p_atk: 35.0,
        food_item_id: 7582,
        hungry_limit: 10
      },
      # Hatchling of Star
      %{
        npc_id: 12312,
        min_level: 1,
        max_level: 55,
        max_hp: 450.0,
        max_mp: 180.0,
        p_atk: 45.0,
        food_item_id: 7582,
        hungry_limit: 10
      },
      # Hatchling of Twilight
      %{
        npc_id: 12313,
        min_level: 1,
        max_level: 55,
        max_hp: 400.0,
        max_mp: 220.0,
        p_atk: 40.0,
        food_item_id: 7582,
        hungry_limit: 10
      },
      # Strider (Wind/Star/Twilight share same base stats here)
      %{
        npc_id: 12526,
        min_level: 55,
        max_level: 80,
        max_hp: 2000.0,
        max_mp: 600.0,
        p_atk: 200.0,
        food_item_id: 6643,
        hungry_limit: 10
      },
      %{
        npc_id: 12527,
        min_level: 55,
        max_level: 80,
        max_hp: 2000.0,
        max_mp: 600.0,
        p_atk: 200.0,
        food_item_id: 6643,
        hungry_limit: 10
      },
      %{
        npc_id: 12528,
        min_level: 55,
        max_level: 80,
        max_hp: 2000.0,
        max_mp: 600.0,
        p_atk: 200.0,
        food_item_id: 6643,
        hungry_limit: 10
      }
    ]
  end

  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(_), do: 0

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> parse_int(val) * 1.0
    end
  end

  defp parse_float(val) when is_float(val), do: val
  defp parse_float(val) when is_integer(val), do: val * 1.0
  defp parse_float(_), do: 0.0
end
