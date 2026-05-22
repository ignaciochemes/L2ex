defmodule L2E.Packet.Client.RequestConfirmRefinerItem do
  @moduledoc """
  Extended opcode 0xD0/0x2A — player confirms the life stone to use for augmentation.

  Body (RequestConfirmRefinerItem.java — Format: dd):
    targetItemObjId   LE-32  — weapon/armor to augment (object_id)
    refinerItemObjId  LE-32  — life stone item (object_id)

  Sent before RequestRefine. Server responds with ExPutIntensiveResultForVariationMake
  (or a similar UI prompt). For our MVP, we no-op this packet — the actual augment
  happens on RequestRefine.
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:target_obj_id, :refiner_obj_id]
  @type t :: %__MODULE__{target_obj_id: pos_integer(), refiner_obj_id: pos_integer()}

  @impl L2E.Packet.Decodable
  def decode(<<target_obj_id::little-32, refiner_obj_id::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{target_obj_id: target_obj_id, refiner_obj_id: refiner_obj_id}}
  end

  def decode(_), do: {:error, :malformed}
end
