defmodule L2E.Packet.Client.RequestSetSeed do
  @moduledoc """
  Extended opcode 0xD0/0x0A — Sent by the castle lord to set seed production for a castle manor.

  Wire order (RequestSetSeed.java):
    manor_id  : readInt()   — castle/manor ID
    count     : readInt()   — number of entries
    per entry (12 bytes each):
      seed_id : readInt()   — item ID of the seed
      amount  : readInt()   — amount to produce (start_amount)
      price   : readInt()   — selling price per seed
  """
  @behaviour L2E.Packet.Decodable

  defstruct castle_id: 0, entries: []

  @type entry :: %{
          seed_id: integer(),
          amount: integer(),
          start_amount: integer(),
          price: integer()
        }
  @type t :: %__MODULE__{castle_id: integer(), entries: [entry()]}

  @batch_length 12

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
         <<seed_id::little-32, amount::little-32, price::little-32, rest::binary>>,
         count,
         acc
       )
       when seed_id >= 1 and amount >= 0 and price >= 0 do
    entry = %{seed_id: seed_id, amount: amount, start_amount: amount, price: price, period: 1}
    decode_entries(rest, count - 1, [entry | acc])
  end

  defp decode_entries(_, _count, acc), do: Enum.reverse(acc)
end
