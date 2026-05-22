defmodule L2E.Repo.Migrations.CreateWarehouseItems do
  use Ecto.Migration

  def change do
    create table(:warehouse_items) do
      add(:char_id, :bigint, null: false)
      add(:item_id, :integer, null: false)
      add(:count, :bigint, default: 1, null: false)
      add(:enchant_level, :integer, default: 0, null: false)

      timestamps()
    end

    create(index(:warehouse_items, [:char_id]))
  end
end
