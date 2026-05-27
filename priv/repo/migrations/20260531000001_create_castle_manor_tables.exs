defmodule L2E.Repo.Migrations.CreateCastleManorTables do
  use Ecto.Migration

  def up do
    create table(:castle_manor_production, primary_key: false) do
      add(:castle_id, :integer, primary_key: true, null: false)
      add(:seed_id, :integer, primary_key: true, null: false)
      add(:amount, :integer, default: 0, null: false)
      add(:start_amount, :integer, default: 0, null: false)
      add(:sold, :integer, default: 0, null: false)
      add(:price, :integer, default: 0, null: false)
      add(:next_period_seed_id, :integer, default: nil)
      add(:next_period_amount, :integer, default: 0, null: false)

      timestamps()
    end

    create(index(:castle_manor_production, [:castle_id]))

    create table(:castle_manor_procure, primary_key: false) do
      add(:castle_id, :integer, primary_key: true, null: false)
      add(:item_id, :integer, primary_key: true, null: false)
      add(:amount, :integer, default: 0, null: false)
      add(:start_amount, :integer, default: 0, null: false)
      add(:reward_type, :integer, default: 0, null: false)
      add(:cost, :integer, default: 0, null: false)
      add(:next_period_item_id, :integer, default: nil)
      add(:next_period_amount, :integer, default: 0, null: false)

      timestamps()
    end

    create(index(:castle_manor_procure, [:castle_id]))
  end

  def down do
    drop(table(:castle_manor_procure))
    drop(table(:castle_manor_production))
  end
end
