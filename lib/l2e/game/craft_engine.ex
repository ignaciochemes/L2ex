defmodule L2E.Game.CraftEngine do
  @moduledoc """
  M123: Crafting logic for manufacturing (recipe shop).

  Pure functional module — no GenServer, no state.

  Provides:
    - Success rate calculation (crafter level vs recipe level)
    - Ingredient validation (check if player has all required items)

  The actual craft attempt (ingredient deduction + item creation) is performed in
  PlayerSession which has direct access to Inventory.

  Recipe fields (from L2E.Data.RecipeTable):
    recipe_id, item_id (product), count (product count), mp_cost, success_rate
    (override), ingredients ([%{item_id, count}]), required_skill_level, is_common, name
  """

  @doc """
  Calculates craft success probability (0–100).

  Formula: base 50% + (crafter_level - recipe_level) * 5, clamped to [10, 90].
  An optional skill_bonus (e.g. +10 for Master Craft passive) is added before clamping.
  """
  @spec success_rate(non_neg_integer(), non_neg_integer(), integer()) :: 1..100
  def success_rate(crafter_level, recipe_level, skill_bonus \\ 0) do
    base = 50 + (crafter_level - recipe_level) * 5 + skill_bonus
    min(90, max(10, base))
  end

  @doc """
  Rolls a craft attempt. Returns `:success` or `:fail`.
  `rate` is an integer in [1, 100].
  """
  @spec attempt(1..100) :: :success | :fail
  def attempt(rate) do
    if :rand.uniform(100) <= rate, do: :success, else: :fail
  end

  @doc """
  Validates that the player's inventory contains all required ingredients.

  `ingredients` — list of `{item_id, required_count}` tuples (or maps with :item_id/:count).
  `items`       — output of `L2E.Inventory.get_items/1`:
                  `[{%L2E.Item.Instance{}, %L2E.Item.Template{}}]`

  Returns `:ok` or `{:error, :missing_ingredients}`.
  """
  @spec check_ingredients(
          [{pos_integer(), pos_integer()}] | [%{item_id: pos_integer(), count: pos_integer()}],
          [{struct(), struct()}]
        ) :: :ok | {:error, :missing_ingredients}
  def check_ingredients(ingredients, items) do
    inventory_counts =
      Enum.reduce(items, %{}, fn {inst, tmpl}, acc ->
        item_id = Map.get(tmpl, :item_id) || Map.get(tmpl, :id, 0)
        Map.update(acc, item_id, inst.count, &(&1 + inst.count))
      end)

    all_present =
      Enum.all?(ingredients, fn ingredient ->
        {item_id, required_count} = normalize_ingredient(ingredient)
        Map.get(inventory_counts, item_id, 0) >= required_count
      end)

    if all_present, do: :ok, else: {:error, :missing_ingredients}
  end

  # Accepts both {id, count} tuples and %{item_id: id, count: n} maps.
  defp normalize_ingredient({item_id, count}), do: {item_id, count}
  defp normalize_ingredient(%{item_id: item_id, count: count}), do: {item_id, count}
end
