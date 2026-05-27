defmodule L2E.DB.ClanCrest do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:clan_id, :integer, autogenerate: false}
  schema "clan_crests" do
    field(:crest_data, :binary)
    field(:large_crest_data, :binary)
    timestamps()
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:clan_id, :crest_data, :large_crest_data])
    |> validate_required([:clan_id])
  end
end
