defmodule L2E.Repo.Migrations.CreateClanWarehouseItems do
  use Ecto.Migration

  def change do
    create table(:clan_warehouse_items) do
      add(:clan_id, :integer, null: false)
      add(:item_id, :integer, null: false)
      add(:count, :integer, null: false, default: 1)
      add(:enchant_level, :integer, null: false, default: 0)
      timestamps(type: :utc_datetime)
    end

    create(index(:clan_warehouse_items, [:clan_id]))
  end
end
