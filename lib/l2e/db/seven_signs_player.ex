defmodule L2E.DB.SevenSignsPlayer do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "seven_signs_players" do
    field(:character_id, :integer)
    field(:cabal, :string, default: "none")
    field(:contribution_score, :integer, default: 0)
    field(:bluestone_count, :integer, default: 0)
    field(:greenstone_count, :integer, default: 0)
    field(:redstone_count, :integer, default: 0)
    field(:accumulated_adena, :integer, default: 0)
    field(:registered_period, :integer, default: 0)
  end

  def changeset(rec, attrs) do
    rec
    |> cast(attrs, [
      :character_id,
      :cabal,
      :contribution_score,
      :bluestone_count,
      :greenstone_count,
      :redstone_count,
      :accumulated_adena,
      :registered_period
    ])
    |> validate_required([:character_id])
    |> validate_inclusion(:cabal, ["dawn", "dusk", "none"])
  end
end
