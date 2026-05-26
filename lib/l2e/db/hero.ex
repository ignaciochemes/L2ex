defmodule L2E.DB.Hero do
  use Ecto.Schema
  import Ecto.Query

  @primary_key {:char_id, :integer, autogenerate: false}
  schema "heroes" do
    field :char_name, :string
    field :class_id, :integer
    field :elected_at, :utc_datetime
    field :is_active, :boolean, default: true

    timestamps()
  end

  @doc "Mark all current heroes inactive, then insert/replace new batch."
  def elect(heroes_list) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    L2E.Repo.update_all(from(h in __MODULE__), set: [is_active: false])

    Enum.each(heroes_list, fn %{char_id: char_id, char_name: char_name, class_id: class_id} ->
      %__MODULE__{}
      |> Ecto.Changeset.change(%{
        char_id: char_id,
        char_name: char_name,
        class_id: class_id,
        elected_at: now,
        is_active: true
      })
      |> L2E.Repo.insert!(on_conflict: :replace_all, conflict_target: :char_id)
    end)

    :ok
  end

  @doc "Return all currently active heroes."
  def active_heroes do
    L2E.Repo.all(from h in __MODULE__, where: h.is_active == true)
  end
end
