defmodule L2E.DB.ManorProduction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "castle_manor_production" do
    field(:castle_id, :integer)
    field(:seed_id, :integer)
    field(:amount, :integer, default: 0)
    field(:start_amount, :integer, default: 0)
    field(:sold, :integer, default: 0)
    field(:price, :integer, default: 0)
    field(:next_period_seed_id, :integer)
    field(:next_period_amount, :integer, default: 0)

    timestamps()
  end

  def changeset(rec, attrs) do
    rec
    |> cast(attrs, [
      :castle_id,
      :seed_id,
      :amount,
      :start_amount,
      :sold,
      :price,
      :next_period_seed_id,
      :next_period_amount
    ])
    |> validate_required([:castle_id, :seed_id, :amount, :price])
  end
end
