defmodule L2E.Instance.Manager do
  @moduledoc """
  Registry of active instances. ETS-backed for O(1) lookup.

  Maps:
    {:party, party_id}    => instance_pid
    {:instance, pid}      => template_id

  All mutations go through this GenServer to keep ETS writes serialized.
  Reads hit ETS directly (public, read_concurrency: true).
  """
  use GenServer
  require Logger

  @table :instance_registry

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Create a new instance for the given template and party. Returns {:ok, pid} or error."
  def create_instance(template_id, party_id) do
    GenServer.call(__MODULE__, {:create, template_id, party_id})
  end

  @doc "Look up the instance pid for a party. Returns {:ok, pid} or {:error, :not_found}."
  def get_instance(party_id) do
    case :ets.lookup(@table, {:party, party_id}) do
      [{_, pid}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:create, template_id, party_id}, _from, state) do
    case L2E.Instance.Supervisor.start_instance(template_id, party_id) do
      {:ok, pid} ->
        :ets.insert(@table, {{:party, party_id}, pid})
        :ets.insert(@table, {{:instance, pid}, template_id})
        Process.monitor(pid)

        Logger.info(
          "[Instance.Manager] Created instance pid=#{inspect(pid)} template=#{template_id} party=#{inspect(party_id)}"
        )

        {:reply, {:ok, pid}, state}

      err ->
        {:reply, err, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    case :ets.match(@table, {{:instance, pid}, :"$1"}) do
      [[_template_id]] ->
        :ets.match_delete(@table, {{:instance, pid}, :_})
        :ets.match_delete(@table, {:_, pid})
        Logger.info("[Instance.Manager] Cleaned up instance pid=#{inspect(pid)}")

      _ ->
        :ok
    end

    {:noreply, state}
  end
end
