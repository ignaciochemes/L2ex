defmodule L2E.Packet.Client.RequestJoinSiege do
  @moduledoc """
  Opcode 0xB2 — player requests to join a siege as attacker or defender.
  Reference: RequestJoinSiege.java

  Binary layout:
    castle_id(32LE)  is_attacker(32LE)  clan_id(32LE)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:castle_id, :is_attacker, :clan_id]

  @impl L2E.Packet.Decodable
  def decode(buf) do
    <<castle_id::little-32, is_attacker::little-32, clan_id::little-32, _rest::binary>> = buf
    {:ok, %__MODULE__{castle_id: castle_id, is_attacker: is_attacker == 1, clan_id: clan_id}}
  end
end
