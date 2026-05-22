defmodule L2E.Data.MultisellTable do
  @moduledoc """
  MultiSell list table. Stores exchange lists used by dimensional merchants,
  grocery NPCs, and recipe shops.

  Each list_id maps to a list of entries:
    %{
      list_id:    integer,
      entries: [
        %{
          entry_id:     integer,
          ingredients:  [{item_id, count}],
          products:     [{item_id, count}]
        }
      ]
    }

  Seeded with a small set of Interlude multisell lists:
  - List 100: Dimensional Merchant (crystal trades)
  - List 200: Blacksmith of Mammon (life stone set)
  """

  use GenServer

  @table __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(_) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    load_defaults()
    {:ok, %{}}
  end

  @doc "Get a multisell list by list_id. Returns nil if not found."
  @spec get(pos_integer()) :: map() | nil
  def get(list_id) do
    case :ets.lookup(@table, list_id) do
      [{^list_id, list}] -> list
      [] -> nil
    end
  end

  @doc "Get all list IDs."
  def all_ids do
    :ets.select(@table, [{{:"$1", :_}, [], [:"$1"]}])
  end

  defp load_defaults do
    lists = [
      %{
        list_id: 100,
        name: "Crystal Exchange",
        entries: [
          # 100x C-grade → 1x B-grade
          %{entry_id: 1, ingredients: [{1459, 100}], products: [{1460, 1}]},
          # 100x B-grade → 1x A-grade
          %{entry_id: 2, ingredients: [{1460, 100}], products: [{1461, 1}]},
          # 100x A-grade → 1x S-grade
          %{entry_id: 3, ingredients: [{1461, 100}], products: [{1462, 1}]}
        ]
      },
      %{
        list_id: 200,
        name: "Blacksmith of Mammon",
        entries: [
          # 200k adena → low-grade life stone
          %{entry_id: 1, ingredients: [{57, 200_000}], products: [{8762, 1}]},
          # 2M adena → mid-grade life stone
          %{entry_id: 2, ingredients: [{57, 2_000_000}], products: [{8763, 1}]}
        ]
      }
    ]

    Enum.each(lists, fn list -> :ets.insert(@table, {list.list_id, list}) end)
  end
end
