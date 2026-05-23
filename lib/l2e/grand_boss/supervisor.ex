defmodule L2E.GrandBoss.Supervisor do
  use Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    children = [
      L2E.GrandBoss.Manager
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
