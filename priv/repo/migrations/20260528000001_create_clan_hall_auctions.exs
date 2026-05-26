defmodule L2E.Repo.Migrations.CreateClanHallAuctions do
  use Ecto.Migration

  def change do
    create table(:clan_halls) do
      add(:hall_id, :integer, null: false)
      add(:hall_name, :string, null: false)
      add(:clan_id, :integer, default: 0, null: false)
      add(:auction_end_date, :utc_datetime)
      add(:min_bid, :integer, default: 100_000, null: false)
      add(:paid_until, :utc_datetime)
      add(:is_paid, :boolean, default: true, null: false)
      timestamps()
    end

    create(unique_index(:clan_halls, [:hall_id]))

    create table(:clan_hall_bids) do
      add(:hall_id, :integer, null: false)
      add(:clan_id, :integer, null: false)
      add(:bid_amount, :integer, null: false)
      add(:bidder_char_id, :integer, null: false)
      add(:bid_date, :utc_datetime, null: false)
      timestamps()
    end

    create(index(:clan_hall_bids, [:hall_id]))
    create(unique_index(:clan_hall_bids, [:hall_id, :clan_id]))
  end
end
