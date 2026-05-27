defmodule L2E.Packet.Client.RequestRecipeShopManageQuit do
  @moduledoc """
  Opcode 0xB3 — Dwarf player closes their crafting stall management UI.

  Body: none.
  The server clears the player's recipe shop state.
  """
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end
