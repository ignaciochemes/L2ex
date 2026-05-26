defmodule L2E.Siege.Supervisor do
  @moduledoc "Supervisor for the Siege subsystem."
  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl Supervisor
  def init(_) do
    children = [
      L2E.Siege.GuardManager,
      L2E.Siege.Manager
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
