defmodule L2E.Network.Supervisor do
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    port = Application.get_env(:l2e, :game_port, 7777)

    children = [
      {ThousandIsland,
       port: port, handler_module: L2E.Network.ConnectionHandler, num_acceptors: 10}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
