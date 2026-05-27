defmodule L2E.Repo.Migrations.AddEnchantLevelToCharacterSkills do
  use Ecto.Migration

  def change do
    alter table(:character_skills) do
      add(:enchant_level, :integer, default: 0, null: false)
    end
  end
end
