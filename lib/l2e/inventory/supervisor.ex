defmodule L2E.Inventory.Supervisor do
  @moduledoc "DynamicSupervisor for per-player Inventory processes."

  use DynamicSupervisor

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Starts an Inventory process for the given character id."
  @spec start_inventory(pos_integer()) :: DynamicSupervisor.on_start_child()
  def start_inventory(char_id) do
    DynamicSupervisor.start_child(__MODULE__, {L2E.Inventory, [char_id: char_id]})
  end
end
