defmodule L2E.Item.DropResolver do
  @moduledoc """
  Pure module: resolves what items an NPC drops upon death.

  Each entry in a drop table is `{item_id, count_range, chance}` where
  `chance` is a float in [0.0, 1.0].  Returns a list of `{item_id, count}`
  tuples for items that actually drop (chance rolls succeed).
  """

  alias L2E.NPC.Template

  @spec resolve(Template.t()) :: [{pos_integer(), pos_integer()}]
  def resolve(%Template{npc_id: npc_id}) do
    npc_id
    |> drop_table()
    |> Enum.reduce([], fn {item_id, count_range, chance}, acc ->
      if :rand.uniform() <= chance do
        [{item_id, roll(count_range)} | acc]
      else
        acc
      end
    end)
  end

  # ── Drop tables per npc_id ────────────────────────────────────────────
  # Format: {item_id, count_range, drop_chance}

  defp drop_table(1) do
    # Rabbit — very low drops
    [{57, 1..3, 0.90}]
  end

  defp drop_table(2) do
    # Goblin
    [
      {57, 5..20, 1.00},
      # Healing Potion
      {726, 1..2, 0.20},
      # Short Sword
      {35, 1..1, 0.05}
    ]
  end

  defp drop_table(3) do
    # Skeleton
    [
      {57, 20..50, 1.00},
      {726, 1..3, 0.35},
      {35, 1..1, 0.08},
      # Leather Helmet
      {22, 1..1, 0.06}
    ]
  end

  defp drop_table(4) do
    # Wolf
    [
      {57, 10..30, 0.95},
      {726, 1..2, 0.25}
    ]
  end

  defp drop_table(5) do
    # Orc Raider
    [
      {57, 50..100, 1.00},
      {726, 2..4, 0.40},
      # Wooden Shield
      {49, 1..1, 0.06},
      # Sword of Revolution
      {1148, 1..1, 0.02}
    ]
  end

  defp drop_table(_), do: [{57, 1..5, 0.80}]

  defp roll(n..n//1), do: n
  defp roll(first..last//1), do: first + :rand.uniform(last - first + 1) - 1
end
