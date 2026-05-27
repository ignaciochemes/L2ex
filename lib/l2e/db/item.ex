defmodule L2E.DB.Item do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Persistent item instance record.
  One row per item slot in a character's inventory.
  `id` doubles as the L2 object_id sent to the game client.
  """

  schema "items" do
    field(:char_id, :integer)
    field(:item_id, :integer)
    field(:count, :integer, default: 1)
    field(:enchant_level, :integer, default: 0)
    field(:is_equipped, :boolean, default: false)
    field(:slot, :string)
    field(:soul_type, :integer, default: 0)
    field(:soul_level, :integer, default: 0)
    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :char_id,
      :item_id,
      :count,
      :enchant_level,
      :is_equipped,
      :slot,
      :soul_type,
      :soul_level
    ])
    |> validate_required([:char_id, :item_id])
    |> validate_number(:count, greater_than: 0)
  end
end
