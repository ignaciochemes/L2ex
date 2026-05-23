defmodule L2E.Repo.Migrations.CreateSevenSigns do
  use Ecto.Migration

  def change do
    # Per-player SSQ participation data
    create table(:seven_signs_players) do
      add :character_id, :integer, null: false
      add :cabal, :string, size: 8, default: "none"   # "dawn" | "dusk" | "none"
      add :contribution_score, :integer, default: 0
      add :bluestone_count, :integer, default: 0       # Ancient Adena stones
      add :greenstone_count, :integer, default: 0
      add :redstone_count, :integer, default: 0
      add :accumulated_adena, :bigint, default: 0
      add :registered_period, :integer, default: 0    # period number when registered
    end

    create unique_index(:seven_signs_players, [:character_id])

    # Server-wide SSQ state (one row, id = 1)
    create table(:seven_signs_state) do
      add :current_period, :integer, default: 1        # 1 = Competition, 2 = Seal Validation
      add :current_cycle, :integer, default: 1
      add :dawn_score, :bigint, default: 0
      add :dusk_score, :bigint, default: 0
      add :dawn_stones, :bigint, default: 0
      add :dusk_stones, :bigint, default: 0
      # Seals: :seal_of_avarice, :seal_of_gnosis, :seal_of_strife
      add :seal_avarice_owner, :string, size: 8, default: "none"   # "dawn" | "dusk" | "none"
      add :seal_gnosis_owner, :string, size: 8, default: "none"
      add :seal_strife_owner, :string, size: 8, default: "none"
      add :period_start_ms, :bigint, default: 0
    end
  end
end
