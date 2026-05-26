defmodule L2E.Repo.Migrations.CreatePetInventoryItems do
  use Ecto.Migration

  def change do
    create table(:pet_inventory_items) do
      # the pet's collar item object id
      add(:pet_item_obj_id, :integer, null: false)
      # owner's character id
      add(:char_id, :integer, null: false)
      # item template id
      add(:item_id, :integer, null: false)
      # item object id
      add(:object_id, :integer, null: false)
      add(:count, :integer, default: 1, null: false)
      add(:enchant_level, :integer, default: 0)
      # paperdoll slot, 0 = not equipped
      add(:slot, :integer, default: 0)
      timestamps()
    end

    create(index(:pet_inventory_items, [:pet_item_obj_id]))
    create(index(:pet_inventory_items, [:char_id]))
    create(unique_index(:pet_inventory_items, [:object_id]))
  end
end
