defmodule L2E.Data.PetDataTable do
  @moduledoc """
  ETS-backed registry of pet templates, keyed by npc_id.

  Behavioral reference: PetDataTable.java (Java) — structure ONLY.
  Data covers main Interlude pets: Wolf, Hatchlings, Striders, Fenrir, Great Wolf.

  OTP design: single GenServer owns the ETS table creation; reads are lock-free via ETS.
  """

  use GenServer
  require Logger

  @table :pet_data

  # Control item ID → npc_id mapping for summon lookup.
  # Striders and Fenrir/Great Wolf reuse collar IDs shared with hatchlings/wolf.
  @control_item_map %{
    2375 => 12077,
    3500 => 12311,
    3501 => 12312,
    3502 => 12313
  }

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Get pet template by npc_id. Returns {:ok, template} or {:error, :not_found}."
  def get(npc_id) do
    case :ets.lookup(@table, npc_id) do
      [{^npc_id, template}] -> {:ok, template}
      [] -> {:error, :not_found}
    end
  end

  @doc "Get pet template by control item id (summon collar). Returns {:ok, template} or {:error, :not_found}."
  def get_by_item(item_id) do
    case Map.get(@control_item_map, item_id) do
      nil -> {:error, :not_found}
      npc_id -> get(npc_id)
    end
  end

  @impl GenServer
  def init(:ok) do
    :ets.new(@table, [:set, :protected, :named_table, read_concurrency: true])
    count = load_templates()
    Logger.info("[PetDataTable] Loaded #{count} pet templates.")
    {:ok, %{}}
  end

  defp load_templates do
    templates = [
      %{
        npc_id: 12077,
        name: "Wolf",
        min_level: 1,
        max_level: 55,
        max_level_exp: 3_375_000,
        food_item_id: 2515,
        control_item_id: 2375,
        hungry_limit: 50,
        unsatisfied_limit: 30
      },
      %{
        npc_id: 12311,
        name: "Hatchling of Wind",
        min_level: 35,
        max_level: 55,
        max_level_exp: 3_375_000,
        food_item_id: 6316,
        control_item_id: 3500,
        hungry_limit: 55,
        unsatisfied_limit: 35
      },
      %{
        npc_id: 12312,
        name: "Hatchling of Star",
        min_level: 35,
        max_level: 55,
        max_level_exp: 3_375_000,
        food_item_id: 6317,
        control_item_id: 3501,
        hungry_limit: 55,
        unsatisfied_limit: 35
      },
      %{
        npc_id: 12313,
        name: "Hatchling of Twilight",
        min_level: 35,
        max_level: 55,
        max_level_exp: 3_375_000,
        food_item_id: 6318,
        control_item_id: 3502,
        hungry_limit: 55,
        unsatisfied_limit: 35
      },
      %{
        npc_id: 12526,
        name: "Strider of Wind",
        min_level: 55,
        max_level: 80,
        max_level_exp: 157_500_000,
        food_item_id: 6316,
        control_item_id: nil,
        hungry_limit: 60,
        unsatisfied_limit: 40
      },
      %{
        npc_id: 12527,
        name: "Strider of Star",
        min_level: 55,
        max_level: 80,
        max_level_exp: 157_500_000,
        food_item_id: 6317,
        control_item_id: nil,
        hungry_limit: 60,
        unsatisfied_limit: 40
      },
      %{
        npc_id: 12528,
        name: "Strider of Twilight",
        min_level: 55,
        max_level: 80,
        max_level_exp: 157_500_000,
        food_item_id: 6318,
        control_item_id: nil,
        hungry_limit: 60,
        unsatisfied_limit: 40
      },
      %{
        npc_id: 16014,
        name: "Fenrir Wolf",
        min_level: 1,
        max_level: 70,
        max_level_exp: 30_375_000,
        food_item_id: 6316,
        control_item_id: nil,
        hungry_limit: 50,
        unsatisfied_limit: 30
      },
      %{
        npc_id: 16025,
        name: "Great Wolf",
        min_level: 1,
        max_level: 70,
        max_level_exp: 30_375_000,
        food_item_id: 2515,
        control_item_id: nil,
        hungry_limit: 50,
        unsatisfied_limit: 30
      }
    ]

    Enum.each(templates, fn t -> :ets.insert(@table, {t.npc_id, t}) end)
    length(templates)
  end
end
