defmodule L2E.DB.ClanWarehouseItem do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Persistent item stored in a clan's shared warehouse.
  """

  schema "clan_warehouse_items" do
    field(:clan_id, :integer)
    field(:item_id, :integer)
    field(:count, :integer, default: 1)
    field(:enchant_level, :integer, default: 0)
    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:clan_id, :item_id, :count, :enchant_level])
    |> validate_required([:clan_id, :item_id])
    |> validate_number(:count, greater_than: 0)
  end
end
