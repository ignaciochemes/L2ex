defmodule L2E.DB.CharacterQuest do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias L2E.Repo

  @moduledoc """
  Persistent quest state record for a character.
  Each row represents one quest a character has interacted with.
  State is upserted — no duplicate rows per (character, quest) pair.

  State values: 0 = not_started, 1 = in_progress, 2 = completed
  """

  schema "character_quests" do
    belongs_to(:character, L2E.DB.Character)
    field(:quest_id, :integer)
    field(:state, :integer, default: 0)
    field(:cond, :integer, default: 0)
    field(:count, :integer, default: 0)
    field(:reward_taken, :boolean, default: false)
    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(quest, attrs) do
    quest
    |> cast(attrs, [:character_id, :quest_id, :state, :cond, :count, :reward_taken])
    |> validate_required([:character_id, :quest_id, :state])
    |> validate_inclusion(:state, [0, 1, 2])
    |> validate_number(:cond, greater_than_or_equal_to: 0)
    |> validate_number(:count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id, :quest_id])
  end

  @spec load_for_character(integer()) :: [t()]
  def load_for_character(character_id) do
    Repo.all(from(q in __MODULE__, where: q.character_id == ^character_id))
  end

  @spec get_quest(integer(), integer()) :: {:ok, t()} | {:error, :not_found}
  def get_quest(character_id, quest_id) do
    case Repo.one(
           from(q in __MODULE__,
             where: q.character_id == ^character_id and q.quest_id == ^quest_id
           )
         ) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @spec set_quest_state(integer(), integer(), integer(), integer(), integer()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def set_quest_state(character_id, quest_id, state, cond \\ 0, count \\ 0) do
    %__MODULE__{}
    |> changeset(%{
      character_id: character_id,
      quest_id: quest_id,
      state: state,
      cond: cond,
      count: count
    })
    |> Repo.insert(
      on_conflict: :replace_all,
      conflict_target: [:character_id, :quest_id]
    )
  end

  @spec complete_quest(integer(), integer()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def complete_quest(character_id, quest_id) do
    %__MODULE__{}
    |> changeset(%{
      character_id: character_id,
      quest_id: quest_id,
      state: 2,
      reward_taken: true
    })
    |> Repo.insert(
      on_conflict: [set: [state: 2, reward_taken: true]],
      conflict_target: [:character_id, :quest_id]
    )
  end
end
