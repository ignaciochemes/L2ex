defmodule L2E.Siege.Supervisor do
  @moduledoc "Supervisor for the Siege subsystem."
  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl Supervisor
  def init(_) do
    children = [
      # Registry for per-castle GenServer lookup by {:castle, castle_id}
      {Registry, keys: :unique, name: L2E.Siege.Registry},
      # DynamicSupervisor for individual Castle GenServer processes
      {DynamicSupervisor, name: L2E.Siege.CastleSupervisor, strategy: :one_for_one},
      L2E.Siege.GuardManager,
      # Manager starts last — its init/1 calls init_castles/0 which requires the above
      L2E.Siege.Manager
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
