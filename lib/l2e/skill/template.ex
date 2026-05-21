defmodule L2E.Skill.Template do
  @moduledoc """
  Immutable definition of a skill type loaded into ETS at startup.

  Fields
  - skill_id / level    — composite key (skill_id, level)
  - type                — :active | :passive | :toggle
  - target_type         — :one | :self | :aoe | :corpse
  - effect_type         — :p_damage | :m_damage | :heal | :buff | :debuff
  - power               — dimensionless multiplier used by Effect formulas
  - mp_cost             — MP consumed on cast
  - cast_time_ms        — cast animation duration before effect lands
  - reuse_ms            — cooldown after the skill completes
  - range               — max cast range (world units)
  - is_magic            — true = cancelled by silence; false = cancelled by stun
  - buff_duration_ms    — for type :buff/:debuff only, 0 otherwise
  - stat_bonus          — map of stat-key → integer bonus added while buff active
                          e.g. %{p_atk: 15} for Might
  """

  @enforce_keys [:skill_id, :level, :name]

  defstruct [
    :skill_id,
    :level,
    :name,
    type: :active,
    target_type: :one,
    effect_type: :p_damage,
    power: 0,
    mp_cost: 0,
    cast_time_ms: 1000,
    reuse_ms: 3000,
    range: 600,
    is_magic: false,
    buff_duration_ms: 0,
    stat_bonus: %{}
  ]

  @type t :: %__MODULE__{
          skill_id: pos_integer(),
          level: pos_integer(),
          name: String.t(),
          type: :active | :passive | :toggle,
          target_type: :one | :self | :aoe | :corpse,
          effect_type: :p_damage | :m_damage | :heal | :buff | :debuff,
          power: integer(),
          mp_cost: non_neg_integer(),
          cast_time_ms: pos_integer(),
          reuse_ms: pos_integer(),
          range: pos_integer(),
          is_magic: boolean(),
          buff_duration_ms: non_neg_integer(),
          stat_bonus: %{optional(atom()) => integer()}
        }
end
