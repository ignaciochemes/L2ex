defmodule L2E.Packet.Client.RequestSaveInventoryOrder do
  @moduledoc """
  Client request to save the player's custom inventory item order.

  Body (RequestSaveInventoryOrder.java):
    count       LE-32       number of entries (client caps at 125)
    [count × (
      object_id LE-32       item instance object ID
      order     LE-32       display order index
    )]

  ⚠️ This packet has no registered opcode in CT0 Interlude ClientPackets.java.
  The struct is defined here for completeness; do NOT add a decoder entry until
  the opcode is confirmed against the live client.

  Reference: RequestSaveInventoryOrder.java (not registered in CT0 ClientPackets enum)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:orders]

  @type order_entry :: {object_id :: pos_integer(), order :: non_neg_integer()}
  @type t :: %__MODULE__{
          orders: [order_entry()]
        }

  @limit 125

  @impl L2E.Packet.Decodable
  def decode(<<count::little-32, rest::binary>>) do
    effective = min(count, @limit)

    case read_pairs(rest, effective, []) do
      {:ok, pairs} -> {:ok, %__MODULE__{orders: pairs}}
      :error -> {:error, :malformed}
    end
  end

  def decode(_), do: {:error, :malformed}

  defp read_pairs(_, 0, acc), do: {:ok, Enum.reverse(acc)}

  defp read_pairs(<<object_id::little-32, order::little-32, rest::binary>>, n, acc) do
    read_pairs(rest, n - 1, [{object_id, order} | acc])
  end

  defp read_pairs(_, _, _), do: :error
end
