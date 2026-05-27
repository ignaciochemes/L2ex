defmodule L2E.Packet.Server.ExShowCropSetting do
  @moduledoc """
  Extended opcode 0xFE/0x20 — Sends the crop procurement settings for a castle manor to the client.

  Wire order (ExShowCropSetting.java):
    0xFE(8) 0x20(16LE)
    manor_id(32LE)
    count(32LE)
    per crop entry:
      crop_id(32LE)
      level(32LE)             — seed level
      0x01(8)
      reward1_id(32LE)
      0x01(8)
      reward2_id(32LE)
      crop_limit(32LE)
      0(32LE)                 — reserved/unknown
      crop_min_price(32LE)
      crop_max_price(32LE)
      current_start_amount(32LE)
      current_price(32LE)
      current_reward(8)       — reward type byte
      next_start_amount(32LE)
      next_price(32LE)
      next_reward(8)
  """
  @behaviour L2E.Packet.Encodable

  defstruct castle_id: 0, entries: []

  @type entry :: %{
          crop_id: integer(),
          level: integer(),
          reward1_id: integer(),
          reward2_id: integer(),
          crop_limit: integer(),
          crop_min_price: integer(),
          crop_max_price: integer(),
          current_start_amount: integer(),
          current_price: integer(),
          current_reward: integer(),
          next_start_amount: integer(),
          next_price: integer(),
          next_reward: integer()
        }
  @type t :: %__MODULE__{castle_id: integer(), entries: [entry()]}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{castle_id: castle_id, entries: entries}) do
    list = entries || []

    crop_bin =
      Enum.map_join(list, "", fn e ->
        <<e.crop_id || 0::little-32, e.level || 1::little-32, 0x01::8,
          e.reward1_id || 0::little-32, 0x01::8, e.reward2_id || 0::little-32,
          e.crop_limit || 0::little-32, 0::little-32, e.crop_min_price || 0::little-32,
          e.crop_max_price || 0::little-32, e.current_start_amount || 0::little-32,
          e.current_price || 0::little-32, e.current_reward || 0::8,
          e.next_start_amount || 0::little-32, e.next_price || 0::little-32,
          e.next_reward || 0::8>>
      end)

    <<0xFE::8, 0x20::little-16, castle_id::little-32, length(list)::little-32>> <> crop_bin
  end
end
