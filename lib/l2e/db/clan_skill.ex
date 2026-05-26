defmodule L2E.DB.ClanSkill do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "clan_skills" do
    belongs_to(:clan, L2E.DB.Clan, foreign_key: :clan_id)
    field(:skill_id, :integer)
    field(:skill_level, :integer, default: 1)
    timestamps()
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:clan_id, :skill_id, :skill_level])
    |> validate_required([:clan_id, :skill_id])
    |> unique_constraint([:clan_id, :skill_id])
  end
end
