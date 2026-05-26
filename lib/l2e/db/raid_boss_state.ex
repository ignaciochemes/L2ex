defmodule L2E.DB.RaidBossState do
  use Ecto.Schema

  @primary_key {:boss_id, :integer, []}
  schema "raid_boss_state" do
    field :state, :string, default: "alive"
    field :respawn_time, :integer, default: 0
    timestamps()
  end
end
