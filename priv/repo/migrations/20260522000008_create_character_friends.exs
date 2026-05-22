defmodule L2E.Repo.Migrations.CreateCharacterFriends do
  use Ecto.Migration

  def up do
    create table(:character_friends) do
      add(:char_id, :integer, null: false)
      add(:friend_id, :integer, null: false)
      add(:friend_name, :string, null: false, default: "")

      timestamps()
    end

    create(index(:character_friends, [:char_id]))
    create(index(:character_friends, [:friend_id]))
    create(unique_index(:character_friends, [:char_id, :friend_id]))
  end

  def down do
    drop(table(:character_friends))
  end
end
