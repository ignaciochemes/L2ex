defmodule L2E.Olympiad.Supervisor do
  @moduledoc "Supervisor for the Olympiad subsystem."
  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Start a new 1v1 match under the MatchSupervisor."
  def start_match(opts) do
    DynamicSupervisor.start_child(L2E.Olympiad.MatchSupervisor, {L2E.Olympiad.Match, opts})
  end

  @impl Supervisor
  def init(_) do
    children = [
      L2E.Olympiad.Manager,
      {DynamicSupervisor, name: L2E.Olympiad.MatchSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
