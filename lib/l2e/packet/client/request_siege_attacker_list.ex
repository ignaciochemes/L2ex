defmodule L2E.Packet.Client.RequestSiegeAttackerList do
  @moduledoc """
  Opcode 0xBD — client requests the attacker clan list for a siege.

  Binary layout:
    castle_id(32LE)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:castle_id]

  @impl L2E.Packet.Decodable
  def decode(<<castle_id::little-32, _rest::binary>>), do: {:ok, %__MODULE__{castle_id: castle_id}}
  def decode(_), do: {:ok, %__MODULE__{castle_id: 0}}
end
