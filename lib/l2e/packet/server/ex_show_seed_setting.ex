defmodule L2E.Packet.Server.ExShowSeedSetting do
  @moduledoc """
  Extended opcode 0xFE/0x1F — Sends the seed production settings for a castle manor to the client.

  Wire order (ExShowSeedSetting.java):
    0xFE(8) 0x1F(16LE)
    manor_id(32LE)
    count(32LE)
    per seed entry:
      seed_id(32LE)
      level(32LE)
      0x01(8)                 — reward slots type (always 1)
      reward1_id(32LE)
      0x01(8)
      reward2_id(32LE)
      seed_limit(32LE)        — max sale limit
      seed_reference_price(32LE)
      seed_min_price(32LE)
      seed_max_price(32LE)
      current_start_amount(32LE)
      current_price(32LE)
      next_start_amount(32LE)
      next_price(32LE)
  """
  @behaviour L2E.Packet.Encodable

  defstruct castle_id: 0, entries: []

  @type entry :: %{
          seed_id: integer(),
          level: integer(),
          reward1_id: integer(),
          reward2_id: integer(),
          seed_limit: integer(),
          seed_reference_price: integer(),
          seed_min_price: integer(),
          seed_max_price: integer(),
          current_start_amount: integer(),
          current_price: integer(),
          next_start_amount: integer(),
          next_price: integer()
        }
  @type t :: %__MODULE__{castle_id: integer(), entries: [entry()]}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{castle_id: castle_id, entries: entries}) do
    list = entries || []

    seed_bin =
      Enum.map_join(list, "", fn e ->
        <<e.seed_id || 0::little-32,
          e.level || 1::little-32,
          0x01::8,
          e.reward1_id || 0::little-32,
          0x01::8,
          e.reward2_id || 0::little-32,
          e.seed_limit || 0::little-32,
          e.seed_reference_price || 0::little-32,
          e.seed_min_price || 0::little-32,
          e.seed_max_price || 0::little-32,
          e.current_start_amount || 0::little-32,
          e.current_price || 0::little-32,
          e.next_start_amount || 0::little-32,
          e.next_price || 0::little-32>>
      end)

    <<0xFE::8, 0x1F::little-16, castle_id::little-32, length(list)::little-32>> <> seed_bin
  end
end
