defmodule L2E.Data.ArmorSetData do
  @moduledoc """
  Armor set bonus definitions for Lineage II Interlude.

  Keyed by chest piece item_id. When a player equips all items in a set,
  the bonus stats are applied on top of base stats.

  Stat keys match the keys used in L2E.Game.Stats:
    :p_atk, :p_def, :m_atk, :m_def, :max_hp, :max_mp, :accuracy,
    :evasion, :crit_rate, :atk_spd, :cast_spd, :speed
  """

  use GenServer

  @table __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(_) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    load_sets()
    {:ok, %{}}
  end

  @doc "Get set definition by chest piece item_id. Returns nil if not a set chest."
  @spec get(pos_integer()) :: map() | nil
  def get(chest_item_id) do
    case :ets.lookup(@table, chest_item_id) do
      [{^chest_item_id, set}] -> set
      [] -> nil
    end
  end

  @doc "Check if player has a complete set equipped and return bonus stats."
  @spec check_set_bonus(map()) :: map()
  def check_set_bonus(equipped_slots) do
    # equipped_slots: %{slot_id => item_id}
    # slot 10 = chest
    chest_id = Map.get(equipped_slots, 10)

    case get(chest_id) do
      nil ->
        %{}

      set ->
        required = set.required_items

        if Enum.all?(required, fn {slot, item_id} -> Map.get(equipped_slots, slot) == item_id end) do
          set.bonus
        else
          %{}
        end
    end
  end

  # Top Interlude armor sets by chest item_id
  # Sources: L2J Mobius armorsets.xml
  defp load_sets do
    sets = [
      # Dark Crystal Heavy (top B-grade heavy)
      %{
        chest_id: 364,
        name: "Dark Crystal Heavy",
        required_items: %{10 => 364, 7 => 365, 6 => 366, 8 => 367, 9 => 368},
        # chest=364, legs=365, head=366, gloves=367, feet=368
        bonus: %{p_def: 86, max_hp: 445}
      },
      # Dark Crystal Robe (B-grade mage)
      %{
        chest_id: 369,
        name: "Dark Crystal Robe",
        required_items: %{10 => 369, 7 => 370, 6 => 371, 8 => 372, 9 => 373},
        bonus: %{m_def: 60, max_mp: 297}
      },
      # Tallum Heavy (A-grade heavy)
      %{
        chest_id: 404,
        name: "Tallum Heavy",
        required_items: %{10 => 404, 7 => 405, 6 => 406, 8 => 407, 9 => 408},
        bonus: %{p_def: 105, max_hp: 592}
      },
      # Tallum Robe (A-grade mage)
      %{
        chest_id: 409,
        name: "Tallum Robe",
        required_items: %{10 => 409, 7 => 410, 6 => 411, 8 => 412, 9 => 413},
        bonus: %{m_def: 75, max_mp: 385}
      },
      # Dynasty Armor (S80) — heavy
      %{
        chest_id: 14002,
        name: "Dynasty Armor",
        required_items: %{10 => 14002, 7 => 14003, 6 => 14004, 8 => 14005, 9 => 14006},
        bonus: %{p_def: 130, max_hp: 740}
      }
    ]

    Enum.each(sets, fn set ->
      :ets.insert(@table, {set.chest_id, set})
    end)
  end
end
