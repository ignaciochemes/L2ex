defmodule L2E.Repo.Migrations.CreateClans do
  use Ecto.Migration

  def change do
    create table(:clans) do
      add(:name, :string, null: false)
      add(:leader_id, :integer, null: false)
      add(:description, :text)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:clans, [:name]))
    create(index(:clans, [:leader_id]))
  end
end
