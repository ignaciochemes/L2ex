defmodule L2E.Repo.Migrations.AddAccessLevelToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add(:access_level, :integer, default: 0, null: false)
    end
  end
end
