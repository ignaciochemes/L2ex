defmodule L2E.DB.ManorProcure do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "castle_manor_procure" do
    field(:castle_id, :integer)
    field(:item_id, :integer)
    field(:amount, :integer, default: 0)
    field(:start_amount, :integer, default: 0)
    field(:reward_type, :integer, default: 0)
    field(:cost, :integer, default: 0)
    field(:next_period_item_id, :integer)
    field(:next_period_amount, :integer, default: 0)

    timestamps()
  end

  def changeset(rec, attrs) do
    rec
    |> cast(attrs, [
      :castle_id,
      :item_id,
      :amount,
      :start_amount,
      :reward_type,
      :cost,
      :next_period_item_id,
      :next_period_amount
    ])
    |> validate_required([:castle_id, :item_id, :amount, :cost])
  end
end
