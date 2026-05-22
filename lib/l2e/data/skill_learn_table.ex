defmodule L2E.Data.SkillLearnTable do
  @moduledoc """
  ETS-backed skill learn data.

  Stores what skills each class can learn, at what level,
  and for how much SP. Keyed by {class_id, skill_id, skill_level}.

  Seeded from @initial_skill_learns on startup.
  Full XML loader (SkillTreeData.java equivalent) is a separate task.
  """

  use GenServer
  require Logger

  @table :skill_learns

  # {class_id, skill_id, skill_level, sp_cost, min_level}
  # class_id 0 = Human Fighter, class_id 1 = Human Mage
  @initial_skill_learns [
    # ─── Human Fighter (class_id 0) ─────────────────────────────────────
    # Power Strike Lv1
    {0, 42, 1, 1500, 4},
    # Power Strike Lv2
    {0, 42, 2, 3500, 8},
    # Power Strike Lv3
    {0, 42, 3, 6000, 12},
    # Mortal Blow Lv1
    {0, 46, 1, 2500, 6},
    # Mortal Blow Lv2
    {0, 46, 2, 5500, 12},
    # Mortal Blow Lv3
    {0, 46, 3, 9500, 18},
    # Sweep Lv1
    {0, 51, 1, 3500, 8},
    # Sweep Lv2
    {0, 51, 2, 7000, 14},
    # Pumping Lv1
    {0, 57, 1, 1200, 3},
    # Pumping Lv2
    {0, 57, 2, 3600, 9},
    # Pumping Lv3
    {0, 57, 3, 7200, 15},
    # Shield Defense Lv1
    {0, 67, 1, 1800, 4},
    # Shield Defense Lv2
    {0, 67, 2, 4500, 10},
    # Shield Defense Lv3
    {0, 67, 3, 8500, 16},
    # Blunt Mastery Lv1
    {0, 263, 1, 900, 2},
    # Blunt Mastery Lv2
    {0, 263, 2, 2700, 6},
    # Blunt Mastery Lv3
    {0, 263, 3, 4500, 10},
    # Blunt Mastery Lv4
    {0, 263, 4, 7200, 14},
    # Sword Mastery Lv1
    {0, 264, 1, 900, 2},
    # Sword Mastery Lv2
    {0, 264, 2, 2700, 6},
    # Sword Mastery Lv3
    {0, 264, 3, 4500, 10},
    # Sword Mastery Lv4
    {0, 264, 4, 7200, 14},
    # Heavy Armor Mastery Lv1
    {0, 265, 1, 900, 2},
    # Heavy Armor Mastery Lv2
    {0, 265, 2, 2700, 6},
    # Heavy Armor Mastery Lv3
    {0, 265, 3, 4500, 10},
    # Heavy Armor Mastery Lv4
    {0, 265, 4, 7200, 14},

    # ─── Human Mage (class_id 1) ─────────────────────────────────────────
    # Wind Strike Lv2
    {1, 3, 2, 1400, 4},
    # Wind Strike Lv3
    {1, 3, 3, 3000, 8},
    # Wind Strike Lv4
    {1, 3, 4, 5200, 12},
    # Blaze Lv1
    {1, 8, 1, 900, 3},
    # Blaze Lv2
    {1, 8, 2, 2400, 7},
    # Blaze Lv3
    {1, 8, 3, 4800, 11},
    # Blaze Lv4
    {1, 8, 4, 8500, 16},
    # Might Lv2
    {1, 68, 2, 3500, 8},
    # Might Lv3
    {1, 68, 3, 6500, 14},
    # Shield Lv1
    {1, 69, 1, 1800, 5},
    # Shield Lv2
    {1, 69, 2, 4000, 10},
    # Shield Lv3
    {1, 69, 3, 7000, 16},
    # Empower Lv1
    {1, 166, 1, 2800, 6},
    # Empower Lv2
    {1, 166, 2, 5500, 12},
    # Empower Lv3
    {1, 166, 3, 9500, 18},
    # Acumen Lv1
    {1, 167, 1, 2400, 5},
    # Acumen Lv2
    {1, 167, 2, 4800, 11},
    # Acumen Lv3
    {1, 167, 3, 8500, 17}
  ]

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Returns all skills for `class_id` that meet `character_level` requirement,
  enriched with skill_id, skill_level, sp_cost, and min_level.
  """
  @spec get_learnable_skills(integer(), integer()) :: [map()]
  def get_learnable_skills(class_id, character_level) do
    :ets.match_object(@table, {{class_id, :_, :_}, :_})
    |> Enum.filter(fn {_key, info} -> info.min_level <= character_level end)
    |> Enum.map(fn {_key, info} -> info end)
  end

  @doc """
  Returns %{sp_cost: int, min_level: int, skill_id: int, skill_level: int}
  for the given class/skill/level, or nil if not learnable.
  """
  @spec get_skill_info(integer(), integer(), integer()) :: map() | nil
  def get_skill_info(class_id, skill_id, skill_level) do
    case :ets.lookup(@table, {class_id, skill_id, skill_level}) do
      [{_key, info}] -> info
      [] -> nil
    end
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(:ok) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    for {class_id, skill_id, skill_level, sp_cost, min_level} <- @initial_skill_learns do
      info = %{
        skill_id: skill_id,
        skill_level: skill_level,
        sp_cost: sp_cost,
        min_level: min_level
      }

      :ets.insert(table, {{class_id, skill_id, skill_level}, info})
    end

    Logger.info("[SkillLearnTable] Loaded #{:ets.info(table, :size)} skill learn entries")
    {:ok, %{table: table}}
  end
end
