defmodule L2E.Packet.Client.RequestManorList do
  @moduledoc """
  Opcode 0x8D — Player requests the manor castle list.
  No body — server responds with ExSendManorList.
  """
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end
