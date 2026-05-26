defmodule L2E.Repo.Migrations.CreateRaidBossState do
  use Ecto.Migration

  def change do
    create table(:raid_boss_state, primary_key: false) do
      add :boss_id, :integer, primary_key: true
      add :state, :string, null: false, default: "alive"
      add :respawn_time, :bigint, null: false, default: 0
      timestamps()
    end
  end
end
