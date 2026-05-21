defmodule L2E.Skill.BuffInfo do
  @moduledoc """
  Tracks one active buff/debuff on a player or NPC.

  `start_monotonic` is set to `System.monotonic_time(:millisecond)` when the
  buff is applied. Remaining duration is: duration_ms - (now - start_monotonic).
  """

  @enforce_keys [:skill_id, :level, :skill_name, :caster_id, :start_monotonic, :duration_ms]

  defstruct [
    :skill_id,
    :level,
    :skill_name,
    :caster_id,
    :start_monotonic,
    :duration_ms,
    stat_bonus: %{}
  ]

  @type t :: %__MODULE__{
          skill_id: pos_integer(),
          level: pos_integer(),
          skill_name: String.t(),
          caster_id: pos_integer(),
          start_monotonic: integer(),
          duration_ms: pos_integer(),
          stat_bonus: %{optional(atom()) => integer()}
        }

  @doc "Remaining time in milliseconds. Returns 0 if already expired."
  @spec remaining_ms(t()) :: non_neg_integer()
  def remaining_ms(%__MODULE__{start_monotonic: start, duration_ms: dur}) do
    elapsed = System.monotonic_time(:millisecond) - start
    max(0, dur - elapsed)
  end

  @doc "Remaining time in ticks (1 tick ≈ 333 ms) for AbnormalStatusUpdate packet."
  @spec remaining_ticks(t()) :: non_neg_integer()
  def remaining_ticks(buff), do: max(1, div(remaining_ms(buff), 333))
end
