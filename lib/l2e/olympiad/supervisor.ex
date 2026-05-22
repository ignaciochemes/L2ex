defmodule L2E.Olympiad.Supervisor do
  @moduledoc "Supervisor for the Olympiad subsystem."
  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl Supervisor
  def init(_) do
    children = [
      L2E.Olympiad.Manager
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end
end
