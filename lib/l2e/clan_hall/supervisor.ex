defmodule L2E.ClanHall.Supervisor do
  @moduledoc """
  M125: Top-level supervisor for the clan hall subsystem.

  Starts in order:
    1. Registry — for per-hall process lookup by hall_id
    2. HallSupervisor — DynamicSupervisor for per-hall GenServer processes
    3. AuctionManager — weekly auction cycle; spawns Hall processes on init
  """
  use Supervisor

  def start_link(_opts),
    do: Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    children = [
      {Registry, keys: :unique, name: L2E.ClanHall.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: L2E.ClanHall.HallSupervisor},
      L2E.ClanHall.AuctionManager
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
