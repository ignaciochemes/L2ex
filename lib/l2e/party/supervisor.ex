defmodule L2E.Party.Supervisor do
  @moduledoc """
  DynamicSupervisor for party processes.
  Each active party is a supervised L2E.Party process.
  """
  use DynamicSupervisor

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start a new party process with the given leader info."
  def start_party(leader_id, leader_pid, distribution_type) do
    spec =
      {L2E.Party,
       [leader_id: leader_id, leader_pid: leader_pid, distribution_type: distribution_type]}

    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
