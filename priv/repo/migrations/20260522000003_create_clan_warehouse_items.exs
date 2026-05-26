defmodule L2E.Repo.Migrations.CreateClanWarehouseItems do
  use Ecto.Migration

  def change do
    create table(:clan_warehouse_items) do
      add(:clan_id, references(:clans, on_delete: :delete_all), null: false)
      add(:item_id, :integer, null: false)
      add(:count, :integer, null: false, default: 1)
      add(:enchant_level, :integer, null: false, default: 0)
      add(:soft_deleted_at, :utc_datetime_usec, default: nil)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:clan_warehouse_items, [:clan_id, :item_id]))
    create(index(:clan_warehouse_items, [:clan_id, :soft_deleted_at]))
  end
end
