defmodule L2E.Repo.Migrations.CreateCharSkills do
  use Ecto.Migration

  def change do
    create table(:char_skills) do
      add(:char_id, references(:characters, on_delete: :delete_all), null: false)
      add(:skill_id, :integer, null: false)
      add(:level, :integer, null: false, default: 1)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:char_skills, [:char_id, :skill_id]))
    create(index(:char_skills, [:char_id]))
  end
end
