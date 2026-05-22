defmodule L2E.Data.ClassAdvancementTable do
  @moduledoc """
  ETS-backed table of class advancement transitions for Lineage II Interlude.

  Maps class_id => list of %{target_class_id, min_level, name}.
  Covers Human classes for MVP.

  API:
  - get_transitions/1  — returns available transitions for a class
  - can_advance?/3     — checks if a class change is valid given current level
  """

  use GenServer
  require Logger

  @table :class_advancements

  # Human class transition data for MVP
  @transitions %{
    # Human Fighter → first class (Lv 20+)
    0 => [
      %{target_class_id: 1, min_level: 20, name: "Warrior"},
      %{target_class_id: 2, min_level: 20, name: "Rogue"},
      %{target_class_id: 4, min_level: 20, name: "Knight"}
    ],
    # Warrior → second class (Lv 40+)
    1 => [
      %{target_class_id: 28, min_level: 40, name: "Warlord"},
      %{target_class_id: 29, min_level: 40, name: "Gladiator"}
    ],
    # Rogue → second class (Lv 40+)
    2 => [
      %{target_class_id: 38, min_level: 40, name: "Treasure Hunter"}
    ],
    # Knight → second class (Lv 40+)
    4 => [
      %{target_class_id: 12, min_level: 40, name: "Paladin"},
      %{target_class_id: 13, min_level: 40, name: "Dark Avenger"}
    ],
    # Human Mage → first class (Lv 20+)
    10 => [
      %{target_class_id: 20, min_level: 20, name: "Sorcerer"},
      %{target_class_id: 21, min_level: 20, name: "Necromancer"}
    ],
    # Sorcerer → second class (Lv 40+)
    20 => [
      %{target_class_id: 87, min_level: 40, name: "Archmage"}
    ]
  }

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Returns the list of advancement transitions available for `class_id`."
  @spec get_transitions(integer()) :: [map()]
  def get_transitions(class_id) do
    case :ets.lookup(@table, class_id) do
      [{^class_id, transitions}] -> transitions
      [] -> []
    end
  end

  @doc """
  Returns true if `class_id` can advance to `target_class_id` at `current_level`.
  """
  @spec can_advance?(integer(), integer(), integer()) :: boolean()
  def can_advance?(class_id, target_class_id, current_level) do
    get_transitions(class_id)
    |> Enum.any?(fn t ->
      t.target_class_id == target_class_id and current_level >= t.min_level
    end)
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(:ok) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    Enum.each(@transitions, fn {class_id, transitions} ->
      :ets.insert(table, {class_id, transitions})
    end)

    Logger.info(
      "[ClassAdvancementTable] Loaded #{map_size(@transitions)} class transition entries"
    )

    {:ok, %{table: table}}
  end
end
