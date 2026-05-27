defmodule L2E.Packet.Client.RequestConfirmGemStone do
  @moduledoc """
  Player confirms embedding a soul crystal into a weapon.

  Note: In L2 Interlude the opcode for this packet conflicts with
  RequestAcquireSkillInfo (0x6B). This struct is defined for future use
  when the correct opcode is confirmed.
  """

  defstruct [:target_item_id, :crystal_item_id, :crystal_opt_data]

  def decode(body) do
    <<
      target_item_id::little-32,
      crystal_item_id::little-32,
      crystal_opt_data::little-32,
      _rest::binary
    >> = body

    %__MODULE__{
      target_item_id: target_item_id,
      crystal_item_id: crystal_item_id,
      crystal_opt_data: crystal_opt_data
    }
  end
end
