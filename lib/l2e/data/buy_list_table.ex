defmodule L2E.Data.BuyListTable do
  @moduledoc """
  ETS-backed GenServer holding all merchant buy-list definitions.

  Loaded from `L2J_Mobius_CT_0_Interlude/dist/game/data/buylists/*.xml`
  at startup. Provides two lookup strategies:

    - `get_by_id(buylist_id)` — by the numeric file ID (filename without ext)
    - `get_by_npc(npc_id)`   — by the NPC ID declared in `<npcs>` section

  Each buy list is a list of item maps:
    `[%{item_id: integer, price: integer, count: integer, restock_delay: integer}]`

  Reference: BuyListData.java, BuyListHolder.java
  """

  use GenServer
  require Logger

  import SweetXml

  # ETS table: {buylist_id, [item_map]} — integer key
  @table :buy_lists
  # ETS table: {npc_id, buylist_id} — maps NPC → its buylist
  @npc_table :buy_list_by_npc

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Returns the item list for the given buylist ID, or nil."
  @spec get_by_id(pos_integer()) :: [map()] | nil
  def get_by_id(buylist_id) do
    case :ets.lookup(@table, buylist_id) do
      [{^buylist_id, items}] -> items
      [] -> nil
    end
  end

  @doc "Returns the item list for the NPC's merchant buylist, or nil."
  @spec get_by_npc(pos_integer()) :: [map()] | nil
  def get_by_npc(npc_id) do
    case :ets.lookup(@npc_table, npc_id) do
      [{^npc_id, buylist_id}] -> get_by_id(buylist_id)
      [] -> nil
    end
  end

  @doc "Returns all loaded buylist IDs."
  @spec all_ids() :: [pos_integer()]
  def all_ids do
    :ets.tab2list(@table) |> Enum.map(&elem(&1, 0))
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@npc_table, [:named_table, :set, :public, read_concurrency: true])

    {total_lists, total_items, npc_mappings} = load_all()

    Logger.info(
      "[BuyListTable] Loaded #{total_lists} buy lists (#{total_items} items, #{npc_mappings} NPC mappings)"
    )

    {:ok, %{}}
  end

  # -----------------------------------------------------------------------
  # XML loading
  # -----------------------------------------------------------------------

  defp data_dir do
    Path.join([File.cwd!(), "L2J_Mobius_CT_0_Interlude", "dist", "game", "data", "buylists"])
  end

  defp load_all do
    files = Path.wildcard(Path.join(data_dir(), "*.xml"))

    Enum.reduce(files, {0, 0, 0}, fn path, {lists, items, npcs} ->
      case load_file(path) do
        {:ok, buylist_id, item_list, npc_ids} ->
          :ets.insert(@table, {buylist_id, item_list})

          npc_count =
            Enum.reduce(npc_ids, 0, fn npc_id, acc ->
              :ets.insert(@npc_table, {npc_id, buylist_id})
              acc + 1
            end)

          {lists + 1, items + length(item_list), npcs + npc_count}

        {:error, _reason} ->
          {lists, items, npcs}
      end
    end)
  end

  defp load_file(path) do
    basename = Path.basename(path, ".xml")

    case Integer.parse(basename) do
      {buylist_id, ""} ->
        case File.read(path) do
          {:ok, content} ->
            parse_buylist(buylist_id, content, path)

          {:error, reason} ->
            Logger.warning("[BuyListTable] Failed to read #{path}: #{reason}")
            {:error, reason}
        end

      _ ->
        {:error, :invalid_filename}
    end
  end

  defp parse_buylist(buylist_id, content, path) do
    try do
      doc = parse(content)

      npc_ids =
        doc
        |> xpath(~x"//npcs/npc"l)
        |> Enum.flat_map(fn node ->
          text = node |> xpath(~x"./text()"s) |> String.trim()

          case Integer.parse(text) do
            {npc_id, _} -> [npc_id]
            :error -> []
          end
        end)

      items =
        doc
        |> xpath(
          ~x"//item"l,
          item_id: ~x"./@id"s,
          price: ~x"./@price"s,
          count: ~x"./@count"s,
          restock_delay: ~x"./@restock_delay"s
        )
        |> Enum.map(fn raw ->
          item_id = parse_attr_int(raw.item_id, 0)
          price = parse_attr_int(raw.price, 0)
          count = parse_attr_int(raw.count, 0)
          restock_delay = parse_attr_int(raw.restock_delay, 0)

          %{
            item_id: item_id,
            price: max(0, price),
            # 0 or missing → -1 (unlimited)
            count: if(count == 0, do: -1, else: count),
            restock_delay: restock_delay
          }
        end)
        |> Enum.filter(&(&1.item_id > 0))

      {:ok, buylist_id, items, npc_ids}
    rescue
      e ->
        Logger.warning("[BuyListTable] Failed to parse #{path}: #{inspect(e)}")
        {:error, :parse_error}
    end
  end

  defp parse_attr_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {val, _} -> val
      :error -> default
    end
  end

  defp parse_attr_int(_, default), do: default
end
