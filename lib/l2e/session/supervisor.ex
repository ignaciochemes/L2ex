defmodule L2E.Session.Supervisor do
  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Spawns a new PlayerSession for an authenticated connection.
  The session is :temporary — a crash is NOT restarted; the client must reconnect.
  """
  def start_session(conn_pid) do
    spec = {L2E.Session.PlayerSession, conn_pid: conn_pid}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
