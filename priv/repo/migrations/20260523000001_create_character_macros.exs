defmodule L2E.Repo.Migrations.CreateCharacterMacros do
  use Ecto.Migration

  def change do
    create table(:character_macros) do
      add(:character_id, :integer, null: false)
      add(:macro_id, :integer, null: false)
      add(:icon, :integer, default: 0)
      add(:name, :string, size: 32, null: false, default: "")
      add(:descr, :string, size: 128, default: "")
      add(:keybind, :string, size: 64, default: "")
      add(:commands, :text, default: "")
    end

    create(unique_index(:character_macros, [:character_id, :macro_id]))
    create(index(:character_macros, [:character_id]))
  end
end
