defmodule L2E.Repo.Migrations.AddSoulCrystalFields do
  use Ecto.Migration

  def change do
    alter table(:items) do
      add(:soul_type, :integer, default: 0)
      add(:soul_level, :integer, default: 0)
    end
  end
end
