defmodule L2E.Duel.Supervisor do
  @moduledoc "DynamicSupervisor for active duel sessions."
  use DynamicSupervisor

  def start_link(_opts), do: DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl DynamicSupervisor
  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_duel(duel_id, attacker_pid, defender_pid, opts \\ []) do
    spec =
      {L2E.Duel.Session,
       duel_id: duel_id, attacker_pid: attacker_pid, defender_pid: defender_pid, opts: opts}

    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
