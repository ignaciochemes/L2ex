defmodule L2E.Item.TemplateTable do
  @moduledoc """
  ETS-backed GenServer holding all item type definitions.
  Loaded from L2J Mobius XML files at startup; all lookups are lock-free concurrent reads.
  """

  use GenServer
  require Logger

  import SweetXml

  alias L2E.Item.Template

  @table :item_templates

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec get(pos_integer()) :: Template.t() | nil
  def get(item_id) do
    case :ets.lookup(@table, item_id) do
      [{^item_id, template}] -> template
      [] -> nil
    end
  end

  @spec all() :: [Template.t()]
  def all do
    :ets.tab2list(@table) |> Enum.map(&elem(&1, 1))
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(_) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    items = load_all()
    Enum.each(items, fn t -> :ets.insert(table, {t.item_id, t}) end)
    Logger.info("[Item.TemplateTable] Loaded #{length(items)} item templates from XML")
    {:ok, %{table: table}}
  end

  # -----------------------------------------------------------------------
  # XML loading
  # -----------------------------------------------------------------------

  defp data_root do
    Path.join([File.cwd!(), "L2J_Mobius_CT_0_Interlude", "dist", "game", "data"])
  end

  defp item_files do
    base = Path.join(data_root(), "stats/items")

    Path.wildcard(Path.join(base, "**/*.xml"))
    |> Enum.reject(&(String.contains?(&1, "/custom/") or String.contains?(&1, "\\custom\\")))
  end

  defp load_all do
    item_files()
    |> Enum.flat_map(&load_file/1)
  end

  defp load_file(path) do
    case File.read(path) do
      {:ok, content} ->
        try do
          content
          |> parse()
          |> xpath(~x"//item"l,
            id: ~x"./@id"i,
            type: ~x"./@type"s,
            name: ~x"./@name"s,
            sets: [
              ~x"./set"l,
              name: ~x"./@name"s,
              val: ~x"./@val"s
            ],
            stats: [
              ~x"./stats/stat"l,
              type: ~x"./@type"s,
              value: ~x"./text()"s
            ]
          )
          |> Enum.map(&build_template/1)
        rescue
          e ->
            Logger.warning("[Item.TemplateTable] Failed to parse #{path}: #{inspect(e)}")
            []
        end

      {:error, reason} ->
        Logger.warning("[Item.TemplateTable] Cannot read #{path}: #{inspect(reason)}")
        []
    end
  end

  defp build_template(%{id: id, type: type_str, name: name, sets: sets, stats: stats}) do
    set_map = Map.new(sets, fn %{name: k, val: v} -> {k, v} end)
    stat_map = Map.new(stats, fn %{type: t, value: v} -> {t, v} end)

    type = parse_type(type_str)
    bodypart_str = Map.get(set_map, "bodypart", "")
    slot = parse_slot(bodypart_str)
    bodypart = slot_to_bodypart(slot)

    {type1, type2} = type_codes(type, bodypart_str)

    weight = parse_int(Map.get(set_map, "weight", "0"))
    price = parse_int(Map.get(set_map, "price", "0"))
    stackable = type == :etc and Map.get(set_map, "is_stackable", "true") != "false"
    is_tradeable = Map.get(set_map, "is_tradable", "true") != "false"

    p_atk = parse_float(Map.get(stat_map, "pAtk", "0")) |> trunc()
    m_atk = parse_float(Map.get(stat_map, "mAtk", "0")) |> trunc()
    p_def = parse_float(Map.get(stat_map, "pDef", "0")) |> trunc()
    m_def = parse_float(Map.get(stat_map, "mDef", "0")) |> trunc()

    %Template{
      item_id: id,
      name: name,
      type: type,
      slot: slot,
      grade: :none,
      stackable: stackable,
      weight: weight,
      is_tradeable: is_tradeable,
      sell_price: div(price, 2),
      type1: type1,
      type2: type2,
      bodypart: bodypart,
      p_atk_bonus: p_atk,
      m_atk_bonus: m_atk,
      p_def_bonus: p_def,
      m_def_bonus: m_def,
      hp_restore: 0,
      mp_restore: 0
    }
  end

  # -----------------------------------------------------------------------
  # Type / slot helpers
  # -----------------------------------------------------------------------

  defp parse_type("Weapon"), do: :weapon
  defp parse_type("Armor"), do: :armor
  defp parse_type(_), do: :etc

  defp parse_slot("rhand"), do: :r_hand
  defp parse_slot("lhand"), do: :l_hand
  defp parse_slot("lrhand"), do: :both_hands
  defp parse_slot("chest"), do: :chest
  defp parse_slot("legs"), do: :legs
  defp parse_slot("head"), do: :head
  defp parse_slot("feet"), do: :feet
  defp parse_slot("gloves"), do: :gloves
  defp parse_slot("back"), do: :back
  defp parse_slot("neck"), do: :neck
  defp parse_slot("lear"), do: :l_ear
  defp parse_slot("rear"), do: :r_ear
  defp parse_slot("lfinger"), do: :l_finger
  defp parse_slot("rfinger"), do: :r_finger
  defp parse_slot(_), do: nil

  # Bodypart bitmask constants (L2 Interlude protocol)
  @bp_none 0x00000000
  @bp_rhand 0x00000080
  @bp_lhand 0x00000100
  @bp_both 0x00008000
  @bp_head 0x00000040
  @bp_chest 0x00000400
  @bp_legs 0x00000800
  @bp_feet 0x00001000
  @bp_gloves 0x00000200

  defp slot_to_bodypart(:r_hand), do: @bp_rhand
  defp slot_to_bodypart(:l_hand), do: @bp_lhand
  defp slot_to_bodypart(:both_hands), do: @bp_both
  defp slot_to_bodypart(:head), do: @bp_head
  defp slot_to_bodypart(:chest), do: @bp_chest
  defp slot_to_bodypart(:legs), do: @bp_legs
  defp slot_to_bodypart(:feet), do: @bp_feet
  defp slot_to_bodypart(:gloves), do: @bp_gloves
  defp slot_to_bodypart(_), do: @bp_none

  # type1 / type2 constants (ItemTemplate.java)
  @t1_weapon 0
  @t1_armor 1
  @t1_etc 4
  @t2_weapon 0
  @t2_armor 1
  @t2_money 4
  @t2_other 5

  defp type_codes(:weapon, _), do: {@t1_weapon, @t2_weapon}
  defp type_codes(:armor, _), do: {@t1_armor, @t2_armor}
  defp type_codes(:etc, ""), do: {@t1_etc, @t2_money}
  defp type_codes(:etc, _), do: {@t1_etc, @t2_other}

  defp parse_int(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_float(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end
end
