defmodule L2E.Packet.Client.RequestHennaRemove do
  @moduledoc """
  Opcode 0xBF — player requests to remove a dye (henna) from their character.

  Body (RequestHennaRemove.java):
    symbolId  LE-32  — the dye item's item_id (used to locate which slot to clear)

  The server scans all 3 henna slots to find the one whose dye_id matches.
  In L2 Interlude, henna removal does not refund the dye items.
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:dye_id]
  @type t :: %__MODULE__{dye_id: pos_integer()}

  @impl L2E.Packet.Decodable
  def decode(<<dye_id::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{dye_id: dye_id}}
  end

  def decode(_), do: {:error, :malformed}
end
