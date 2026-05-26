defmodule L2E.DB.CharacterMacro do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "character_macros" do
    field(:character_id, :integer)
    field(:macro_id, :integer)
    field(:icon, :integer, default: 0)
    field(:name, :string, default: "")
    field(:descr, :string, default: "")
    field(:keybind, :string, default: "")
    field(:commands, :string, default: "")
  end

  def changeset(macro, attrs) do
    macro
    |> cast(attrs, [:character_id, :macro_id, :icon, :name, :descr, :keybind, :commands])
    |> validate_required([:character_id, :macro_id])
  end
end
