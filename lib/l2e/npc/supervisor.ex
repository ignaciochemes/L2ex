defmodule L2E.NPC.Supervisor do
  @moduledoc """
  Top-level supervisor for NPC subsystems.

  Children:
    - L2E.NPC.WalkingManager  — patrol route manager (M124)
    - L2E.NPC.InstanceSupervisor — DynamicSupervisor for live NPC instances
  """

  use Supervisor
  require Logger

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    children = [
      L2E.NPC.WalkingManager,
      {DynamicSupervisor, strategy: :one_for_one, name: L2E.NPC.InstanceSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "Spawn a new NPC instance with a pre-built opts keyword list."
  def spawn_npc(opts) do
    DynamicSupervisor.start_child(L2E.NPC.InstanceSupervisor, {L2E.NPC.Instance, opts})
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

        DynamicSupervisor.start_child(L2E.NPC.InstanceSupervisor, {L2E.NPC.Instance, opts})
    end
  end
end
