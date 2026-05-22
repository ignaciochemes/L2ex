defmodule L2E.Packet.Client.RequestCrystallizeItem do
  @moduledoc """
  Opcode 0x72 — sent by client to crystallize an item.

  Body (RequestCrystallizeItem.java):
    object_id  LE-32   object ID of the item to crystallize
    count      LE-32   quantity to crystallize (usually 1)

  Reference: RequestCrystallizeItem.java — REQUEST_CRYSTALLIZE_ITEM(0x72, ...)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:object_id, :count]

  @type t :: %__MODULE__{
          object_id: pos_integer(),
          count: pos_integer()
        }

  @impl L2E.Packet.Decodable
  def decode(<<object_id::little-32, count::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{object_id: object_id, count: count}}
  end

  def decode(_), do: {:error, :malformed}
end
