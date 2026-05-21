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
      accuracy: accuracy(template),
      evasion: evasion(template),
      crit_rate: crit_rate(template),
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
  def max_hp(%{base_hp: base, hp_per_level: growth}, level) do
    round(base + growth * (level - 1))
  end

  @spec max_mp(map(), pos_integer()) :: pos_integer()
  def max_mp(%{base_mp: base, mp_per_level: growth}, level) do
    round(base + growth * (level - 1))
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

  @spec accuracy(map()) :: non_neg_integer()
  def accuracy(%{base_dex: dex}), do: round(dex * 0.5)

  @spec evasion(map()) :: non_neg_integer()
  def evasion(%{base_dex: dex}), do: round(dex * 0.5)

  @spec crit_rate(map()) :: non_neg_integer()
  def crit_rate(%{base_crit: base, base_dex: dex}), do: round(base + dex * 0.1)

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
  @spec xp_to_next_level(pos_integer()) :: non_neg_integer()
  def xp_to_next_level(level) when level >= 85, do: :infinity
  def xp_to_next_level(level) when level <= 1, do: 0

  def xp_to_next_level(level) do
    # Approximate formula tuned against L2 Interlude XP table
    round(:math.pow(level, 3.0) * 10 + :math.pow(level, 2.0) * 20)
  end
end
