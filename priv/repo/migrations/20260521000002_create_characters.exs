defmodule L2E.Repo.Migrations.CreateCharacters do
  use Ecto.Migration

  def change do
    create table(:characters) do
      add(:account_name, :string, null: false, size: 32)
      add(:name, :string, null: false, size: 16)
      add(:race, :integer, null: false, default: 0)
      add(:sex, :integer, null: false, default: 0)
      add(:class_id, :integer, null: false, default: 0)
      add(:level, :integer, null: false, default: 1)
      add(:exp, :bigint, null: false, default: 0)
      add(:sp, :integer, null: false, default: 0)
      add(:hp, :float, null: false, default: 100.0)
      add(:mp, :float, null: false, default: 100.0)
      add(:max_hp, :float, null: false, default: 100.0)
      add(:max_mp, :float, null: false, default: 100.0)
      add(:x, :integer, null: false, default: -71338)
      add(:y, :integer, null: false, default: 258_271)
      add(:z, :integer, null: false, default: -3104)
      add(:heading, :integer, null: false, default: 0)
      add(:hair_style, :integer, null: false, default: 0)
      add(:hair_color, :integer, null: false, default: 0)
      add(:face, :integer, null: false, default: 0)
      add(:last_access, :utc_datetime)
      timestamps(type: :utc_datetime)
    end

    create(unique_index(:characters, [:name]))
    create(index(:characters, [:account_name]))
  end
end
