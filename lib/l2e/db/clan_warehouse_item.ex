defmodule L2E.DB.ClanWarehouseItem do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Persistent item stored in a clan's shared warehouse.

  Soft deletes use `soft_deleted_at` field — queries exclude rows where this is non-nil.
  """

  schema "clan_warehouse_items" do
    field(:clan_id, :integer)
    field(:item_id, :integer)
    field(:count, :integer, default: 1)
    field(:enchant_level, :integer, default: 0)
    field(:soft_deleted_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:clan_id, :item_id, :count, :enchant_level, :soft_deleted_at])
    |> validate_required([:clan_id, :item_id])
    |> validate_number(:count, greater_than: 0)
  end
end
