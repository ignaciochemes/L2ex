defmodule L2E.Instance.Zone do
  @moduledoc """
  GenServer managing a single instance zone.
  Owns: player list, door states, expiry timer.

  Each instance is an isolated supervised process. Players enter/leave via
  message passing. Doors are per-instance state — no shared locks.
  On expiry, all remaining players receive :instance_ejected.
  """
  use GenServer
  require Logger

  @instance_ttl_ms 3_600_000

  defstruct [
    :template_id,
    :party_id,
    :players,
    :doors,
    :created_at
  ]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(init_arg), do: GenServer.start_link(__MODULE__, init_arg)

  def enter(instance_pid, player_pid), do: GenServer.call(instance_pid, {:enter, player_pid})
  def leave(instance_pid, player_pid), do: GenServer.call(instance_pid, {:leave, player_pid})

  def set_door(instance_pid, door_id, open?),
    do: GenServer.cast(instance_pid, {:set_door, door_id, open?})

  def get_players(instance_pid), do: GenServer.call(instance_pid, :get_players)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{template_id: template_id, party_id: party_id}) do
    Process.send_after(self(), :instance_expired, @instance_ttl_ms)

    state = %__MODULE__{
      template_id: template_id,
      party_id: party_id,
      players: MapSet.new(),
      doors: %{},
      created_at: System.system_time(:second)
    }

    Logger.info("[Instance] Zone started — template=#{template_id} party=#{inspect(party_id)}")
    {:ok, state}
  end

  @impl true
  def handle_call({:enter, player_pid}, _from, state) do
    Process.monitor(player_pid)
    {:reply, :ok, %{state | players: MapSet.put(state.players, player_pid)}}
  end

  def handle_call({:leave, player_pid}, _from, state) do
    {:reply, :ok, %{state | players: MapSet.delete(state.players, player_pid)}}
  end

  def handle_call(:get_players, _from, state) do
    {:reply, state.players, state}
  end

  @impl true
  def handle_cast({:set_door, door_id, open?}, state) do
    new_doors = Map.put(state.doors, door_id, if(open?, do: :open, else: :closed))

    Enum.each(state.players, fn player_pid ->
      send(player_pid, {:instance_door_update, door_id, open?})
    end)

    {:noreply, %{state | doors: new_doors}}
  end

  @impl true
  def handle_info(:instance_expired, state) do
    Logger.info(
      "[Instance] Zone expired — template=#{state.template_id}, ejecting #{MapSet.size(state.players)} player(s)"
    )

    Enum.each(state.players, fn pid -> send(pid, :instance_ejected) end)
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | players: MapSet.delete(state.players, pid)}}
  end
end
