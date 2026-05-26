defmodule L2E.DB.ClanHall do
  @moduledoc """
  Persistent clan hall record.
  hall_id identifies the physical hall; clan_id = 0 means no owner (auctionable).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "clan_halls" do
    field(:hall_id, :integer)
    field(:hall_name, :string)
    field(:clan_id, :integer, default: 0)
    field(:auction_end_date, :utc_datetime)
    field(:min_bid, :integer, default: 100_000)
    field(:paid_until, :utc_datetime)
    field(:is_paid, :boolean, default: true)
    timestamps()
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [
      :hall_id,
      :hall_name,
      :clan_id,
      :auction_end_date,
      :min_bid,
      :paid_until,
      :is_paid
    ])
    |> validate_required([:hall_id, :hall_name])
    |> unique_constraint(:hall_id)
  end
end
