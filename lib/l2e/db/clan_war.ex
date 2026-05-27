defmodule L2E.DB.ClanWar do
  use Ecto.Schema
  import Ecto.Changeset

  schema "clan_wars" do
    field(:attacker_clan_id, :integer)
    field(:defender_clan_id, :integer)
    field(:attacker_kills, :integer, default: 0)
    field(:defender_kills, :integer, default: 0)
    # "declared" = attacker declared, waiting for defender response
    # "mutual"   = both sides declared (full war)
    # "ended"    = surrendered or time-limited end
    field(:state, :string, default: "declared")
    timestamps()
  end

  def changeset(clan_war, attrs) do
    clan_war
    |> cast(attrs, [
      :attacker_clan_id,
      :defender_clan_id,
      :attacker_kills,
      :defender_kills,
      :state
    ])
    |> validate_required([:attacker_clan_id, :defender_clan_id])
    |> unique_constraint([:attacker_clan_id, :defender_clan_id])
  end
end
