defmodule L2E.CommandChannel.Session do
  @moduledoc """
  Command Channel GenServer — groups up to 4 parties (max 36 players) for mass raids.
  Only party leaders can join/leave a Command Channel.
  The CC leader is the leader of the party that created the CC.
  """
  use GenServer
  require Logger

  @max_parties 4
  @max_members 36

  # parties: list of %{party_pid, leader_char_id, leader_name, member_count}
  defstruct cc_id: nil, leader_char_id: nil, parties: [], created_at: nil

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(opts) do
    cc_id = Keyword.fetch!(opts, :cc_id)
    GenServer.start_link(__MODULE__, opts, name: via(cc_id))
  end

  @doc "Create a new Command Channel. Returns {:ok, pid} or {:error, reason}."
  def create(cc_id, leader_char_id, leader_party_pid) do
    DynamicSupervisor.start_child(
      L2E.CommandChannel.Supervisor,
      {__MODULE__,
       [cc_id: cc_id, leader_char_id: leader_char_id, leader_party_pid: leader_party_pid]}
    )
  end

  @doc "Add a party to this Command Channel. Returns :ok | {:error, reason}."
  def add_party(cc_pid, party_pid, leader_char_id, leader_name) do
    GenServer.call(cc_pid, {:add_party, party_pid, leader_char_id, leader_name})
  end

  @doc "Remove a party from this Command Channel."
  def remove_party(cc_pid, party_pid) do
    GenServer.cast(cc_pid, {:remove_party, party_pid})
  end

  @doc "Get the current Command Channel state info."
  def get_info(cc_pid) do
    GenServer.call(cc_pid, :get_info)
  end

  @doc "Broadcast a message to all members of this Command Channel via PubSub."
  def broadcast_to_all(cc_pid, message) do
    GenServer.cast(cc_pid, {:broadcast, message})
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(opts) do
    cc_id = Keyword.fetch!(opts, :cc_id)
    leader_char_id = Keyword.fetch!(opts, :leader_char_id)
    leader_party_pid = Keyword.fetch!(opts, :leader_party_pid)

    party_info = get_party_info(leader_party_pid)

    state = %__MODULE__{
      cc_id: cc_id,
      leader_char_id: leader_char_id,
      parties: [party_info],
      created_at: System.system_time(:second)
    }

    Logger.info("[CC] Created cc_id=#{cc_id} leader=#{leader_char_id}")
    {:ok, state}
  end

  @impl true
  def handle_call({:add_party, party_pid, _leader_char_id, _leader_name}, _from, state) do
    total_members = Enum.sum(Enum.map(state.parties, & &1.member_count))
    party_info = get_party_info(party_pid)

    cond do
      length(state.parties) >= @max_parties ->
        {:reply, {:error, :max_parties_reached}, state}

      total_members + party_info.member_count > @max_members ->
        {:reply, {:error, :max_members_reached}, state}

      true ->
        new_parties = state.parties ++ [party_info]
        new_state = %{state | parties: new_parties}
        broadcast_update(new_state)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    {:reply, Map.from_struct(state), state}
  end

  @impl true
  def handle_cast({:remove_party, party_pid}, state) do
    new_parties = Enum.reject(state.parties, &(&1.party_pid == party_pid))

    if Enum.empty?(new_parties) do
      Logger.info("[CC] Disbanded cc_id=#{state.cc_id}")
      {:stop, :normal, %{state | parties: []}}
    else
      new_state = %{state | parties: new_parties}
      broadcast_update(new_state)
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:broadcast, message}, state) do
    Phoenix.PubSub.broadcast(L2E.PubSub, "cc:#{state.cc_id}", message)
    {:noreply, state}
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  # -----------------------------------------------------------------------
  # Private helpers
  # -----------------------------------------------------------------------

  defp via(cc_id), do: {:via, Registry, {L2E.Session.Registry, {:cc, cc_id}}}

  defp get_party_info(party_pid) do
    try do
      info = L2E.Party.get_info(party_pid)

      %{
        party_pid: party_pid,
        leader_char_id: Map.get(info, :leader_char_id, 0),
        leader_name: Map.get(info, :leader_name, "Unknown"),
        member_count: Map.get(info, :member_count, 0)
      }
    catch
      _, _ ->
        %{party_pid: party_pid, leader_char_id: 0, leader_name: "Unknown", member_count: 0}
    end
  end

  defp broadcast_update(state) do
    Phoenix.PubSub.broadcast(L2E.PubSub, "cc:#{state.cc_id}", {:cc_updated, state})
  end
end
