defmodule L2E.Data.RecipeTable do
  @moduledoc """
  ETS-backed GenServer holding all crafting recipe templates.

  Two recipe types exist in Lineage II Interlude:
    - Dwarven recipes (`is_common: false`) — only Dwarf subclasses with Create Item
    - Common recipes (`is_common: true`) — any player can craft via Common Craft

  Seeded from hardcoded Interlude values at startup.
  Full XML loader (RecipeData.java equivalent) is a separate task.

  ETS table: :recipe_table
    key: recipe_id (integer)
    value: recipe map
  """

  use GenServer
  require Logger

  @table :recipe_table

  @initial_recipes [
    %{
      recipe_id: 1,
      item_id: 1872,
      count: 5,
      mp_cost: 15,
      success_rate: 100,
      ingredients: [%{item_id: 1869, count: 10}],
      required_skill_level: 1,
      is_common: false,
      name: "Recipe: Iron Ingot"
    },
    %{
      recipe_id: 2,
      item_id: 1880,
      count: 5,
      mp_cost: 15,
      success_rate: 100,
      ingredients: [%{item_id: 1879, count: 3}],
      required_skill_level: 1,
      is_common: false,
      name: "Recipe: Charcoal"
    },
    %{
      recipe_id: 3,
      item_id: 1875,
      count: 1,
      mp_cost: 30,
      success_rate: 80,
      ingredients: [%{item_id: 1880, count: 5}, %{item_id: 1869, count: 2}],
      required_skill_level: 2,
      is_common: false,
      name: "Recipe: Synthetic Cokes"
    },
    %{
      recipe_id: 4,
      item_id: 57,
      count: 1,
      mp_cost: 5,
      success_rate: 100,
      ingredients: [%{item_id: 4042, count: 1}],
      required_skill_level: 1,
      is_common: true,
      name: "Recipe: Silver Nugget"
    },
    %{
      recipe_id: 5,
      item_id: 1884,
      count: 1,
      mp_cost: 25,
      success_rate: 90,
      ingredients: [%{item_id: 1872, count: 5}, %{item_id: 1875, count: 2}],
      required_skill_level: 2,
      is_common: false,
      name: "Recipe: Steel"
    },
    %{
      recipe_id: 6,
      item_id: 1888,
      count: 1,
      mp_cost: 40,
      success_rate: 85,
      ingredients: [%{item_id: 1884, count: 3}, %{item_id: 1875, count: 3}],
      required_skill_level: 3,
      is_common: false,
      name: "Recipe: Mithril Alloy"
    }
  ]

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Returns the recipe map for the given recipe_id, or nil."
  @spec get(pos_integer()) :: map() | nil
  def get(recipe_id) do
    case :ets.lookup(@table, recipe_id) do
      [{^recipe_id, recipe}] -> recipe
      [] -> nil
    end
  end

  @doc "Returns the recipe that produces the given item_id, or nil."
  @spec get_for_item(pos_integer()) :: map() | nil
  def get_for_item(item_id) do
    :ets.tab2list(@table)
    |> Enum.find_value(fn {_id, recipe} ->
      if recipe.item_id == item_id, do: recipe
    end)
  end

  @doc "Returns all common recipes (any player can craft)."
  @spec get_common_recipes() :: [map()]
  def get_common_recipes do
    :ets.tab2list(@table)
    |> Enum.filter(fn {_id, recipe} -> recipe.is_common end)
    |> Enum.map(&elem(&1, 1))
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    Enum.each(@initial_recipes, fn recipe ->
      :ets.insert(@table, {recipe.recipe_id, recipe})
    end)

    Logger.info("[RecipeTable] Loaded #{length(@initial_recipes)} recipes")
    {:ok, %{}}
  end
end
