defmodule L2E.Packet.Client.RequestRefine do
  @moduledoc """
  Extended opcode 0xD0/0x2C — player performs the augmentation (life stone use).

  Body (RequestRefine.java — Format: ch dddd):
    targetItemObjId    LE-32  — weapon/armor to augment (object_id)
    refinerItemObjId   LE-32  — life stone item (object_id)
    gemStoneItemObjId  LE-32  — gemstone item to consume (object_id)
    gemStoneCount      LE-32  — number of gemstones to consume

  The server determines the life stone grade from its item_id, rolls a random
  augmentation option from OptionTable, consumes the life stone, and sends
  ExVariationResult back to the client.
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:target_obj_id, :refiner_obj_id, :gemstone_obj_id, :gemstone_count]

  @type t :: %__MODULE__{
          target_obj_id: pos_integer(),
          refiner_obj_id: pos_integer(),
          gemstone_obj_id: pos_integer(),
          gemstone_count: non_neg_integer()
        }

  @impl L2E.Packet.Decodable
  def decode(
        <<target_obj_id::little-32, refiner_obj_id::little-32, gemstone_obj_id::little-32,
          gemstone_count::little-32, _rest::binary>>
      ) do
    {:ok,
     %__MODULE__{
       target_obj_id: target_obj_id,
       refiner_obj_id: refiner_obj_id,
       gemstone_obj_id: gemstone_obj_id,
       gemstone_count: gemstone_count
     }}
  end

  def decode(_), do: {:error, :malformed}
end
