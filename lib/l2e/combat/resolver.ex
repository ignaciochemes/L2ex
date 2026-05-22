defmodule L2E.Combat.Resolver do
  @moduledoc """
  Pure module for resolving physical and magical combat hits.

  Implements L2 Interlude combat math from Formulas.java:

  Physical hit:
    chance = clamp(80 + 2*(accuracy - evasion), 20, 98) percent
    damage = 76 * P.Atk * proximity_bonus / P.Def  (with ±10% variance)
    crit:    rate out of 1000, capped at 500; doubles damage (×2)

  Magical hit:
    damage = 91 * M.Atk / M.Def * skill_power_factor

  Shield block:
    roll 1..100 vs shield_rate → :failed | :blocked | :perfect_block
    :blocked     → P.Def += shield_def
    :perfect_block → 1 damage

  No side effects — randomness via :rand so tests can seed it.
  """

  # -----------------------------------------------------------------------
  # Physical hit (auto-attack or physical skill)
  # -----------------------------------------------------------------------

  @doc """
  Resolves a physical auto-attack.

  `attacker` and `defender` are stat maps:
    `%{p_atk, p_def, accuracy, evasion, crit_rate, shield_def, shield_rate}`
  Extra optional keys: `behind: bool, side: bool` for proximity bonus.

  Returns `{damage, result}` where result is `:hit | :miss | :crit | :blocked | :perfect_block`.
  """
  @spec resolve_hit(map(), map()) ::
          {non_neg_integer(), :hit | :miss | :crit | :blocked | :perfect_block}
  def resolve_hit(attacker, defender) do
    if miss?(attacker, defender) do
      {0, :miss}
    else
      case shield_check(defender) do
        :perfect_block ->
          {1, :perfect_block}

        shield ->
          effective_pdef =
            defender.p_def + if shield == :blocked, do: Map.get(defender, :shield_def, 0), else: 0

          proximity = proximity_bonus(attacker)
          base = phys_damage(attacker.p_atk, effective_pdef, proximity)

          if crit?(attacker) do
            {round(base * 2.0), :crit}
          else
            {max(1, round(base)), :hit}
          end
      end
    end
  end

  @doc """
  Resolves a physical skill hit with a flat power bonus added to P.Atk.
  """
  @spec resolve_skill_hit(map(), map(), number()) ::
          {non_neg_integer(), :hit | :miss | :crit | :blocked | :perfect_block}
  def resolve_skill_hit(attacker, defender, power) do
    effective_attacker = %{attacker | p_atk: attacker.p_atk + power}
    resolve_hit(effective_attacker, defender)
  end

  # -----------------------------------------------------------------------
  # Magical hit
  # -----------------------------------------------------------------------

  @doc """
  Resolves a magical skill hit.

  `power` is the skill's magic power (from skill template).
  Returns `{damage, :hit | :mcrit}`.
  Magic never misses in L2 (no evasion check).
  """
  @spec resolve_magic_hit(map(), map(), number()) :: {non_neg_integer(), :hit | :mcrit}
  def resolve_magic_hit(attacker, defender, power) do
    m_def = max(1, Map.get(defender, :m_def, 20))
    base = 91.0 * attacker.m_atk * (1.0 + power / 100.0) / m_def
    variance = 0.90 + :rand.uniform() * 0.20

    if magic_crit?(attacker) do
      {max(1, round(base * variance * 3.0)), :mcrit}
    else
      {max(1, round(base * variance)), :hit}
    end
  end

  # -----------------------------------------------------------------------
  # Private
  # -----------------------------------------------------------------------

  # L2 hit-miss formula: chance = clamp(80 + 2*(accuracy - evasion), 20, 98) %
  # Internally uses per-mille: clamp(800 + 20*(acc-eva), 200, 980) / 1000
  defp miss?(attacker, defender) do
    diff = Map.get(attacker, :accuracy, 0) - Map.get(defender, :evasion, 0)
    chance = clamp(800 + 20 * diff, 200, 980)
    :rand.uniform(1000) > chance
  end

  # Physical damage: 76 * P.Atk * proximity / P.Def with ±10% variance
  defp phys_damage(p_atk, p_def, proximity) when p_def > 0 do
    variance = 0.90 + :rand.uniform() * 0.20
    76.0 * p_atk * proximity / p_def * variance
  end

  defp phys_damage(p_atk, _p_def, proximity), do: p_atk * proximity * 0.8

  # Behind: +20%, side: +10%, front: 0%
  defp proximity_bonus(%{behind: true}), do: 1.2
  defp proximity_bonus(%{side: true}), do: 1.1
  defp proximity_bonus(_), do: 1.0

  # Crit check: crit_rate is out of 1000, capped at 500
  defp crit?(attacker) do
    rate = min(Map.get(attacker, :crit_rate, 40), 500)
    :rand.uniform(1000) <= rate
  end

  # Magic crit: flat 3% base chance, modified by WIT (1% per 10 WIT above 20)
  defp magic_crit?(attacker) do
    wit = Map.get(attacker, :wit, 20)
    rate = round(30 + max(0, wit - 20) * 1.0)
    :rand.uniform(1000) <= min(rate, 100)
  end

  # Shield check: returns :failed | :blocked | :perfect_block
  defp shield_check(defender) do
    shield_rate = Map.get(defender, :shield_rate, 0)

    cond do
      shield_rate <= 0 ->
        :failed

      :rand.uniform(100) <= shield_rate ->
        if :rand.uniform(100) <= 10, do: :perfect_block, else: :blocked

      true ->
        :failed
    end
  end

  defp clamp(v, lo, hi), do: max(lo, min(hi, v))
end
