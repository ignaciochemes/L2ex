defmodule L2E.DB.Clan do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Persistent clan record. Stores clan metadata: name, leader, description.

  Game logic (invites, members, etc.) lives in the L2E.Clan GenServer.
  """

  schema "clans" do
    field(:name, :string)
    field(:leader_id, :integer)
    field(:description, :string)
    has_many(:warehouse_items, L2E.DB.ClanWarehouseItem, foreign_key: :clan_id)
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(clan, attrs) do
    clan
    |> cast(attrs, [:name, :leader_id, :description])
    |> validate_required([:name, :leader_id])
    |> validate_length(:name, min: 1, max: 32)
    |> unique_constraint(:name)
  end
end
