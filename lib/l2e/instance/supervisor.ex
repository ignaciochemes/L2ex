defmodule L2E.Instance.Supervisor do
  @moduledoc "DynamicSupervisor for active instance subtrees."
  use DynamicSupervisor

  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Start a new instance zone process. Returns {:ok, instance_pid}."
  def start_instance(template_id, creator_party_id) do
    spec = {L2E.Instance.Zone, %{template_id: template_id, party_id: creator_party_id}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def stop_instance(pid), do: DynamicSupervisor.terminate_child(__MODULE__, pid)
end
