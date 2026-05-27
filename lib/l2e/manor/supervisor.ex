defmodule L2E.Manor.Supervisor do
  @moduledoc "Supervisor for the Castle Manor subsystem."
  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl Supervisor
  def init(:ok) do
    children = [L2E.Manor.Manager]
    Supervisor.init(children, strategy: :one_for_one)
  end
end
