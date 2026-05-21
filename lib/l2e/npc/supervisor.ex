defmodule L2E.NPC.Supervisor do
  @moduledoc """
  DynamicSupervisor for all live NPC.Instance processes.

  Each spawned NPC gets a child process started here.
  When an NPC dies it stops normally; SpawnTable schedules respawn.
  """

  use DynamicSupervisor
  require Logger

  def start_link(_opts), do: DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Spawn a new NPC instance."
  def spawn_npc(opts) do
    DynamicSupervisor.start_child(__MODULE__, {L2E.NPC.Instance, opts})
  end
end
