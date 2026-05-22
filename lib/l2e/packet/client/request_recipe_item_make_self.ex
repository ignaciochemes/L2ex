defmodule L2E.Packet.Client.RequestRecipeItemMakeSelf do
  @moduledoc """
  Opcode 0xAF — player crafts an item using their own recipe book.

  Body (RequestRecipeItemMakeSelf.java):
    id  LE-32  — the recipe_id to execute

  Works for both Dwarven recipes and Common recipes.
  The server validates ingredient availability, consumes them, and produces the result item.
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:recipe_id]
  @type t :: %__MODULE__{recipe_id: pos_integer()}

  @impl L2E.Packet.Decodable
  def decode(<<recipe_id::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{recipe_id: recipe_id}}
  end

  def decode(_), do: {:error, :malformed}
end
