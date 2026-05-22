defmodule L2E.Data.OptionTable do
  @moduledoc """
  ETS-backed GenServer holding augmentation option templates (Life Stone results).

  When a player uses a Life Stone on a weapon, the server rolls a random option
  from the pool appropriate for that stone's grade. Options can grant stat bonuses,
  active skills, passive skills, or special proc effects.

  Grade → option pool:
    :low     → ids 1–3  (stat bonuses only)
    :mid     → ids 1–5
    :top     → ids 1–7
    :ancient → ids 1–8

  Seeded from hardcoded Interlude values at startup.
  Full XML loader (AugmentationData.java equivalent) is a separate task.

  ETS table: :option_table
    key: option_id (integer)
    value: option map
  """

  use GenServer
  require Logger

  @table :option_table

  @grade_pools %{
    low: 1..3,
    mid: 1..5,
    top: 1..7,
    ancient: 1..8
  }

  @initial_options [
    %{
      option_id: 1,
      type: :stat_bonus,
      skill_id: nil,
      skill_level: 0,
      stat_bonus: %{p_atk: 12},
      description: "P.Atk +12"
    },
    %{
      option_id: 2,
      type: :stat_bonus,
      skill_id: nil,
      skill_level: 0,
      stat_bonus: %{m_atk: 15},
      description: "M.Atk +15"
    },
    %{
      option_id: 3,
      type: :stat_bonus,
      skill_id: nil,
      skill_level: 0,
      stat_bonus: %{p_def: 8},
      description: "P.Def +8"
    },
    %{
      option_id: 4,
      type: :stat_bonus,
      skill_id: nil,
      skill_level: 0,
      stat_bonus: %{run_speed: 5},
      description: "Speed +5"
    },
    %{
      option_id: 5,
      type: :stat_bonus,
      skill_id: nil,
      skill_level: 0,
      stat_bonus: %{hp: 150, mp: 50},
      description: "Max HP +150, MP +50"
    },
    %{
      option_id: 6,
      type: :active_skill,
      skill_id: 1068,
      skill_level: 1,
      stat_bonus: %{},
      description: "Haste"
    },
    %{
      option_id: 7,
      type: :passive_skill,
      skill_id: 1086,
      skill_level: 1,
      stat_bonus: %{},
      description: "Vampiric Rage"
    },
    %{
      option_id: 8,
      type: :special,
      skill_id: nil,
      skill_level: 0,
      stat_bonus: %{},
      description: "Chance: P.Atk -5 to attacker"
    }
  ]

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Returns the option map for the given option_id, or nil."
  @spec get(pos_integer()) :: map() | nil
  def get(option_id) do
    case :ets.lookup(@table, option_id) do
      [{^option_id, option}] -> option
      [] -> nil
    end
  end

  @doc """
  Returns a random option_id appropriate for the given life stone grade.

  Grades: `:low | :mid | :top | :ancient`
  Returns nil if the grade is unknown.
  """
  @spec get_random_option(:low | :mid | :top | :ancient) :: pos_integer() | nil
  def get_random_option(grade) do
    case Map.get(@grade_pools, grade) do
      nil -> nil
      range -> Enum.random(range)
    end
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    Enum.each(@initial_options, fn option ->
      :ets.insert(@table, {option.option_id, option})
    end)

    Logger.info("[OptionTable] Loaded #{length(@initial_options)} augmentation options")
    {:ok, %{}}
  end
end
