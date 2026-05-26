defmodule L2E.Packet.Client.RequestPartyLootModify do
  @moduledoc """
  Opcode 0x5B — Client requests to change party loot distribution mode.
  Only valid when sent by the party leader.

  Loot type byte values (L2 Interlude protocol):
    0 = finders_keepers
    1 = random_including_spoil
    2 = by_turn
    3 = by_turn_including_spoil
    4 = random

  Binary layout: loot_type(32LE)

  Reference: L2J Mobius CT0 Interlude clientpackets/RequestPartyLootModify.java
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:loot_type]

  @impl true
  def decode(buf) do
    <<loot_type::little-32, _rest::binary>> = buf

    mode =
      case loot_type do
        0 -> :finders_keepers
        1 -> :random_including_spoil
        2 -> :by_turn
        3 -> :by_turn_including_spoil
        4 -> :random
        _ -> :finders_keepers
      end

    {:ok, %__MODULE__{loot_type: mode}}
  end
end
