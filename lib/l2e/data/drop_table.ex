defmodule L2E.Data.DropTable do
  @moduledoc """
  ETS-backed GenServer that parses NPC XML drop tables on startup.

  Drop structure per NPC:
    npc_id => [%{chance: float, items: [%{item_id, min, max, chance}]}]

  Each "group" has a chance to fire (0..100). When it fires, exactly one item
  is selected by weighted pick from the group's items (chances sum to 100).
  """
  use GenServer
  require Logger
  import SweetXml, only: [sigil_x: 2]

  @table :npc_drop_table
  @npcs_dir "L2J_Mobius_CT_0_Interlude/dist/game/data/stats/npcs"

  # ── Public API ────────────────────────────────────────────────────────────

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Roll drops for the given NPC id. Returns [{item_id, count}]."
  @spec resolve(pos_integer()) :: [{pos_integer(), pos_integer()}]
  def resolve(npc_id) do
    groups = :ets.lookup_element(@table, npc_id, 2)
    Enum.flat_map(groups, &maybe_drop_group/1)
  rescue
    ArgumentError -> []
  end

  # ── GenServer ─────────────────────────────────────────────────────────────

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    load_all()
    {:ok, :loaded}
  end

  # ── Loading ───────────────────────────────────────────────────────────────

  defp load_all do
    base = Path.join(:code.priv_dir(:l2e) |> to_string() |> Path.dirname(), @npcs_dir)

    case File.ls(base) do
      {:ok, entries} ->
        Enum.each(entries, fn entry ->
          full = Path.join(base, entry)

          if File.regular?(full) and String.ends_with?(entry, ".xml") do
            load_file(full)
          else
            :skip
          end
        end)

      {:error, reason} ->
        Logger.warning("[DropTable] Could not list #{base}: #{inspect(reason)}")
    end
  end

  defp load_file(path) do
    case File.read(path) do
      {:ok, xml} ->
        parse_npcs(xml)

      {:error, reason} ->
        Logger.warning("[DropTable] Could not read #{path}: #{inspect(reason)}")
    end
  end

  defp parse_npcs(xml) do
    doc = SweetXml.parse(xml, quiet: true)

    npc_ids =
      SweetXml.xpath(doc, ~x"//npc/@id"l)
      |> Enum.map(&List.to_integer/1)

    Enum.each(npc_ids, fn npc_id ->
      groups = extract_groups(doc, npc_id)

      unless groups == [] do
        :ets.insert(@table, {npc_id, groups})
      end
    end)
  end

  defp extract_groups(doc, npc_id) do
    SweetXml.xpath(
      doc,
      ~x"//npc[@id=#{npc_id}]/dropLists/drop/group"l,
      chance: ~x"./@chance"s,
      items: [
        ~x"./item"l,
        item_id: ~x"./@id"i,
        min: ~x"./@min"i,
        max: ~x"./@max"i,
        chance: ~x"./@chance"s
      ]
    )
    |> Enum.map(fn g ->
      %{
        chance: parse_float(g.chance),
        items:
          Enum.map(g.items, fn i ->
            %{item_id: i.item_id, min: i.min, max: i.max, chance: parse_float(i.chance)}
          end)
      }
    end)
  end

  # ── Drop resolution helpers ────────────────────────────────────────────────

  defp maybe_drop_group(%{chance: group_chance, items: items}) do
    if :rand.uniform() * 100 <= group_chance do
      case pick_item(items) do
        nil -> []
        {item_id, count} -> [{item_id, count}]
      end
    else
      []
    end
  end

  # Weighted pick: item chances within a group sum to 100
  defp pick_item([]), do: nil

  defp pick_item(items) do
    roll = :rand.uniform() * 100.0
    do_pick(items, roll, 0.0)
  end

  defp do_pick([], _roll, _acc), do: nil

  defp do_pick([item | rest], roll, acc) do
    new_acc = acc + item.chance

    if roll <= new_acc do
      count = item.min + :rand.uniform(max(1, item.max - item.min + 1)) - 1
      {item.item_id, count}
    else
      do_pick(rest, roll, new_acc)
    end
  end

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_float(f) when is_float(f), do: f
  defp parse_float(i) when is_integer(i), do: i * 1.0
end
