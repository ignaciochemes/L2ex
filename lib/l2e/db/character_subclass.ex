defmodule L2E.DB.CharacterSubclass do
  use Ecto.Schema
  import Ecto.Query

  alias L2E.Repo

  schema "character_subclasses" do
    field(:char_id, :integer)
    field(:class_id, :integer)
    field(:class_index, :integer)
    field(:level, :integer, default: 40)
    field(:exp, :integer, default: 0)
    field(:sp, :integer, default: 0)
    field(:skills_json, :string)

    timestamps()
  end

  @doc "Load all sub-classes for a character, ordered by class_index."
  def load_for_character(char_id) do
    Repo.all(
      from(s in __MODULE__,
        where: s.char_id == ^char_id,
        order_by: [asc: s.class_index]
      )
    )
  end

  @doc "Add a new sub-class for a character."
  def add(char_id, class_id, class_index) do
    %__MODULE__{
      char_id: char_id,
      class_id: class_id,
      class_index: class_index,
      level: 40,
      exp: 0,
      sp: 0
    }
    |> Repo.insert()
  end

  @doc "Save current sub-class progress (level, exp, sp)."
  def save(char_id, class_index, level, exp, sp) do
    case Repo.get_by(__MODULE__, char_id: char_id, class_index: class_index) do
      nil ->
        {:error, :not_found}

      subclass ->
        subclass
        |> Ecto.Changeset.change(level: level, exp: exp, sp: sp)
        |> Repo.update()
    end
  end

  @doc "Remove a sub-class by class_index."
  def remove(char_id, class_index) do
    case Repo.get_by(__MODULE__, char_id: char_id, class_index: class_index) do
      nil -> {:error, :not_found}
      subclass -> Repo.delete(subclass)
    end
  end

  @doc "Save skill snapshot for a sub-class slot. Silently ignores if record not found."
  def save_skills(char_id, class_index, skills) do
    case Repo.get_by(__MODULE__, char_id: char_id, class_index: class_index) do
      nil ->
        {:error, :not_found}

      subclass ->
        subclass
        |> Ecto.Changeset.change(skills_json: serialize_skills(skills))
        |> Repo.update()
    end
  end

  @doc "Load skill snapshot for a sub-class slot. Returns skills map or nil if not saved yet."
  def load_skills(char_id, class_index) do
    case Repo.get_by(__MODULE__, char_id: char_id, class_index: class_index) do
      %{skills_json: json} when is_binary(json) -> deserialize_skills(json)
      _ -> nil
    end
  end

  # ---- Private serialization ------------------------------------------------

  defp serialize_skills(skills) do
    skills
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end

  defp deserialize_skills(b64) do
    try do
      b64
      |> Base.decode64!()
      |> :erlang.binary_to_term([:safe])
    rescue
      _ -> nil
    end
  end
end
