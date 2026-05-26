defmodule L2E.World.DoorSupervisor do
  @moduledoc """
  DynamicSupervisor for castle door processes.
  Each door is a transient L2E.World.Door GenServer.
  """

  use DynamicSupervisor

  def start_link(_opts),
    do: DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl DynamicSupervisor
  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Start a door process with the given opts."
  @spec start_door(keyword()) :: DynamicSupervisor.on_start_child()
  def start_door(opts) do
    DynamicSupervisor.start_child(__MODULE__, {L2E.World.Door, opts})
  end
end
