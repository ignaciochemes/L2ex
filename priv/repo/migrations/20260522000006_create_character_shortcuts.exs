defmodule L2E.Repo.Migrations.CreateCharacterShortcuts do
  use Ecto.Migration

  def change do
    create table(:character_shortcuts) do
      add :char_id, :integer, null: false
      add :slot, :integer, null: false
      add :page, :integer, null: false, default: 0
      add :type, :integer, null: false
      add :shortcut_id, :integer, null: false
      add :level, :integer, null: false, default: 1
    end

    create index(:character_shortcuts, [:char_id])
    create unique_index(:character_shortcuts, [:char_id, :slot, :page])
  end
end
