defmodule L2E.Combat.Resolver do
  @moduledoc """
  Pure module for resolving physical combat hits.

  Implements a simplified version of the L2 Interlude physical formula:
    base_damage = P.Atk * 70 / P.Def
    accuracy check → :miss if attacker accuracy < defender evasion roll
    crit check → multiplier × 2 if successful

  No side effects — all randomness is injected via :rand so tests can seed it.

  Reference: Formulas.java (calcPhysDam, calcHit, calcCrit)
  """

  @doc """
  Resolves a single physical hit.

  Returns `{damage, result}` where result is `:hit | :miss | :crit`.
  damage is 0 on a miss.
  """
  @spec resolve_hit(map(), map()) :: {non_neg_integer(), :hit | :miss | :crit}
  def resolve_hit(attacker, defender) do
    if miss?(attacker, defender) do
      {0, :miss}
    else
      base = base_damage(attacker.p_atk, defender.p_def)

      if crit?(attacker) do
        {round(base * 2.0), :crit}
      else
        {round(base), :hit}
      end
    end
  end

  # -----------------------------------------------------------------------
  # Private
  # -----------------------------------------------------------------------

  # L2 formula: P.Atk * 70 / P.Def with ±15% random variance
  defp base_damage(p_atk, p_def) when p_def > 0 do
    variance = 0.85 + :rand.uniform() * 0.30
    p_atk * 70.0 / p_def * variance
  end

  defp base_damage(p_atk, _p_def), do: p_atk * 0.7

  # Miss check: compare accuracy vs evasion with a random roll
  # L2 formula: P(hit) = (accuracy - evasion + 85) / 100 clamped to [10%, 95%]
  defp miss?(attacker, defender) do
    hit_chance = clamp((attacker.accuracy - defender.evasion + 85) / 100.0, 0.10, 0.95)
    :rand.uniform() > hit_chance
  end

  # Crit check: crit_rate is out of 1000 in L2 (max 500)
  # Simplified: crit_rate / 100 gives a 0–5% base chance
  defp crit?(attacker) do
    crit_chance = min(attacker.crit_rate / 100.0, 0.33)
    :rand.uniform() < crit_chance
  end

  defp clamp(v, lo, hi), do: max(lo, min(hi, v))
end
