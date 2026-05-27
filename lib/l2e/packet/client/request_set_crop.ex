defmodule L2E.Packet.Client.RequestSetCrop do
  @moduledoc """
  Extended opcode 0xD0/0x0B — Sent by the castle lord to set crop procurement for a castle manor.

  Wire order (RequestSetCrop.java):
    manor_id    : readInt()    — castle/manor ID
    count       : readInt()    — number of entries
    per entry (13 bytes each):
      item_id     : readInt()  — crop item ID
      amount      : readInt()  — amount to procure (start_amount)
      price       : readInt()  — purchase price per crop
      reward_type : readByte() — reward type (0=adena, 1=fixed reward)
  """
  @behaviour L2E.Packet.Decodable

  defstruct castle_id: 0, entries: []

  @type entry :: %{
          item_id: integer(),
          amount: integer(),
          start_amount: integer(),
          price: integer(),
          reward_type: integer()
        }
  @type t :: %__MODULE__{castle_id: integer(), entries: [entry()]}

  @batch_length 13

  @impl L2E.Packet.Decodable
  def decode(<<manor_id::little-32, count::little-32, rest::binary>>) do
    expected = count * @batch_length

    if count > 0 and byte_size(rest) >= expected do
      entries = decode_entries(rest, count, [])
      {:ok, %__MODULE__{castle_id: manor_id, entries: entries}}
    else
      {:ok, %__MODULE__{castle_id: manor_id, entries: []}}
    end
  end

  def decode(_), do: {:error, :malformed}

  defp decode_entries(_bin, 0, acc), do: Enum.reverse(acc)

  defp decode_entries(
         <<item_id::little-32, amount::little-32, price::little-32, reward_type::8,
           rest::binary>>,
         count,
         acc
       )
       when item_id >= 1 and amount >= 0 and price >= 0 do
    entry = %{
      item_id: item_id,
      amount: amount,
      start_amount: amount,
      price: price,
      reward_type: reward_type,
      period: 1
    }

    decode_entries(rest, count - 1, [entry | acc])
  end

  defp decode_entries(_, _count, acc), do: Enum.reverse(acc)
end
