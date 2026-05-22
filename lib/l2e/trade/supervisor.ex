defmodule L2E.Trade.Supervisor do
  @moduledoc """
  Supervisor for ephemeral player-to-player trade processes.

  Each trade session is represented by one `L2E.Trade` GenServer that lives
  only for the duration of the trade and is then stopped.
  """

  use Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      {Registry, keys: :unique, name: L2E.Trade.Registry},
      {DynamicSupervisor, name: L2E.Trade.DynamicSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc "Start a trade between char_a (initiator) and char_b (recipient)."
  def start_trade(char_a, char_b, pid_a, pid_b) do
    DynamicSupervisor.start_child(
      L2E.Trade.DynamicSupervisor,
      {L2E.Trade, [char_a: char_a, char_b: char_b, pid_a: pid_a, pid_b: pid_b]}
    )
  end
end
