defmodule L2E.Packet.Client.RequestUnequipItem do
  @moduledoc """
  Opcode 0x11 — sent by client to unequip an item from a given equipment slot.

  Body (RequestUnEquipItem.java):
    slot  LE-32   equipment slot integer (see Paperdoll slot constants)

  Reference: RequestUnEquipItem.java — REQUEST_UN_EQUIP_ITEM(0x11, ...)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:slot]

  @type t :: %__MODULE__{
          slot: non_neg_integer()
        }

  @impl L2E.Packet.Decodable
  def decode(<<slot::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{slot: slot}}
  end

  def decode(_), do: {:error, :malformed}
end
