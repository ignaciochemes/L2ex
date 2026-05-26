defmodule L2E.Repo.Migrations.CreateHeroes do
  use Ecto.Migration

  def change do
    create table(:heroes, primary_key: false) do
      add :char_id, :integer, primary_key: true, null: false
      add :char_name, :string, size: 35, null: false
      add :class_id, :integer, null: false
      add :elected_at, :utc_datetime, null: false, default: fragment("now()")
      add :is_active, :boolean, null: false, default: true

      timestamps()
    end
  end
end
