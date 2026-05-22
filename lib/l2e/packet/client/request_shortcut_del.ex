defmodule L2E.Packet.Client.RequestShortcutDel do
  @moduledoc """
  Opcode 0x35 — client deletes a shortcut from the action bar.

  Body (RequestShortcutDel.java):
    page_slot  LE-32   (slot = page_slot % 12, page = page_slot / 12)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:slot, :page]

  @type t :: %__MODULE__{
          slot: non_neg_integer(),
          page: non_neg_integer()
        }

  @impl L2E.Packet.Decodable
  def decode(<<page_slot::little-32, _::binary>>) do
    {:ok,
     %__MODULE__{
       slot: rem(page_slot, 12),
       page: div(page_slot, 12)
     }}
  end

  def decode(_), do: {:error, :malformed}
end
