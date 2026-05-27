defmodule L2E.Packet.Client.RequestRecipeShopListSet do
  @moduledoc """
  Opcode 0xB2 — Dwarf player confirms their crafting stall recipe list.

  Body (RequestRecipeShopListSet.java):
    count      LE-32  — number of items (8 bytes each)
    per item:
      recipe_id  LE-32
      cost       LE-32  — max fee the player will accept for this recipe

  After this packet the server sets the player's store type to MANUFACTURE
  and broadcasts RecipeShopMsg to nearby players.
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:recipes]
  @type t :: %__MODULE__{recipes: [{pos_integer(), pos_integer()}]}

  @impl L2E.Packet.Decodable
  def decode(<<count::little-32, rest::binary>>) do
    case decode_items(rest, count, []) do
      {:ok, items} -> {:ok, %__MODULE__{recipes: items}}
      err -> err
    end
  end

  def decode(_), do: {:error, :malformed}

  defp decode_items(_bin, 0, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_items(<<recipe_id::little-32, cost::little-32, rest::binary>>, n, acc) do
    decode_items(rest, n - 1, [{recipe_id, cost} | acc])
  end

  defp decode_items(_, _, _), do: {:error, :malformed}
end
