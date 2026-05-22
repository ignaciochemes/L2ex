defmodule L2E.Repo.Migrations.CreateCharacterSkills do
  use Ecto.Migration

  def change do
    create table(:character_skills) do
      add(:character_id, :integer, null: false)
      add(:skill_id, :integer, null: false)
      add(:skill_level, :integer, null: false, default: 1)
      timestamps(type: :utc_datetime)
    end

    create(index(:character_skills, [:character_id]))
    create(unique_index(:character_skills, [:character_id, :skill_id]))
  end
end
