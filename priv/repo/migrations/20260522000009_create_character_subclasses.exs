defmodule L2E.Repo.Migrations.CreateCharacterSubclasses do
  use Ecto.Migration

  def change do
    create table(:character_subclasses) do
      add :char_id, :integer, null: false
      add :class_id, :integer, null: false
      add :class_index, :integer, null: false, default: 1  # 1-3 for sub-classes
      add :level, :integer, null: false, default: 40
      add :exp, :bigint, null: false, default: 0
      add :sp, :bigint, null: false, default: 0

      timestamps()
    end

    create index(:character_subclasses, [:char_id])
    create unique_index(:character_subclasses, [:char_id, :class_index])
  end
end
