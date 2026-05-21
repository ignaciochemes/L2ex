defmodule L2E.World.Supervisor do
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Registry for region lookups: key is {grid_x, grid_y}
      {Registry, keys: :unique, name: L2E.World.RegionRegistry},

      # DynamicSupervisor for Region GenServers (started on demand)
      {DynamicSupervisor, strategy: :one_for_one, name: L2E.World.RegionSupervisor}
    ]

    # rest_for_one: if RegionRegistry crashes, RegionSupervisor and all
    # Region processes restart together to avoid stale Registry entries.
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
