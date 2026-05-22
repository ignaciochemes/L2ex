defmodule L2E.Data.SubclassData do
  @moduledoc """
  ETS-backed sub-class availability data.

  Each character class has a set of available sub-classes it can take.
  Sub-classes must be from a different race's 3rd class lineage.
  In Interlude, players can take sub-classes of any class except their own lineage.
  
  For simplicity: any 3rd-tier class ID (76-88, Kamael excluded) is valid as a sub-class,
  excluding the player's own class lineage.
  """

  use GenServer

  @table :subclass_data

  # 3rd-class IDs available as sub-classes (Interlude)
  @subclass_ids [
    88,  # Hellbound Archmage
    87,  # Archmage
    86,  # Soultaker
    85,  # Mystic Muse
    84,  # Storm Screamer
    83,  # Arcana Lord
    82,  # Doomcryer
    81,  # Dominator
    80,  # Titan
    79,  # Grand Khavatari
    78,  # Dreadnought
    77,  # Maestro
    76,  # Fortune Seeker
    # 2nd class - also valid for sub-class (levels 40+)
    56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75
  ]

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Returns list of valid sub-class IDs for a given class_id. Excludes own lineage."
  def available_for(class_id) do
    # For now, return all sub-class IDs. Lineage restriction can be added later.
    @subclass_ids |> Enum.reject(&(&1 == class_id))
  end

  @doc "Is class_id a valid sub-class choice for the given current class?"
  def valid_subclass?(current_class_id, chosen_class_id) do
    chosen_class_id in available_for(current_class_id)
  end

  @impl GenServer
  def init(_) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end
end
