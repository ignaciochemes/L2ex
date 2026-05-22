defmodule L2E.DB.Character do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Persistent character record. Holds position, stats, and appearance.
  Game logic (combat, movement validation, etc.) stays in PlayerSession.

  Characters are keyed by account_name (denormalised string) to avoid
  requiring a JOIN on every char-select screen load.
  """

  schema "characters" do
    field(:account_name, :string)
    field(:name, :string)
    field(:race, :integer, default: 0)
    field(:sex, :integer, default: 0)
    field(:class_id, :integer, default: 0)
    field(:level, :integer, default: 1)
    field(:exp, :integer, default: 0)
    field(:sp, :integer, default: 0)
    field(:hp, :float, default: 100.0)
    field(:mp, :float, default: 100.0)
    field(:max_hp, :float, default: 100.0)
    field(:max_mp, :float, default: 100.0)
    field(:x, :integer, default: -71338)
    field(:y, :integer, default: 258_271)
    field(:z, :integer, default: -3104)
    field(:heading, :integer, default: 0)
    field(:hair_style, :integer, default: 0)
    field(:hair_color, :integer, default: 0)
    field(:face, :integer, default: 0)
    field(:karma, :integer, default: 0)
    field(:pvp_kills, :integer, default: 0)
    field(:pk_kills, :integer, default: 0)
    field(:last_access, :utc_datetime)
    timestamps(type: :utc_datetime)
    has_many(:skills, L2E.DB.CharacterSkill)
    has_many(:quests, L2E.DB.CharacterQuest)
  end

  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :account_name,
      :name,
      :race,
      :sex,
      :class_id,
      :hair_style,
      :hair_color,
      :face,
      :x,
      :y,
      :z
    ])
    |> validate_required([:account_name, :name, :race, :sex, :class_id])
    |> validate_length(:name, min: 1, max: 16)
    |> validate_format(:name, ~r/^[A-Za-z][A-Za-z0-9]*$/)
    |> unique_constraint(:name)
    |> put_starting_position()
  end

  @spec update_position_changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def update_position_changeset(%__MODULE__{} = char, attrs) do
    char
    |> cast(attrs, [:x, :y, :z, :heading, :hp, :mp, :last_access])
  end

  # Resolve starting world position from race if not explicitly set.
  defp put_starting_position(%Ecto.Changeset{} = cs) do
    if get_change(cs, :x) do
      cs
    else
      race = get_field(cs, :race, 0)
      {x, y, z} = starting_position(race)
      cs |> put_change(:x, x) |> put_change(:y, y) |> put_change(:z, z)
    end
  end

  # L2 Interlude starting positions per race
  @spec starting_position(non_neg_integer()) :: {integer(), integer(), integer()}
  # Human
  def starting_position(0), do: {-71338, 258_271, -3104}
  # Elf
  def starting_position(1), do: {46578, 41678, -3411}
  # Dark Elf
  def starting_position(2), do: {28365, 14223, -4207}
  # Orc
  def starting_position(3), do: {-56763, -113_549, -672}
  # Dwarf
  def starting_position(4), do: {106_077, -109_247, -3232}
  # default Human
  def starting_position(_), do: {-71338, 258_271, -3104}
end
