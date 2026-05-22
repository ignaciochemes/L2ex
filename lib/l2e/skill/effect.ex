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
end
