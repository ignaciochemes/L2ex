defmodule L2E.GrandBoss.Manager do
  use GenServer
  require Logger

  @moduledoc """
  M61-A: Grand Boss respawn window tracking.

  Tracks the alive/dead/waiting state of all Interlude grand bosses.
  Persists state in ETS. Actual NPC spawning is delegated to SpawnTable.
  """

  # Grand Boss NPC IDs — all Interlude world/raid bosses that gate an instance
  @grand_boss_ids [
    29001,
    29006,
    29014,
    29019,
    29020,
    29022,
    29026,
    29028,
    29045,
    29046,
    29047,
    29048,
    29049,
    29050
  ]

  # Boss IDs from L2J Mobius CT0 data
  @bosses %{
    29022 => %{name: "Antharas", respawn_min_h: 192, respawn_max_h: 200},
    29028 => %{name: "Valakas", respawn_min_h: 264, respawn_max_h: 280},
    29020 => %{name: "Baium", respawn_min_h: 121, respawn_max_h: 143},
    29026 => %{name: "Zaken", respawn_min_h: 60, respawn_max_h: 84},
    29006 => %{name: "Core", respawn_min_h: 36, respawn_max_h: 44},
    29014 => %{name: "Orfen", respawn_min_h: 36, respawn_max_h: 44},
    29001 => %{name: "Queen Ant", respawn_min_h: 19, respawn_max_h: 35},
    29045 => %{name: "Frintezza", respawn_min_h: 48, respawn_max_h: 52},
    29046 => %{name: "Sailren", respawn_min_h: 12, respawn_max_h: 36}
  }

  # State: %{boss_id => %{state: :alive | :dead | :waiting, respawn_at: DateTime | nil}}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    :ets.new(:grand_boss_states, [:named_table, :public, read_concurrency: true])
    :ets.new(:grand_boss_locks, [:named_table, :public, :set])

    Enum.each(@bosses, fn {id, _info} ->
      :ets.insert(:grand_boss_states, {id, :alive, nil})
    end)

    Process.send_after(self(), :cleanup_stale_locks, 300_000)

    Logger.info("[GrandBossManager] initialized #{map_size(@bosses)} boss slots")
    {:ok, %{}}
  end

  # ─── Public API ────────────────────────────────────────────────────────────

  def grand_boss_ids, do: @grand_boss_ids

  def get_state(boss_id) do
    case :ets.lookup(:grand_boss_states, boss_id) do
      [{^boss_id, state, respawn_at}] -> {state, respawn_at}
      [] -> {:unknown, nil}
    end
  end

  def set_dead(boss_id) do
    GenServer.cast(__MODULE__, {:boss_died, boss_id})
  end

  def set_alive(boss_id) do
    :ets.insert(:grand_boss_states, {boss_id, :alive, nil})
  end

  @doc "Attempt to lock instance for a party. Returns :ok or {:error, reason}."
  def enter_instance(boss_id, party_leader_char_id) do
    GenServer.call(__MODULE__, {:enter_instance, boss_id, party_leader_char_id})
  end

  @doc "Release the instance lock for a boss after the party leaves."
  def leave_instance(boss_id) do
    GenServer.call(__MODULE__, {:leave_instance, boss_id})
  end

  @doc "Returns true if the boss is alive and the instance is not currently locked."
  def can_enter?(boss_id) do
    GenServer.call(__MODULE__, {:can_enter, boss_id})
  end

  @doc "Notify manager that a grand boss NPC has died. respawn_time_ms defaults to 12 hours."
  def boss_died(boss_id, respawn_time_ms \\ 43_200_000) do
    GenServer.cast(__MODULE__, {:boss_died, boss_id, respawn_time_ms})
  end

  # ─── Internals ─────────────────────────────────────────────────────────────

  defp get_boss_state(boss_id) do
    case :ets.lookup(:grand_boss_states, boss_id) do
      [{^boss_id, s, _}] -> s
      [] -> :unknown
    end
  end

  # ─── handle_call ───────────────────────────────────────────────────────────

  def handle_call({:enter_instance, boss_id, party_leader_char_id}, _from, state) do
    boss_state = get_boss_state(boss_id)

    cond do
      boss_state == :dead ->
        {:reply, {:error, :boss_dead}, state}

      :ets.lookup(:grand_boss_locks, boss_id) != [] ->
        {:reply, {:error, :instance_occupied}, state}

      true ->
        :ets.insert(
          :grand_boss_locks,
          {boss_id, party_leader_char_id, System.monotonic_time(:second)}
        )

        {:reply, :ok, state}
    end
  end

  def handle_call({:leave_instance, boss_id}, _from, state) do
    :ets.delete(:grand_boss_locks, boss_id)
    {:reply, :ok, state}
  end

  def handle_call({:can_enter, boss_id}, _from, state) do
    boss_alive = get_boss_state(boss_id) != :dead
    not_locked = :ets.lookup(:grand_boss_locks, boss_id) == []
    {:reply, boss_alive and not_locked, state}
  end

  # ─── handle_cast ───────────────────────────────────────────────────────────

  # New 3-tuple variant: called from NPC death hook with explicit respawn_time_ms
  def handle_cast({:boss_died, boss_id, respawn_time_ms}, state) do
    now = DateTime.utc_now()
    respawn_at = DateTime.add(now, div(respawn_time_ms, 1000), :second)
    :ets.insert(:grand_boss_states, {boss_id, :dead, respawn_at})
    :ets.delete(:grand_boss_locks, boss_id)
    Process.send_after(self(), {:respawn_boss, boss_id}, respawn_time_ms)
    Phoenix.PubSub.broadcast(L2E.PubSub, "world:grand_boss", {:grand_boss_died, boss_id})
    Logger.info("[GrandBossManager] boss #{boss_id} died — respawn at #{respawn_at}")
    {:noreply, state}
  end

  # Legacy 2-tuple variant: called via set_dead/1 (uses @bosses respawn window config)
  def handle_cast({:boss_died, boss_id}, state) do
    case Map.get(@bosses, boss_id) do
      nil ->
        {:noreply, state}

      %{respawn_min_h: min_h, respawn_max_h: max_h} ->
        range_ms = (max_h - min_h) * 3_600_000
        delay_ms = min_h * 3_600_000 + :rand.uniform(max(1, range_ms))
        respawn_at = DateTime.utc_now() |> DateTime.add(div(delay_ms, 1000), :second)
        :ets.insert(:grand_boss_states, {boss_id, :dead, respawn_at})
        Process.send_after(self(), {:respawn_window_open, boss_id}, delay_ms)
        Logger.info("[GrandBossManager] #{boss_id} dead — respawn at #{respawn_at}")
        {:noreply, state}
    end
  end

  def handle_info({:respawn_window_open, boss_id}, state) do
    :ets.insert(:grand_boss_states, {boss_id, :waiting, nil})
    Logger.info("[GrandBossManager] #{boss_id} respawn window open")
    {:noreply, state}
  end

  def handle_info({:respawn_boss, boss_id}, state) do
    :ets.insert(:grand_boss_states, {boss_id, :alive, nil})
    Phoenix.PubSub.broadcast(L2E.PubSub, "world:grand_boss", {:grand_boss_respawned, boss_id})
    Logger.info("[GrandBossManager] boss #{boss_id} respawned")
    {:noreply, state}
  end

  def handle_info(:cleanup_stale_locks, state) do
    now = System.monotonic_time(:second)

    :ets.tab2list(:grand_boss_locks)
    |> Enum.each(fn {boss_id, _leader, inserted_at} ->
      if now - inserted_at > 10_800 do
        :ets.delete(:grand_boss_locks, boss_id)
        Logger.info("[GrandBossManager] stale lock cleared for boss #{boss_id}")
      end
    end)

    Process.send_after(self(), :cleanup_stale_locks, 300_000)
    {:noreply, state}
  end
end
