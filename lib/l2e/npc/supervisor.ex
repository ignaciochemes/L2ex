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

  @doc "Spawn a new NPC instance with a pre-built opts keyword list."
  def spawn_npc(opts) do
    DynamicSupervisor.start_child(__MODULE__, {L2E.NPC.Instance, opts})
  end

  @doc """
  Convenience: spawn an NPC by numeric id at the given world coordinates.
  Looks up the template automatically. Object ID is auto-generated.
  Returns `{:ok, pid}` or `{:error, :no_template}` / `{:error, reason}`.
  """
  @spec spawn_npc(pos_integer(), integer(), integer(), integer(), non_neg_integer()) ::
          {:ok, pid()} | {:error, term()}
  def spawn_npc(npc_id, x, y, z, heading \\ 0) do
    case L2E.NPC.TemplateTable.get(npc_id) do
      nil ->
        {:error, :no_template}

      template ->
        object_id = 100_000 + :erlang.unique_integer([:positive, :monotonic])

        opts = [
          template: template,
          position: {x, y, z},
          heading: heading,
          object_id: object_id
        ]

        DynamicSupervisor.start_child(__MODULE__, {L2E.NPC.Instance, opts})
    end
  end
end
