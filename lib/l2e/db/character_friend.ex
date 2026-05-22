defmodule L2E.DB.CharacterFriend do
  @moduledoc "Persistent friend list entry linking two characters."

  use Ecto.Schema
  import Ecto.Query

  alias L2E.Repo

  schema "character_friends" do
    field(:char_id, :integer)
    field(:friend_id, :integer)
    field(:friend_name, :string)

    timestamps()
  end

  @doc "Add a friend entry."
  def add(char_id, friend_id, friend_name) do
    %__MODULE__{}
    |> Ecto.Changeset.cast(
      %{char_id: char_id, friend_id: friend_id, friend_name: friend_name},
      [:char_id, :friend_id, :friend_name]
    )
    |> Ecto.Changeset.validate_required([:char_id, :friend_id])
    |> Repo.insert(on_conflict: :nothing)
  end

  @doc "Remove a friend entry."
  def remove(char_id, friend_id) do
    from(f in __MODULE__,
      where: f.char_id == ^char_id and f.friend_id == ^friend_id)
    |> Repo.delete_all()
  end

  @doc "Load all friends for a character."
  def load_for_character(char_id) do
    from(f in __MODULE__, where: f.char_id == ^char_id)
    |> Repo.all()
  end

  @doc "Check if two characters are friends."
  def friends?(char_id, other_id) do
    from(f in __MODULE__,
      where: f.char_id == ^char_id and f.friend_id == ^other_id)
    |> Repo.exists?()
  end
end
