defmodule L2E.Party.Room do
  @moduledoc """
  M122: Party Room GenServer.

  A party room is a temporary announcement: a party leader posts their room
  so solo players can find them. Rooms are ephemeral — no DB persistence.

  State:
    - id: unique integer (auto-increment from ETS counter)
    - title: string
    - party_pid: pid of the owning L2E.Party
    - leader_char_id: integer
    - min_level: integer
    - max_level: integer
    - loot_type: :by_turn | :random | :spoil | :item_order
    - location: string (free text)
    - member_count: integer (live count from party)
    - max_members: 9

  Lifecycle: created when party leader opens party match, closed when party
  disbands or leader closes it manually.
  """

  use GenServer

  # Public API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via_tuple(opts[:id]))
  end

  def via_tuple(id) do
    {:via, Registry, {L2E.Party.RoomRegistry, id}}
  end

  @doc "Create a new party room under L2E.Party.RoomSupervisor."
  def create(params) do
    DynamicSupervisor.start_child(L2E.Party.RoomSupervisor, {__MODULE__, params})
  end

  @doc "Close a party room by id."
  def close(room_id) do
    GenServer.stop(via_tuple(room_id), :normal)
  end

  @doc "Get info map for a room."
  def get_info(room_id) do
    GenServer.call(via_tuple(room_id), :get_info)
  end

  @doc "Update the member count for a room."
  def update_count(room_id, count) do
    GenServer.cast(via_tuple(room_id), {:update_count, count})
  end

  @doc "Returns all active rooms as a list of info maps."
  def list_rooms() do
    Registry.select(L2E.Party.RoomRegistry, [{{:"$1", :"$2", :"$3"}, [], [:"$2"]}])
    |> Enum.map(fn pid ->
      try do
        GenServer.call(pid, :get_info)
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.filter(&is_map/1)
  end

  @doc "Generate a unique room id from an ETS counter."
  def next_id() do
    table = :party_room_ids

    if :ets.whereis(table) == :undefined do
      :ets.new(table, [:named_table, :public, :set])
    end

    :ets.update_counter(table, :counter, {2, 1}, {:counter, 0})
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    state = %{
      id: opts[:id],
      title: opts[:title] || "Party",
      party_pid: opts[:party_pid],
      leader_char_id: opts[:leader_char_id],
      min_level: opts[:min_level] || 1,
      max_level: opts[:max_level] || 85,
      loot_type: opts[:loot_type] || :by_turn,
      location: opts[:location] || "Unknown",
      member_count: opts[:member_count] || 1,
      max_members: 9
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:update_count, count}, state) do
    {:noreply, %{state | member_count: count}}
  end
end

defmodule L2E.Party.RoomRegistry do
  @moduledoc "Registry for party room processes. Keyed by room_id (integer)."
  # This module exists as a named atom used in Registry registration.
  # The Registry process is started in L2E.Party.Supervisor.
end
