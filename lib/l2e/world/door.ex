defmodule L2E.World.Door do
  @moduledoc """
  A castle door or gate — can be opened, closed, and damaged during sieges.

  Each door is a supervised GenServer process. On state changes it broadcasts
  the appropriate packet to all players in its region:
    - DoorInfo (0x31)        — full state: initial announcement or HP update
    - DoorStatusUpdate (0x2C) — compact open/close notification

  Registered in L2E.Session.Registry by {:door, object_id}.
  """

  use GenServer, restart: :transient
  require Logger

  alias L2E.Packet.Server
  alias L2E.World.Region

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Open the door."
  def open(pid), do: GenServer.cast(pid, :open)

  @doc "Close the door."
  def close(pid), do: GenServer.cast(pid, :close)

  @doc "Apply damage to the door."
  @spec take_damage(pid(), number()) :: :ok
  def take_damage(pid, amount), do: GenServer.cast(pid, {:take_damage, amount})

  @doc "Apply damage to the door with attacker tracking."
  @spec take_damage(pid(), number(), pid() | nil) :: :ok
  def take_damage(pid, amount, _from_pid), do: GenServer.cast(pid, {:take_damage, amount})

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    object_id = Keyword.fetch!(opts, :object_id)
    name = Keyword.get(opts, :name, "Door")
    position = Keyword.fetch!(opts, :position)
    max_hp = Keyword.get(opts, :max_hp, 100_000)
    castle_id = Keyword.get(opts, :castle_id, 0)

    Registry.register(L2E.Session.Registry, {:door, object_id}, self())

    state = %{
      object_id: object_id,
      name: name,
      position: position,
      hp: max_hp * 1.0,
      max_hp: max_hp,
      open: false,
      castle_id: castle_id,
      region_pid: Region.get_or_start(position)
    }

    broadcast_info(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast(:open, state) do
    new_state = %{state | open: true}
    broadcast_status(new_state)
    {:noreply, new_state}
  end

  def handle_cast(:close, state) do
    new_state = %{state | open: false}
    broadcast_status(new_state)
    {:noreply, new_state}
  end

  def handle_cast({:take_damage, amount}, state) do
    new_hp = max(0.0, state.hp - amount)
    new_state = %{state | hp: new_hp}

    if new_hp <= 0.0 do
      Logger.info("[Door] #{state.name} (object_id=#{state.object_id}) destroyed!")
      destroyed = %{new_state | open: true}
      broadcast_info(destroyed)
      broadcast_status(destroyed)

      # Notify the owning castle GenServer so it can track door state during siege
      if state.castle_id && state.castle_id > 0 do
        L2E.Siege.Castle.door_destroyed(state.castle_id, state.object_id)
      end

      {:noreply, destroyed}
    else
      broadcast_info(new_state)
      {:noreply, new_state}
    end
  end

  # -----------------------------------------------------------------------
  # Private — packet helpers
  # -----------------------------------------------------------------------

  # DoorInfo (0x31) — full state including HP and coordinates.
  # Sent on init and whenever HP changes.
  defp broadcast_info(state) do
    if state.region_pid do
      {x, y, z} = state.position

      pkt = %Server.DoorInfo{
        door_id: state.object_id,
        is_open: if(state.open, do: 1, else: 0),
        max_hp: state.max_hp,
        current_hp: trunc(state.hp),
        x: x,
        y: y,
        z: z
      }

      GenServer.cast(state.region_pid, {:broadcast_packet, pkt})
    end
  end

  # DoorStatusUpdate (0x2C) — compact open/close notification.
  # Sent on open/close changes.
  defp broadcast_status(state) do
    if state.region_pid do
      pkt = %Server.DoorStatusUpdate{
        door_id: state.object_id,
        is_open: if(state.open, do: 1, else: 0)
      }

      GenServer.cast(state.region_pid, {:broadcast_packet, pkt})
    end
  end
end
