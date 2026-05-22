defmodule L2E.Repo.Migrations.AddHennasToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      add(:henna1, :integer, null: true)
      add(:henna2, :integer, null: true)
      add(:henna3, :integer, null: true)
    end
  end
end
