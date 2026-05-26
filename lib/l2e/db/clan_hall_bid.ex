defmodule L2E.DB.ClanHallBid do
  @moduledoc """
  Bid record for clan hall auction.
  One bid per clan per hall; higher bid replaces lower bid (upsert).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "clan_hall_bids" do
    field(:hall_id, :integer)
    field(:clan_id, :integer)
    field(:bid_amount, :integer)
    field(:bidder_char_id, :integer)
    field(:bid_date, :utc_datetime)
    timestamps()
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:hall_id, :clan_id, :bid_amount, :bidder_char_id, :bid_date])
    |> validate_required([:hall_id, :clan_id, :bid_amount, :bidder_char_id, :bid_date])
  end
end
