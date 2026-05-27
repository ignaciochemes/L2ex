defmodule L2E.Repo.Migrations.CreateClanWars do
  use Ecto.Migration

  def change do
    create table(:clan_wars) do
      add(:attacker_clan_id, :integer, null: false)
      add(:defender_clan_id, :integer, null: false)
      add(:attacker_kills, :integer, default: 0)
      add(:defender_kills, :integer, default: 0)
      add(:state, :string, default: "declared")
      timestamps()
    end

    create(unique_index(:clan_wars, [:attacker_clan_id, :defender_clan_id]))
  end
end
