defmodule L2E.Data.ExperienceLossData do
  @moduledoc """
  Static XP loss percentages for player death in Lineage II Interlude.

  Interlude rules (hardcoded constants — no XML source in CT0):
    - Below level 7 : no XP loss
    - Level 7–39    : 4% of XP within the current level
    - Level 40–75   : 3% of XP within the current level
    - Level 76+     : 2% of XP within the current level

  "XP within the current level" = total_exp - get_xp_for_level(current_level).
  A player can never lose more than their progress within the current level,
  so level-down from death does not occur.

  The GenServer shell exists only to fit the supervision tree; all lookups
  are pure module-level functions backed by compile-time constants.
  """

  use GenServer
  require Logger

  # ---------------------------------------------------------------------------
  # Supervision API
  # ---------------------------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    Logger.info("[ExperienceLossData] Loaded static XP loss table (Interlude rules)")
    {:ok, %{}}
  end

  # ---------------------------------------------------------------------------
  # Public API — pure functions, no GenServer call needed
  # ---------------------------------------------------------------------------

  @doc """
  Returns the XP loss fraction (0.0–1.0) for the given level.

  The optional `pvp?` flag is reserved for future karma/chaotic logic
  and is currently unused (PvP XP loss rules apply only to chaotic players,
  which is handled at the call site in player_session).
  """
  @spec get_loss_percent(pos_integer(), boolean()) :: float()
  def get_loss_percent(level, pvp? \\ false)

  def get_loss_percent(level, _pvp?) when level < 7, do: 0.0
  def get_loss_percent(level, _pvp?) when level < 40, do: 0.04
  def get_loss_percent(level, _pvp?) when level < 76, do: 0.03
  def get_loss_percent(_level, _pvp?), do: 0.02

  @doc """
  Calculates the EXP lost when a player at `level` with `current_exp` total
  EXP dies. Returns 0 for characters below level 7.

  The loss is always capped to the EXP progress within the current level,
  so the result can never push the player below their level floor.
  """
  @spec calculate_exp_loss(non_neg_integer(), pos_integer()) :: non_neg_integer()
  def calculate_exp_loss(_current_exp, level) when level < 7, do: 0

  def calculate_exp_loss(current_exp, level) do
    xp_at_level_start = L2E.Data.ExperienceTable.get_xp_for_level(level)
    xp_in_level = max(0, current_exp - xp_at_level_start)
    percent = get_loss_percent(level)
    trunc(xp_in_level * percent)
  end
end
