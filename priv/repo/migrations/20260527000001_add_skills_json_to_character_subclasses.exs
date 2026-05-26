defmodule L2E.Repo.Migrations.AddSkillsJsonToCharacterSubclasses do
  use Ecto.Migration

  def change do
    alter table(:character_subclasses) do
      add(:skills_json, :text, null: true)
    end
  end
end
