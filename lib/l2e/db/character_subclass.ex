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
end
