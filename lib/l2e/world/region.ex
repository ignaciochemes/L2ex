defmodule L2E.World.Region do
  @moduledoc """
  One GenServer per active world grid cell.

  Owns:
  - The entity map for this cell: %{pid => entity_info}
  - The PubSub topic for AOI broadcasts within this cell

  Started on demand (first player entering the cell).
  Registered in L2E.World.RegionRegistry by {gx, gy} key.

  Crash semantics: if a Region crashes, its entity map is lost.
  Players in the region receive :connection_closed and must reconnect.
  The region process is NOT restarted automatically — it will be recreated
  the next time a player tries to enter.
  """

  use GenServer, restart: :temporary
  require Logger

  alias L2E.World.RegionCoords

  @type entity_info :: %{
          char_id: pos_integer(),
          char_name: String.t(),
          position: {integer(), integer(), integer()},
          heading: non_neg_integer(),
          hp: non_neg_integer(),
          max_hp: non_neg_integer()
        }

  @type state :: %{
          grid: {integer(), integer()},
          topic: String.t(),
          entities: %{pid() => entity_info()},
          npcs: %{pid() => map()},
          ground_items: %{pos_integer() => map()}
        }

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(grid: grid) do
    GenServer.start_link(__MODULE__, grid, name: via(grid))
  end

  @doc "Returns the pid for a region grid cell, starting it if necessary."
  @spec get_or_start({integer(), integer()} | {integer(), integer(), integer()}) :: pid()
  def get_or_start({x, y, _z}), do: get_or_start({x, y})

  def get_or_start(position) when is_tuple(position) and tuple_size(position) == 3 do
    {x, y, _z} = position
    get_or_start(RegionCoords.to_grid(x, y))
  end

  def get_or_start(grid) when is_tuple(grid) and tuple_size(grid) == 2 do
    case Registry.lookup(L2E.World.RegionRegistry, grid) do
      [{pid, _}] ->
        pid

      [] ->
        case DynamicSupervisor.start_child(L2E.World.RegionSupervisor, {__MODULE__, grid: grid}) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end
    end
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(grid) do
    Registry.register(L2E.World.RegionRegistry, grid, self())

    state = %{
      grid: grid,
      topic: RegionCoords.topic(grid),
      entities: %{},
      npcs: %{},
      ground_items: %{}
    }

    Logger.debug("[Region] Started for grid #{inspect(grid)}")
    {:ok, state}
  end

  # Player enters this region — returns list of existing entities to the caller
  @impl true
  def handle_call({:player_enter, pid, entity_info}, _from, state) do
    Process.monitor(pid)

    # Tell all current entities a new player arrived
    broadcast_to_others(state.entities, pid, {:broadcast, :player_entered, entity_info})

    # Also tell all NPCs so they can do aggro checks
    broadcast_to_map(state.npcs, {:broadcast, :player_entered, entity_info})

    new_entities = Map.put(state.entities, pid, entity_info)
    existing = Map.values(state.entities)

    # Also return NPC info packets so the entering player sees NPCs
    npc_packets = Map.values(state.npcs)

    # Also return ground item spawn packets for items on the ground
    item_packets = Enum.map(state.ground_items, fn {_, item} -> item.packet end)

    {:reply, {existing, npc_packets ++ item_packets}, %{state | entities: new_entities}}
  end

  # NPC enters this region — broadcasts NpcInfo to all current players
  def handle_call({:npc_enter, npc_pid, _object_id, npc_info_packet}, _from, state) do
    Process.monitor(npc_pid)

    # Tell all current players about the new NPC
    for {pid, _} <- state.entities do
      send(pid, {:send_packet, npc_info_packet})
    end

    # NPCs subscribe to player movement events for aggro
    new_npcs = Map.put(state.npcs, npc_pid, npc_info_packet)
    {:reply, :ok, %{state | npcs: new_npcs}}
  end

  # M18: Player picks up a ground item — returns the item data or nil
  def handle_call({:pickup_item, object_id, picker_pid}, _from, state) do
    case Map.pop(state.ground_items, object_id) do
      {nil, _} ->
        {:reply, nil, state}

      {item_data, new_ground_items} ->
        alias L2E.Packet.Server

        # Tell all players the item was picked up (DeleteObject)
        delete_pkt = %Server.DeleteObject{object_id: object_id}

        for {pid, _} <- state.entities do
          send(pid, {:send_packet, delete_pkt})
        end

        # GetItem animation broadcast
        {x, y, z} = item_data.position
        picker_info = Map.get(state.entities, picker_pid, %{char_id: 0})

        get_pkt = %Server.GetItem{
          char_id: picker_info.char_id,
          object_id: object_id,
          x: x,
          y: y,
          z: z
        }

        for {pid, _} <- state.entities do
          send(pid, {:send_packet, get_pkt})
        end

        {:reply, item_data, %{state | ground_items: new_ground_items}}
    end
  end

  # Player left (graceful)
  @impl true
  def handle_cast({:player_leave, char_id, pid}, state) do
    broadcast_to_others(state.entities, pid, {:broadcast, :player_left, char_id})
    broadcast_to_map(state.npcs, {:broadcast, :player_left, char_id})
    new_entities = Map.delete(state.entities, pid)

    maybe_stop(%{state | entities: new_entities})
  end

  # Player moved within this region
  def handle_cast({:player_moved, char_id, pid, origin, position, heading}, state) do
    info = %{char_id: char_id, origin: origin, position: position, heading: heading}

    broadcast_to_others(state.entities, pid, {:broadcast, :player_moved, info})

    updated_entity =
      state.entities
      |> Map.get(pid, %{})
      |> Map.merge(%{position: position, heading: heading})

    {:noreply, %{state | entities: Map.put(state.entities, pid, updated_entity)}}
  end

  # Broadcast an arbitrary server packet to all players in this region
  def handle_cast({:broadcast_packet, packet}, state) do
    for {pid, _} <- state.entities do
      send(pid, {:send_packet, packet})
    end

    {:noreply, state}
  end

  # M18: Drop an item on the ground — broadcast SpawnItem to all players
  def handle_cast({:drop_item, object_id, item_id, x, y, z, count}, state) do
    alias L2E.Packet.Server

    spawn_pkt = %Server.SpawnItem{
      object_id: object_id,
      item_id: item_id,
      x: x,
      y: y,
      z: z,
      count: count,
      stackable: 0
    }

    item_data = %{
      object_id: object_id,
      item_id: item_id,
      position: {x, y, z},
      count: count,
      packet: spawn_pkt
    }

    new_ground_items = Map.put(state.ground_items, object_id, item_data)

    for {pid, _} <- state.entities do
      send(pid, {:send_packet, spawn_pkt})
    end

    {:noreply, %{state | ground_items: new_ground_items}}
  end

  # Player process crashed — evict from region
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    cond do
      Map.has_key?(state.entities, pid) ->
        %{char_id: char_id} = Map.get(state.entities, pid)
        Logger.debug("[Region] Evicting crashed player pid=#{inspect(pid)}")
        broadcast_to_others(state.entities, pid, {:broadcast, :player_left, char_id})
        broadcast_to_map(state.npcs, {:broadcast, :player_left, char_id})
        new_entities = Map.delete(state.entities, pid)
        maybe_stop(%{state | entities: new_entities})

      Map.has_key?(state.npcs, pid) ->
        Logger.debug("[Region] NPC process down pid=#{inspect(pid)}")
        new_npcs = Map.delete(state.npcs, pid)
        maybe_stop(%{state | npcs: new_npcs})

      true ->
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("[Region] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # -----------------------------------------------------------------------
  # Private helpers
  # -----------------------------------------------------------------------

  defp broadcast_to_others(entities, sender_pid, message) do
    for {pid, _info} <- entities, pid != sender_pid do
      send(pid, message)
    end
  end

  defp broadcast_to_map(map, message) do
    for {pid, _} <- map do
      send(pid, message)
    end
  end

  # Stop the region process when it has no entities, NPCs, or ground items — saves memory
  defp maybe_stop(%{entities: entities, npcs: npcs, ground_items: items} = state)
       when map_size(entities) == 0 and map_size(npcs) == 0 and map_size(items) == 0 do
    Logger.debug("[Region] Empty, stopping #{inspect(state.grid)}")
    {:stop, :normal, state}
  end

  defp maybe_stop(state), do: {:noreply, state}

  defp via(grid), do: {:via, Registry, {L2E.World.RegionRegistry, grid}}
end
