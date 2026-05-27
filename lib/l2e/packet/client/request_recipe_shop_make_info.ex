defmodule L2E.Packet.Client.RequestRecipeShopMakeInfo do
  @moduledoc """
  Opcode 0xB5 — Buyer queries recipe info from a crafting stall.

  Body (RequestRecipeShopMakeInfo.java):
    player_object_id  LE-32  — object ID of the shop owner
    recipe_id         LE-32  — recipe the buyer wants to inspect

  Server responds with RecipeShopItemInfo (0xDA).
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:shop_object_id, :recipe_id]
  @type t :: %__MODULE__{shop_object_id: pos_integer(), recipe_id: pos_integer()}

  @impl L2E.Packet.Decodable
  def decode(<<shop_oid::little-32, recipe_id::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{shop_object_id: shop_oid, recipe_id: recipe_id}}
  end

  def decode(_), do: {:error, :malformed}
end
