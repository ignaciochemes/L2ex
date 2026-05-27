defmodule L2E.Packet.Client.RequestRecipeShopMakeItem do
  @moduledoc """
  Opcode 0xB6 — Buyer requests that a recipe stall owner crafts an item for them.

  Body (RequestRecipeShopMakeItem.java):
    manufacturer_id  LE-32  — object ID of the shop owner
    recipe_id        LE-32  — recipe to execute
    unknown          LE-32  — unused in Java reference (padding)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:shop_object_id, :recipe_id]
  @type t :: %__MODULE__{shop_object_id: pos_integer(), recipe_id: pos_integer()}

  @impl L2E.Packet.Decodable
  def decode(<<shop_oid::little-32, recipe_id::little-32, _unknown::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{shop_object_id: shop_oid, recipe_id: recipe_id}}
  end

  def decode(_), do: {:error, :malformed}
end
