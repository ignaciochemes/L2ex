defmodule L2E.Data.HennaTable do
  @moduledoc """
  ETS-backed GenServer holding all Henna (tattoo/dye) templates.

  Players can engrave up to 3 hennas onto a character. Each henna grants
  stat bonuses while engraved and is removed by returning dye items to an NPC.

  Seeded from hardcoded Interlude values at startup.
  Full XML loader (HennaData.java equivalent) is a separate task.

  ETS table: :henna_table
    key: henna_id (integer)
    value: henna map
  """

  use GenServer
  require Logger

  @table :henna_table

  @initial_hennas [
    %{
      henna_id: 1,
      symbol_id: 4270,
      dye_id: 4271,
      dye_count: 10,
      cancel_fee: 5,
      price: 0,
      stat_bonus: %{str: 2, con: -1},
      allowed_classes: [],
      name: "Lion Symbol"
    },
    %{
      henna_id: 2,
      symbol_id: 4270,
      dye_id: 4272,
      dye_count: 10,
      cancel_fee: 5,
      price: 0,
      stat_bonus: %{str: 1, dex: 1, con: -1},
      allowed_classes: [],
      name: "Dragon Symbol"
    },
    %{
      henna_id: 3,
      symbol_id: 4270,
      dye_id: 4273,
      dye_count: 10,
      cancel_fee: 5,
      price: 0,
      stat_bonus: %{con: 2, str: -1},
      allowed_classes: [],
      name: "Ogre Symbol"
    },
    %{
      henna_id: 4,
      symbol_id: 4270,
      dye_id: 4274,
      dye_count: 10,
      cancel_fee: 5,
      price: 0,
      stat_bonus: %{dex: 2, str: -1},
      allowed_classes: [],
      name: "Cat Symbol"
    },
    %{
      henna_id: 5,
      symbol_id: 4270,
      dye_id: 4275,
      dye_count: 10,
      cancel_fee: 5,
      price: 0,
      stat_bonus: %{dex: 1, men: 1, str: -1},
      allowed_classes: [],
      name: "Star Symbol"
    },
    %{
      henna_id: 6,
      symbol_id: 4270,
      dye_id: 4276,
      dye_count: 10,
      cancel_fee: 5,
      price: 0,
      stat_bonus: %{wit: 2, men: -1},
      allowed_classes: [],
      name: "Rabbit Symbol"
    },
    %{
      henna_id: 7,
      symbol_id: 4270,
      dye_id: 4277,
      dye_count: 10,
      cancel_fee: 5,
      price: 0,
      stat_bonus: %{men: 2, wit: -1},
      allowed_classes: [],
      name: "Frog Symbol"
    },
    %{
      henna_id: 8,
      symbol_id: 4270,
      dye_id: 4278,
      dye_count: 10,
      cancel_fee: 5,
      price: 0,
      stat_bonus: %{int: 2, men: -1},
      allowed_classes: [],
      name: "Princess Symbol"
    }
  ]

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Returns the henna map for the given henna_id, or nil."
  @spec get(pos_integer()) :: map() | nil
  def get(henna_id) do
    case :ets.lookup(@table, henna_id) do
      [{^henna_id, henna}] -> henna
      [] -> nil
    end
  end

  @doc "Returns all hennas as a list (for NPC dialog menus)."
  @spec get_all() :: [map()]
  def get_all do
    :ets.tab2list(@table) |> Enum.map(&elem(&1, 1))
  end

  @doc "Returns the henna whose dye_id matches the given item_id, or nil."
  @spec get_dye_for_item(pos_integer()) :: map() | nil
  def get_dye_for_item(item_id) do
    :ets.tab2list(@table)
    |> Enum.find_value(fn {_id, henna} ->
      if henna.dye_id == item_id, do: henna
    end)
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    Enum.each(@initial_hennas, fn henna ->
      :ets.insert(@table, {henna.henna_id, henna})
    end)

    Logger.info("[HennaTable] Loaded #{length(@initial_hennas)} hennas")
    {:ok, %{}}
  end
end
