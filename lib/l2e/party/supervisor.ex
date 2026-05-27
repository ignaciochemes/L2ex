defmodule L2E.Party.Supervisor do
  @moduledoc """
  Top-level supervisor for all party subsystems.

  Children:
    - L2E.Party.RoomRegistry   — Registry for party room processes (M122)
    - L2E.Party.RoomSupervisor — DynamicSupervisor for party room processes (M122)
    - L2E.Party.PartySupervisor — DynamicSupervisor for active party processes
  """
  use Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    children = [
      {Registry, keys: :unique, name: L2E.Party.RoomRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: L2E.Party.RoomSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: L2E.Party.PartySupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "Start a new party process with the given leader info."
  def start_party(leader_id, leader_pid, distribution_type) do
    spec =
      {L2E.Party,
       [leader_id: leader_id, leader_pid: leader_pid, distribution_type: distribution_type]}

    DynamicSupervisor.start_child(L2E.Party.PartySupervisor, spec)
  end
end
