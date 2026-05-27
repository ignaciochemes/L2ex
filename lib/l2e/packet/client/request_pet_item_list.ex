defmodule L2E.Packet.Client.RequestPetItemList do
  @moduledoc "Opcode 0x8E — request the list of items in the pet's inventory."
  @behaviour L2E.Packet.Decodable

  defstruct []

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body) do
    {:ok, %__MODULE__{}}
  end
end
