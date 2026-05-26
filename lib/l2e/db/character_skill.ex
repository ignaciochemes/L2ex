defmodule L2E.DB.CharacterSkill do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias L2E.Repo

  @moduledoc """
  Persistent skill record for a character.
  Each row represents one skill a character has learned.
  Skill level is updated in-place via upsert — no duplicate rows per (character, skill) pair.
  """

  schema "character_skills" do
    belongs_to(:character, L2E.DB.Character)
    field(:skill_id, :integer)
    field(:skill_level, :integer, default: 1)
    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(skill, attrs) do
    skill
    |> cast(attrs, [:character_id, :skill_id, :skill_level])
    |> validate_required([:character_id, :skill_id, :skill_level])
    |> validate_number(:skill_level, greater_than: 0)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id, :skill_id])
  end

  @spec load_for_character(integer()) :: [t()]
  def load_for_character(character_id) do
    Repo.all(from(s in __MODULE__, where: s.character_id == ^character_id))
  end

  @spec upsert_skill(integer(), integer(), integer()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def upsert_skill(character_id, skill_id, skill_level) do
    %__MODULE__{}
    |> changeset(%{character_id: character_id, skill_id: skill_id, skill_level: skill_level})
    |> Repo.insert(
      on_conflict: [set: [skill_level: skill_level]],
      conflict_target: [:character_id, :skill_id]
    )
  end

  @doc """
  Replaces all skills for a character with the given skills map.
  Used when switching sub-classes so that the next login loads the correct skill set.
  """
  @spec replace_for_character(integer(), %{integer() => integer()}) :: :ok
  def replace_for_character(character_id, skills) do
    Repo.transaction(fn ->
      Repo.delete_all(from(s in __MODULE__, where: s.character_id == ^character_id))

      Enum.each(skills, fn {skill_id, level} ->
        upsert_skill(character_id, skill_id, level)
      end)
    end)

    :ok
  end
end
