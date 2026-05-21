defmodule L2E.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items) do
      add(:char_id, references(:characters, on_delete: :delete_all), null: false)
      add(:item_id, :integer, null: false)
      add(:count, :integer, null: false, default: 1)
      add(:enchant_level, :integer, null: false, default: 0)
      add(:is_equipped, :boolean, null: false, default: false)
      add(:slot, :string)

      timestamps(type: :utc_datetime)
    end

    create(index(:items, [:char_id]))
  end
end
