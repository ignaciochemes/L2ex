defmodule L2E.Packet.Client.RequestDuelAnswerStart do
  @moduledoc """
  Extended opcode 0xD0/0x28 — answer a duel challenge.

  Wire order (RequestDuelAnswerStart.java):
    _partyDuel = readInt()  0=1v1, 1=party duel
    _unk1      = readInt()  unused
    _response  = readInt()  0=decline, 1=accept
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:party_duel, :response]

  @type t :: %__MODULE__{party_duel: integer(), response: integer()}

  @impl L2E.Packet.Decodable
  def decode(<<party_duel::little-32, _unk1::little-32, response::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{party_duel: party_duel, response: response}}
  end

  def decode(_), do: {:error, :malformed}
end
