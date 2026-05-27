defmodule L2E.Item.SoulCrystal do
  @moduledoc "Soul crystal absorption logic for Interlude."

  # Item IDs for soul crystals Level 0-13 (representative ranges)
  # Red (Fire):   4629 (Lv0) .. 4641 (Lv12)
  # Green (Water):4642 (Lv0) .. 4654 (Lv12)
  # Blue (Wind):  4655 (Lv0) .. 4667 (Lv12)
  @crystal_item_ids_red Enum.to_list(4629..4641)
  @crystal_item_ids_green Enum.to_list(4642..4654)
  @crystal_item_ids_blue Enum.to_list(4655..4667)
  @max_level 13

  @doc "Returns true if the item_id is a soul crystal of any type."
  def soul_crystal?(item_id) do
    item_id in @crystal_item_ids_red or
      item_id in @crystal_item_ids_green or
      item_id in @crystal_item_ids_blue
  end

  @doc "Returns soul type atom from item_id: :red | :green | :blue | :none"
  def soul_type(item_id) do
    cond do
      item_id in @crystal_item_ids_red -> :red
      item_id in @crystal_item_ids_green -> :green
      item_id in @crystal_item_ids_blue -> :blue
      true -> :none
    end
  end

  @doc "Returns current soul level (0-12) from item_id."
  def soul_level(item_id) do
    cond do
      item_id in @crystal_item_ids_red -> item_id - 4629
      item_id in @crystal_item_ids_green -> item_id - 4642
      item_id in @crystal_item_ids_blue -> item_id - 4655
      true -> 0
    end
  end

  @doc """
  Try to absorb a soul from npc_level into the equipped soul crystal.
  Returns {:absorbed, new_level} | {:failed} | {:already_max}
  """
  def try_absorb(crystal_item_id, npc_level) do
    current_level = soul_level(crystal_item_id)

    if current_level >= @max_level do
      {:already_max}
    else
      # Absorption chance: base 10% + 2% per NPC level above 20, capped at 70%
      chance = min(10 + max(0, npc_level - 20) * 2, 70)
      roll = :rand.uniform(100)

      if roll <= chance do
        new_level = current_level + 1
        {:absorbed, new_level}
      else
        {:failed}
      end
    end
  end
end
