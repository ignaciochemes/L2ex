defmodule L2E.DB.GlobalVariable do
  use Ecto.Schema

  @primary_key {:name, :string, []}
  schema "global_variables" do
    field(:value, :string)
    timestamps()
  end
end
