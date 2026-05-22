defmodule L2E.Packet.Client.RequestAnswerFriendInvite do
  @moduledoc "Opcode 0x5F — answer a received friend invite. response: 0=decline, 1=accept. Reference: RequestAnswerFriendInvite.java"
  @behaviour L2E.Packet.Decodable

  defstruct [:response]

  @type t :: %__MODULE__{response: integer()}

  @impl L2E.Packet.Decodable
  def decode(<<response::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{response: response}}
  end

  def decode(_), do: {:error, :malformed}
end
