defmodule L2E.Repo.Migrations.CreateClanCrests do
  use Ecto.Migration

  def change do
    create table(:clan_crests, primary_key: false) do
      add(:clan_id, :integer, primary_key: true, null: false)
      add(:crest_data, :binary)
      add(:large_crest_data, :binary)

      timestamps()
    end
  end
end
