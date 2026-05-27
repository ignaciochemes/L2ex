defmodule L2E.Packet.Client.RequestRecipeShopManageList do
  @moduledoc """
  Opcode 0xB0 — Dwarf player opens their recipe shop manage UI.

  Body: none (no fields after opcode).
  Server responds with RecipeShopManageList (0xD8).
  """
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end
