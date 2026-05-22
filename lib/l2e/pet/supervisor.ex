defmodule L2E.Pet.Supervisor do
  @moduledoc "DynamicSupervisor for active pet sessions. Each pet is supervised under its owner's session."
  use DynamicSupervisor

  def start_link(_opts), do: DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl DynamicSupervisor
  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_pet(owner_pid, pet_item_obj_id, npc_id) do
    spec =
      {L2E.Pet.Session, owner_pid: owner_pid, pet_item_obj_id: pet_item_obj_id, npc_id: npc_id}

    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
