defmodule L2E.Skill.Effect do
  @moduledoc """
  Pure computation module for skill effects.

  All functions are stateless — they take stats maps and return results.
  No process interaction, no side effects.
  """

  @doc """
  Computes magical skill damage.

  Formula (simplified Interlude approximation):
    damage = m_atk * power / 100 * (1 - m_def_factor)
  where m_def_factor = clamp(target_m_def / 1000, 0, 0.85)
  """
  @spec apply_magic_damage(map(), map(), pos_integer()) :: pos_integer()
  def apply_magic_damage(caster_stats, target_stats, power) do
    m_atk = Map.get(caster_stats, :m_atk, 10)
    m_def = Map.get(target_stats, :m_def, 20)
    m_def_factor = min(0.85, m_def / 1000.0)
    raw = m_atk * power / 100.0 * (1.0 - m_def_factor)
    max(1, round(raw))
  end

  @doc """
  Computes physical skill damage (burst above auto-attack).

  Formula:
    damage = p_atk * (1 + power / 100) * (1 - p_def_factor)
  where p_def_factor = clamp(target_p_def / 1000, 0, 0.8)
  """
  @spec apply_physical_damage(map(), map(), pos_integer()) :: pos_integer()
  def apply_physical_damage(caster_stats, target_stats, power) do
    p_atk = Map.get(caster_stats, :p_atk, 10)
    p_def = Map.get(target_stats, :p_def, 50)
    p_def_factor = min(0.80, p_def / 1000.0)
    raw = p_atk * (1.0 + power / 100.0) * (1.0 - p_def_factor)
    max(1, round(raw))
  end

  @doc """
  Computes the HP amount restored by a heal skill.

  Formula:
    healed = power * (1 + m_atk / 2000) * level_bonus
  where level_bonus = 1 + level * 0.01
  """
  @spec apply_heal(map(), pos_integer()) :: pos_integer()
  def apply_heal(caster_stats, power) do
    m_atk = Map.get(caster_stats, :m_atk, 3)
    level = Map.get(caster_stats, :level, 1)
    level_bonus = 1.0 + level * 0.01
    healed = power * (1.0 + m_atk / 2000.0) * level_bonus
    max(1, round(healed))
  end

  # M49: CC success check — 80% base, -1% per MEN above 20, clamped 10-95%
  def check_cc_lands?(caster_stats, target_stats) do
    caster_level = Map.get(caster_stats, :level, 1)
    target_men = Map.get(target_stats, :men, 20)
    base_rate = 0.80 - (target_men - 20) * 0.01
    rate = :erlang.max(0.10, :erlang.min(0.95, base_rate + caster_level * 0.002))
    :rand.uniform() <= rate
  end

  # M49: DoT tick damage — scales with caster's M.Atk for magic DoTs
  def dot_tick_damage(caster_stats, power) do
    m_atk = Map.get(caster_stats, :m_atk, 10)
    max(1, round(power + m_atk * 0.05))
  end

  # ── M49-B: Speed reduction ──────────────────────────────────────────────────

  @doc "Returns speed multiplier for slow effect. power is percent reduction (e.g. 30 = 30% slower)."
  def slow_factor(power), do: max(0.3, 1.0 - power / 100.0)

  # ── M49-B: Silence landing check ────────────────────────────────────────────

  @doc "Returns true if silence debuff lands. Same MEN-based formula as CC."
  def check_silence_lands?(caster_stats, target_stats),
    do: check_cc_lands?(caster_stats, target_stats)

  # ── M49-B: Mana burn ────────────────────────────────────────────────────────

  @doc "MP damage from mana burn skills (e.g. Mana Burn, Drain Mana)."
  def apply_mana_burn(caster_stats, power) do
    m_atk = Map.get(caster_stats, :m_atk, 10)
    max(1, round(power * (1.0 + m_atk / 3000.0)))
  end

  # ── M49-B: Stat modifiers ───────────────────────────────────────────────────

  @doc """
  Applies a stat modifier entry.
  type: :add or :percent
  stat: atom key (:p_atk, :p_def, :m_atk, :m_def, :speed, :evasion_rate, :accuracy, :atk_spd, :cast_spd)
  value: numeric modifier
  Returns a modifier map to be merged into buff state.
  """
  def stat_modifier(stat, type, value) when type in [:add, :percent],
    do: %{stat: stat, type: type, value: value}

  @doc "Computes effective stat value after applying a list of modifiers."
  def apply_stat_mods(base_value, mods, stat) do
    relevant = Enum.filter(mods, &(&1.stat == stat))
    adds = Enum.filter(relevant, &(&1.type == :add)) |> Enum.map(& &1.value) |> Enum.sum()
    pcts = Enum.filter(relevant, &(&1.type == :percent)) |> Enum.map(& &1.value) |> Enum.sum()
    round((base_value + adds) * (1.0 + pcts / 100.0))
  end

  # ── M49-B: MP DoT tick ──────────────────────────────────────────────────────

  @doc "MP drain per tick (mana DoT skills)."
  def dot_tick_mp(caster_stats, power) do
    m_atk = Map.get(caster_stats, :m_atk, 10)
    max(1, round(power + m_atk * 0.03))
  end

  # ── M49-B: Resurrection ─────────────────────────────────────────────────────

  @doc """
  Computes HP/MP granted by a resurrection effect.
  power is percentage of max to restore (e.g. 70 = 70%).
  Returns {hp_restore, mp_restore}.
  """
  def apply_resurrection(target_stats, power) do
    max_hp = Map.get(target_stats, :max_hp, 100)
    max_mp = Map.get(target_stats, :max_mp, 50)
    pct = power / 100.0
    {max(1, round(max_hp * pct)), max(1, round(max_mp * pct))}
  end

  # ── M49-B: Cancel / Dispel ──────────────────────────────────────────────────

  @doc """
  Determines how many buffs are removed by a cancel/dispel effect.
  power is 1–5 representing max buffs to strip.
  Returns integer count.
  """
  def cancel_count(power), do: max(1, min(5, div(power, 20)))

  # ── M80: HP Drain ───────────────────────────────────────────────────────────

  @doc "HP drain: deals magic damage AND heals caster for a percentage of damage dealt."
  @spec apply_hp_drain(map(), map(), pos_integer(), float()) :: %{damage: pos_integer(), healed: pos_integer()}
  def apply_hp_drain(caster_stats, target_stats, power, drain_ratio \\ 0.5) do
    damage = apply_magic_damage(caster_stats, target_stats, power)
    healed = round(damage * drain_ratio)
    %{damage: damage, healed: healed}
  end

  # ── M80: Fear ───────────────────────────────────────────────────────────────

  @doc "Fear: returns the duration in ms based on MEN resist."
  @spec fear_duration(map(), pos_integer()) :: pos_integer()
  def fear_duration(target_stats, base_duration_ms) do
    men = Map.get(target_stats, :men, 20)
    # MEN reduces fear duration: 30 MEN = no reduction, 40 MEN = 25% reduction
    resist_factor = max(0.1, 1.0 - (men - 30) * 0.025)
    round(base_duration_ms * resist_factor)
  end

  # ── M80: Paralyze ───────────────────────────────────────────────────────────

  @doc "Paralyze: returns duration in ms (same resist formula as fear but different CC type)."
  @spec paralyze_duration(map(), pos_integer()) :: pos_integer()
  def paralyze_duration(target_stats, base_duration_ms) do
    fear_duration(target_stats, base_duration_ms)
  end

  # ── M80: HP percent DoT ─────────────────────────────────────────────────────

  @doc "HP damage over time as percent of max HP."
  @spec dot_tick_hp_percent(map(), float()) :: pos_integer()
  def dot_tick_hp_percent(target_stats, percent) do
    max_hp = Map.get(target_stats, :max_hp, 100)
    max(1, round(max_hp * percent / 100.0))
  end

  # ── M80: Dispel ─────────────────────────────────────────────────────────────

  @doc "Dispel: returns count of buffs to remove from target."
  @spec dispel_count(pos_integer()) :: pos_integer()
  def dispel_count(power) do
    # power represents number of buff slots to remove (1-5)
    max(1, min(5, div(power, 20)))
  end

  # ── M80: Aggression ─────────────────────────────────────────────────────────

  @doc "Aggression: hate value to add to target NPC hate map."
  @spec aggression_value(map(), pos_integer()) :: pos_integer()
  def aggression_value(caster_stats, power) do
    level = Map.get(caster_stats, :level, 1)
    level * power
  end

  # ── M80: Noblesse Blessing ──────────────────────────────────────────────────

  @doc "Noblesse Blessing: returns duration in ms (flat, not reduced by stats)."
  @spec noblesse_blessing_duration(pos_integer()) :: pos_integer()
  def noblesse_blessing_duration(base_duration_ms), do: base_duration_ms

  # ── M80: Fake Death ─────────────────────────────────────────────────────────

  @doc "Fake death: returns true if the fake death succeeds (90% base success rate)."
  @spec fake_death_lands?() :: boolean()
  def fake_death_lands?(), do: :rand.uniform(100) <= 90
end
