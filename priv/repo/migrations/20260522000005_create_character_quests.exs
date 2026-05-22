defmodule L2E.Repo.Migrations.CreateCharacterQuests do
  use Ecto.Migration

  def change do
    create table(:character_quests) do
      add(:character_id, :integer, null: false)
      add(:quest_id, :integer, null: false)
      add(:state, :integer, null: false, default: 0)
      add(:cond, :integer, null: false, default: 0)
      add(:count, :integer, null: false, default: 0)
      add(:reward_taken, :boolean, null: false, default: false)
      timestamps(type: :utc_datetime)
    end

    create(index(:character_quests, [:character_id]))
    create(unique_index(:character_quests, [:character_id, :quest_id]))
  end

  def down do
    drop(table(:character_quests))
  end
end
