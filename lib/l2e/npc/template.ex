defmodule L2E.NPC.Template do
  @moduledoc """
  Plain struct describing an NPC type (monster template).

  Loaded once at startup into NPC.TemplateTable (ETS).
  All NPC.Instance processes share these read-only templates.
  """

  @enforce_keys [:npc_id, :name, :level]
  defstruct [
    :npc_id,
    :name,
    :title,
    :level,
    # Attack stats
    :p_atk,
    :m_atk,
    :p_def,
    :m_def,
    :atk_speed,
    :cast_speed,
    :accuracy,
    :evasion,
    :crit_rate,
    # Movement
    :run_speed,
    :walk_speed,
    # Vitals
    :max_hp,
    :max_mp,
    # AI
    :aggro_range,
    :is_aggressive,
    :leash_range,
    # Respawn delay in milliseconds
    :respawn_ms,
    # Attack range (melee = 40, bow = 300+)
    :attack_range,
    # Exp / SP reward on death
    :exp_reward,
    :sp_reward,
    # Faction AI — NPCs sharing the same faction_id will call for help
    faction_id: nil,
    # Skill AI
    skill_chance: 0.0,
    skills: [],
    # Movement AI
    can_walk: false,
    wander_radius: 0
  ]

  @type t :: %__MODULE__{}
end
