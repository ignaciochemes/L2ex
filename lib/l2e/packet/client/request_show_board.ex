defmodule L2E.Packet.Client.RequestShowBoard do
  @moduledoc """
  Opcode 0xAB — player opens the Community Board (BBS).

  Sent when the player clicks the Community Board button in the client UI.

  Binary layout (RequestShowBoard.java):
    type(32LE)  — 0 = main, 1 = community, 2 = friend list

  Reference: ClientPackets.java REQUEST_SHOW_BOARD(0xAB)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:type]
  @type t :: %__MODULE__{type: non_neg_integer()}

  @impl L2E.Packet.Decodable
  def decode(body) do
    <<type::little-32, _rest::binary>> = body
    {:ok, %__MODULE__{type: type}}
  end
end
