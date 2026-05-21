defmodule L2E.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add(:username, :string, null: false, size: 32)
      add(:password_hash, :string, null: false)
      timestamps(type: :utc_datetime)
    end

    create(unique_index(:accounts, [:username]))
  end
end
