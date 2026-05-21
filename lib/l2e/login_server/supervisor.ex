defmodule L2E.LoginServer.Supervisor do
  @moduledoc """
  Supervision tree for the L2 Login Server.

  Children:
  - `AccountStore` — ETS-backed GenServer for pending sessions.
  - ThousandIsland — TCP acceptor on the login port (default 2106).
  """

  use Supervisor

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl Supervisor
  def init(_opts) do
    port = Application.get_env(:l2e, :login_port, 2106)

    children = [
      L2E.LoginServer.AccountStore,
      {ThousandIsland,
       port: port, handler_module: L2E.LoginServer.ConnectionHandler, num_acceptors: 5}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
