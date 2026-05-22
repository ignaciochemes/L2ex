defmodule L2E.Game.Stats do
  @moduledoc """
  Pure module for deriving final character stats from a class template + level.

  Formulas are simplified approximations of L2 Interlude math.
  When XML data files become available (M9), the per-level base tables
  will replace the linear hp_per_level / mp_per_level approximations.

  Stat modifier tables (STR → P.Atk bonus etc.) follow the relative
  proportions from L2 Interlude. Exact lookup tables live in the gamedata
  XML files; until M9 we use linear interpolation around the midpoint.
  """

  @doc """
  Computes all derived stats for a character.
  Returns a map with integer values suitable for StatusUpdate packets.
  """
  @spec compute(map(), pos_integer()) :: map()
  def compute(template, level) do
    %{
      level: level,
      max_hp: max_hp(template, level),
      max_mp: max_mp(template, level),
      max_cp: max_cp(template, level),
      p_atk: p_atk(template, level),
      p_def: p_def(template, level),
      m_atk: m_atk(template, level),
      m_def: m_def(template, level),
      atk_speed: template.atk_speed,
      cast_speed: template.cast_speed,
      run_speed: template.run_speed,
      walk_speed: template.walk_speed,
      accuracy: accuracy(template, level),
      evasion: evasion(template, level),
      crit_rate: crit_rate(template),
      shield_rate: shield_rate(template),
      str: template.base_str,
      dex: template.base_dex,
      con: template.base_con,
      int: template.base_int,
      wit: template.base_wit,
      men: template.base_men,
      attack_range: template.base_attack_range
    }
  end

  # -----------------------------------------------------------------------
  # HP / MP / CP
  # -----------------------------------------------------------------------

  @spec max_hp(map(), pos_integer()) :: pos_integer()
  def max_hp(%{base_hp: base}, level) do
    max_hp_at_level(base, level)
  end

  @spec max_mp(map(), pos_integer()) :: pos_integer()
  def max_mp(%{base_mp: base}, level) do
    max_mp_at_level(base, level)
  end

  # Non-linear HP growth: polynomial curve matching L2 Interlude progression.
  # At level 1 → ~1.08× base; level 40 → ~6.3× base; level 80 → ~13.8× base.
  defp max_hp_at_level(base_hp, level) do
    round(base_hp * (1 + level * 0.07 + :math.pow(level, 1.5) * 0.01))
  end

  # MP grows faster relative to base due to regen mechanics.
  defp max_mp_at_level(base_mp, level) do
    round(base_mp * (1 + level * 0.08))
  end

  @spec max_cp(map(), pos_integer()) :: pos_integer()
  def max_cp(%{base_cp: base, cp_per_level: growth}, level) do
    round(base + growth * (level - 1))
  end

  # -----------------------------------------------------------------------
  # Offensive stats
  # -----------------------------------------------------------------------

  @doc "Physical attack power. Scales with level and STR modifier."
  @spec p_atk(map(), pos_integer()) :: pos_integer()
  def p_atk(%{base_p_atk: base, base_str: str}, level) do
    round(base * level_factor(level) * str_bonus(str))
  end

  @doc "Magic attack power. Scales with level and INT modifier (squared, per L2 formula)."
  @spec m_atk(map(), pos_integer()) :: pos_integer()
  def m_atk(%{base_m_atk: base, base_int: int_val}, level) do
    bonus = int_bonus(int_val)
    round(base * level_factor(level) * bonus * bonus)
  end

  # -----------------------------------------------------------------------
  # Defensive stats
  # -----------------------------------------------------------------------

  @spec p_def(map(), pos_integer()) :: pos_integer()
  def p_def(%{base_p_def: base}, level) do
    round(base * (1.0 + (level - 1) * 0.035))
  end

  @spec m_def(map(), pos_integer()) :: pos_integer()
  def m_def(%{base_m_def: base, base_men: men}, level) do
    round(base * (1.0 + (level - 1) * 0.035) * men_bonus(men))
  end

  # -----------------------------------------------------------------------
  # Accuracy / Evasion / Critical
  # -----------------------------------------------------------------------

  # L2 formula: accuracy = sqrt(DEX) * 6 + level
  @spec accuracy(map(), pos_integer()) :: non_neg_integer()
  def accuracy(%{base_dex: dex}, level), do: round(:math.sqrt(dex) * 6 + level)

  # Backward-compat 1-arity (level 1 default, used in Stats.compute/2 below)
  @spec accuracy(map()) :: non_neg_integer()
  def accuracy(%{base_dex: dex}), do: round(:math.sqrt(dex) * 6)

  # L2 formula: evasion = sqrt(DEX) * 4 + level
  @spec evasion(map(), pos_integer()) :: non_neg_integer()
  def evasion(%{base_dex: dex}, level), do: round(:math.sqrt(dex) * 4 + level)

  @spec evasion(map()) :: non_neg_integer()
  def evasion(%{base_dex: dex}), do: round(:math.sqrt(dex) * 4)

  # L2 formula: crit_rate = sqrt(DEX) * 3 (out of 1000, max 500 = 50%)
  @spec crit_rate(map()) :: non_neg_integer()
  def crit_rate(%{base_crit: base, base_dex: dex}) do
    min(round(base + :math.sqrt(dex) * 3), 500)
  end

  # Shield defense rate (base from template)
  @spec shield_rate(map()) :: non_neg_integer()
  def shield_rate(%{base_shield_rate: r}), do: r
  def shield_rate(_), do: 0

  # -----------------------------------------------------------------------
  # Regeneration rates (per 3-second tick)
  # -----------------------------------------------------------------------

  @doc "HP regenerated per 3-second regen tick. L2 formula: CON * 1.5 + base_regen_hp."
  @spec hp_regen(map(), pos_integer()) :: float()
  def hp_regen(%{base_con: con, base_hp: base_hp}, level) do
    base_regen = base_hp * 0.005
    con_bonus = con * 1.5
    (base_regen + con_bonus) * (1.0 + level * 0.01)
  end

  @doc "MP regenerated per 3-second regen tick. L2 formula: MEN * 0.3 + base_regen_mp."
  @spec mp_regen(map(), pos_integer()) :: float()
  def mp_regen(%{base_men: men, base_mp: base_mp}, level) do
    base_regen = base_mp * 0.004
    men_bonus = men * 0.3
    (base_regen + men_bonus) * (1.0 + level * 0.005)
  end

  # -----------------------------------------------------------------------
  # Stat modifiers
  # -----------------------------------------------------------------------

  # Each STR point above/below 40 gives ±0.6% P.Atk (approx from L2 table)
  defp str_bonus(str), do: max(0.1, 1.0 + (str - 40) * 0.006)

  # Each INT point above/below 40 gives ±0.4% M.Atk base (squared in m_atk)
  defp int_bonus(int_val), do: max(0.1, 1.0 + (int_val - 40) * 0.004)

  # Each MEN point above/below 30 gives ±0.4% M.Def
  defp men_bonus(men), do: max(0.1, 1.0 + (men - 30) * 0.004)

  # Linear level scaling: at level 1 → 1.0×, at level 20 → ~2.2×, at level 40 → ~3.4×
  defp level_factor(level), do: 1.0 + (level - 1) * 0.062

  # -----------------------------------------------------------------------
  # Equipment bonuses
  # -----------------------------------------------------------------------

  @doc """
  Applies flat equipment bonuses (from equipped items) to a base stat map.

  `bonuses` is the map returned by `L2E.Inventory.get_equip_bonuses/1`:
  `%{p_atk: int, p_def: int, m_atk: int, m_def: int}`.
  """
  @spec apply_equipment(map(), map()) :: map()
  def apply_equipment(stats, bonuses) do
    %{
      stats
      | p_atk: stats.p_atk + (bonuses[:p_atk] || 0),
        p_def: stats.p_def + (bonuses[:p_def] || 0),
        m_atk: stats.m_atk + (bonuses[:m_atk] || 0),
        m_def: stats.m_def + (bonuses[:m_def] || 0)
    }
  end

  # -----------------------------------------------------------------------
  # Buff bonuses
  # -----------------------------------------------------------------------

  @doc """
  Applies flat stat bonuses from a list of active BuffInfo structs.

  Each buff's `stat_bonus` map may contain any subset of stat keys.
  Unknown keys are ignored so future buff types don't crash older callers.
  """
  @spec apply_buffs(map(), list()) :: map()
  def apply_buffs(stats, []), do: stats

  def apply_buffs(stats, buffs) do
    Enum.reduce(buffs, stats, fn buff, acc ->
      Enum.reduce(buff.stat_bonus, acc, fn {key, val}, s ->
        case Map.has_key?(s, key) do
          true -> Map.update!(s, key, &(&1 + val))
          false -> s
        end
      end)
    end)
  end

  @doc """
  Returns the cumulative XP required to reach the given level.
  Approximates the L2 Interlude experience table.
  Level 1 requires 0 XP. Level 2 requires 68, then grows roughly as level^3.
  """
  @spec xp_to_next_level(pos_integer()) :: non_neg_integer() | :infinity
  def xp_to_next_level(level) when level >= 85, do: :infinity
  def xp_to_next_level(level) when level <= 1, do: 0

  def xp_to_next_level(level) do
    alias L2E.Data.ExperienceTable
    ExperienceTable.get_xp_for_level(level + 1) - ExperienceTable.get_xp_for_level(level)
  end
end
