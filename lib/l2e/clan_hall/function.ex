defmodule L2E.ClanHall.Function do
  @moduledoc "M125: Clan hall function definitions (timed buffs/services)."

  @type function_type ::
          :restore_hp
          | :restore_mp
          | :restore_exp
          | :support_magic
          | :curtain
          | :front_platform
          | :item_creation
          | :teleport

  defstruct [:type, :level, :duration_ms, :activated_at]

  @durations %{
    restore_hp: 86_400_000,
    restore_mp: 86_400_000,
    restore_exp: 86_400_000,
    support_magic: 86_400_000,
    curtain: 86_400_000,
    front_platform: 86_400_000,
    item_creation: 86_400_000,
    teleport: 86_400_000
  }

  def build(type, level) do
    %__MODULE__{
      type: type,
      level: level,
      duration_ms: Map.get(@durations, type, 86_400_000),
      activated_at: System.system_time(:millisecond)
    }
  end

  def active?(%__MODULE__{activated_at: at, duration_ms: dur}) do
    System.system_time(:millisecond) < at + dur
  end
end
