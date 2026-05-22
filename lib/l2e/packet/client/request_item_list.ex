defmodule L2E.Packet.Client.RequestItemList do
  @moduledoc """
  Opcode 0x0F — sent by client to request a full refresh of the inventory list.

  Body: empty (no fields).

  Reference: RequestItemList.java — REQUEST_ITEM_LIST(0x0F, ...)
  """
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end
