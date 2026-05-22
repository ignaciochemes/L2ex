defmodule L2E.DB.WarehouseItem do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Persistent item stored in a character's private warehouse.
  """

  schema "warehouse_items" do
    field(:char_id, :integer)
    field(:item_id, :integer)
    field(:count, :integer, default: 1)
    field(:enchant_level, :integer, default: 0)
    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:char_id, :item_id, :count, :enchant_level])
    |> validate_required([:char_id, :item_id])
    |> validate_number(:count, greater_than: 0)
  end
end
