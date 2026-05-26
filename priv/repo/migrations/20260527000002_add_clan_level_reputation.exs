defmodule L2E.Repo.Migrations.AddClanLevelReputation do
  use Ecto.Migration

  def change do
    alter table(:clans) do
      add(:level, :integer, default: 1, null: false)
      add(:reputation_points, :integer, default: 0, null: false)
      add(:castle_id, :integer, default: 0, null: false)
      add(:clan_hall_id, :integer, default: 0, null: false)
    end

    create table(:clan_skills, primary_key: false) do
      add(:clan_id, references(:clans), null: false)
      add(:skill_id, :integer, null: false)
      add(:skill_level, :integer, default: 1, null: false)
      timestamps()
    end

    create(unique_index(:clan_skills, [:clan_id, :skill_id]))
  end
end
