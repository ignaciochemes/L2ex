defmodule L2E.Repo.Migrations.AddKarmaToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      add(:karma, :integer, default: 0, null: false)
      add(:pvp_kills, :integer, default: 0, null: false)
      add(:pk_kills, :integer, default: 0, null: false)
    end
  end
end
