defmodule L2E.Repo.Migrations.CreateGlobalVariables do
  use Ecto.Migration

  def change do
    create table(:global_variables, primary_key: false) do
      add(:name, :string, primary_key: true)
      add(:value, :text, null: false, default: "")
      timestamps()
    end
  end
end
