defmodule L2E.DB.PetInventoryItem do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "pet_inventory_items" do
    field(:pet_item_obj_id, :integer)
    field(:char_id, :integer)
    field(:item_id, :integer)
    field(:object_id, :integer)
    field(:count, :integer, default: 1)
    field(:enchant_level, :integer, default: 0)
    field(:slot, :integer, default: 0)
    timestamps()
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [
      :pet_item_obj_id,
      :char_id,
      :item_id,
      :object_id,
      :count,
      :enchant_level,
      :slot
    ])
    |> validate_required([:pet_item_obj_id, :char_id, :item_id, :object_id])
  end

  def load_for_pet(pet_item_obj_id) do
    L2E.Repo.all(from(i in __MODULE__, where: i.pet_item_obj_id == ^pet_item_obj_id))
  end

  def add_item(pet_item_obj_id, char_id, item_id, object_id, count \\ 1) do
    %__MODULE__{}
    |> changeset(%{
      pet_item_obj_id: pet_item_obj_id,
      char_id: char_id,
      item_id: item_id,
      object_id: object_id,
      count: count
    })
    |> L2E.Repo.insert()
  end

  def remove_item(object_id) do
    L2E.Repo.delete_all(from(i in __MODULE__, where: i.object_id == ^object_id))
  end
end
