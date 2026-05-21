defmodule L2E.Clan.Supervisor do
  @moduledoc "DynamicSupervisor for clan processes."
  use DynamicSupervisor

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start a new clan process."
  def start_clan(clan_id, clan_name, leader_id, leader_pid) do
    spec =
      {L2E.Clan,
       [clan_id: clan_id, clan_name: clan_name, leader_id: leader_id, leader_pid: leader_pid]}

    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
