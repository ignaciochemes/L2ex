defmodule L2E.DB.CharacterShortcut do
  use Ecto.Schema
  import Ecto.Query
  alias L2E.Repo

  schema "character_shortcuts" do
    field(:char_id, :integer)
    field(:slot, :integer)
    field(:page, :integer, default: 0)
    field(:type, :integer)
    field(:shortcut_id, :integer)
    field(:level, :integer, default: 1)
  end

  def load_for_character(char_id) do
    Repo.all(from(s in __MODULE__, where: s.char_id == ^char_id))
  end

  def upsert(char_id, slot, page, type, shortcut_id, level) do
    %__MODULE__{
      char_id: char_id,
      slot: slot,
      page: page,
      type: type,
      shortcut_id: shortcut_id,
      level: level
    }
    |> Repo.insert(
      on_conflict: [set: [type: type, shortcut_id: shortcut_id, level: level]],
      conflict_target: [:char_id, :slot, :page]
    )

    :ok
  end

  def delete(char_id, slot, page) do
    Repo.delete_all(
      from(s in __MODULE__, where: s.char_id == ^char_id and s.slot == ^slot and s.page == ^page)
    )

    :ok
  end
end
