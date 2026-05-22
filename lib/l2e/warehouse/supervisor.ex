defmodule L2E.Warehouse.Supervisor do
  @moduledoc """
  DynamicSupervisor for private warehouse processes.

  Each `L2E.Warehouse` GenServer is started on demand when a character
  opens the warehouse NPC dialog and stopped when they close it.
  """

  use Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      {Registry, keys: :unique, name: L2E.Warehouse.Registry},
      {DynamicSupervisor, name: L2E.Warehouse.DynamicSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc "Starts a warehouse process for the given char_id."
  def start_warehouse(char_id) do
    DynamicSupervisor.start_child(
      L2E.Warehouse.DynamicSupervisor,
      {L2E.Warehouse, char_id: char_id}
    )
  end
end
