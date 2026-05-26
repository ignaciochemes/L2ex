defmodule L2E.Repo.Migrations.CreateOlympiadHistories do
  use Ecto.Migration

  def change do
    create table(:olympiad_histories) do
      add(:cycle, :integer, null: false)
      add(:winner_char_id, :integer, null: false)
      add(:winner_char_name, :string, size: 35, null: false)
      add(:winner_class_id, :integer, null: false)
      add(:loser_char_id, :integer, null: false)
      add(:loser_char_name, :string, size: 35, null: false)
      add(:loser_class_id, :integer, null: false)
      add(:points_delta, :integer, null: false)
      add(:match_duration_s, :integer)
      timestamps()
    end

    create(index(:olympiad_histories, [:cycle]))
    create(index(:olympiad_histories, [:winner_char_id]))
    create(index(:olympiad_histories, [:loser_char_id]))
  end
end
