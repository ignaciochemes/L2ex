defmodule L2E.Packet.Client.RequestHennaEquip do
  @moduledoc """
  Opcode 0xBC — player requests to engrave a dye (henna) onto their character.

  Body (RequestHennaEquip.java):
    symbolId  LE-32  — the dye item's item_id (dye to consume)

  In L2J Interlude, _symbolId is matched against henna.getDyeId() to find the
  henna definition. The item in inventory is consumed on success.
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
