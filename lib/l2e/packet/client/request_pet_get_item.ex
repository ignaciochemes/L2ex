defmodule L2E.Packet.Client.RequestPetGetItem do
  @moduledoc "Opcode 0x8F — command pet to pick up a ground item. Reference: RequestPetGetItem.java"
  @behaviour L2E.Packet.Decodable

  defstruct [:object_id]

  @type t :: %__MODULE__{object_id: integer()}

  @impl L2E.Packet.Decodable
  def decode(<<object_id::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{object_id: object_id}}
  end

  def decode(_), do: {:error, :malformed}
end
