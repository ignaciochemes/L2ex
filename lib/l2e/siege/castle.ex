defmodule L2E.Siege.Castle do
  @moduledoc """
  Per-castle GenServer — owns the full siege state machine for one castle.

  Lifecycle:
    :idle → :preparation → :in_siege → :ended → :idle

  Transitions are driven by `Process.send_after/3` — no polling loop.
  Registered in L2E.Siege.Registry as {:castle, castle_id}.

  Reference: Castle.java (behavioral reference only)
  """

  use GenServer
  require Logger

  # -----------------------------------------------------------------------
  # Struct — kept for backward compatibility with Manager's ETS storage
  # -----------------------------------------------------------------------

  defstruct [
    :id,
    :name,
    :owner_clan_id,
    :siege_date,
    # :idle | :preparation | :in_progress | :ended
    :siege_status,
    :tax_rate,
    :treasury
  ]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          name: String.t(),
          owner_clan_id: pos_integer() | nil,
          siege_date: DateTime.t() | nil,
          siege_status: :idle | :preparation | :in_progress | :ended,
          tax_rate: non_neg_integer(),
          treasury: non_neg_integer()
        }

  # Interlude castle IDs and names
  @castles [
    %{id: 1, name: "Gludio"},
    %{id: 2, name: "Dion"},
    %{id: 3, name: "Giran"},
    %{id: 4, name: "Oren"},
    %{id: 5, name: "Aden"},
    %{id: 6, name: "Innadril"},
    %{id: 7, name: "Goddard"},
    %{id: 8, name: "Rune"},
    %{id: 9, name: "Schuttgart"}
  ]

  def all_castles, do: @castles

  def new(id, name) do
    %__MODULE__{
      id: id,
      name: name,
      owner_clan_id: nil,
      siege_date: nil,
      siege_status: :idle,
      tax_rate: 15,
      treasury: 0
    }
  end

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(opts) do
    castle_id = Keyword.fetch!(opts, :castle_id)
    GenServer.start_link(__MODULE__, opts, name: via(castle_id))
  end

  @doc "Get the full siege state of a castle."
  def get_info(castle_id), do: safe_call(via(castle_id), :get_siege_info)

  @doc "Register a clan as attacker. Only allowed during :preparation."
  def register_attacker(castle_id, clan_id),
    do: safe_call(via(castle_id), {:register_attacker, clan_id})

  @doc "Register a clan as defender. Only allowed during :preparation."
  def register_defender(castle_id, clan_id),
    do: safe_call(via(castle_id), {:register_defender, clan_id})

  @doc "Mark that a clan captured the relic flag."
  def relic_captured(castle_id, by_clan_id),
    do: GenServer.cast(via(castle_id), {:relic_captured, by_clan_id})

  @doc "Notify the castle that one of its doors was destroyed."
  def door_destroyed(castle_id, door_id),
    do: GenServer.cast(via(castle_id), {:door_destroyed, door_id})

  @doc "Manually trigger siege start (for testing/admin use)."
  def start_siege(castle_id),
    do: GenServer.cast(via(castle_id), :start_siege_manual)

  @doc "Record a kill by an attacker clan during an active siege."
  def record_kill(castle_id, attacker_clan_id) do
    case Registry.lookup(L2E.Siege.Registry, {:castle, castle_id}) do
      [{pid, _}] -> GenServer.cast(pid, {:record_kill, attacker_clan_id})
      [] -> :ok
    end
  end

  @doc "Enter preparation phase and schedule siege start."
  def schedule_siege(castle_id),
    do: GenServer.cast(via(castle_id), :schedule_siege)

  defp via(castle_id), do: {:via, Registry, {L2E.Siege.Registry, {:castle, castle_id}}}

  defp safe_call(name, msg) do
    GenServer.call(name, msg)
  catch
    :exit, _ -> {:error, :castle_not_found}
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    castle_id = Keyword.fetch!(opts, :castle_id)
    castle_name = Keyword.fetch!(opts, :castle_name)
    owner_clan_id = Keyword.get(opts, :owner_clan_id)

    state = %{
      castle_id: castle_id,
      castle_name: castle_name,
      owner_clan_id: owner_clan_id,
      siege_state: :idle,
      siege_start_at: nil,
      siege_end_timer: nil,
      registered_attackers: MapSet.new(),
      registered_defenders: MapSet.new(),
      relics_held_by: nil,
      # %{clan_id => kill_count} — tracked during :in_siege phase
      kill_scores: %{}
    }

    Logger.info("[Castle] #{castle_name} (id=#{castle_id}) initialized.")
    {:ok, state}
  end

  # ---- Queries ----

  @impl GenServer
  def handle_call(:get_siege_info, _from, state) do
    {:reply, state, state}
  end

  # ---- Registration — only allowed in :preparation ----

  def handle_call({:register_attacker, clan_id}, _from, %{siege_state: :preparation} = state) do
    new_attackers = MapSet.put(state.registered_attackers, clan_id)
    new_state = %{state | registered_attackers: new_attackers}

    Phoenix.PubSub.broadcast(
      L2E.PubSub,
      "world:siege_#{state.castle_id}",
      {:siege_clan_joined, state.castle_id, MapSet.to_list(new_attackers),
       MapSet.to_list(state.registered_defenders)}
    )

    {:reply, :ok, new_state}
  end

  def handle_call({:register_attacker, _clan_id}, _from, state) do
    {:reply, {:error, :not_in_preparation}, state}
  end

  def handle_call({:register_defender, clan_id}, _from, %{siege_state: :preparation} = state) do
    new_defenders = MapSet.put(state.registered_defenders, clan_id)
    new_state = %{state | registered_defenders: new_defenders}

    Phoenix.PubSub.broadcast(
      L2E.PubSub,
      "world:siege_#{state.castle_id}",
      {:siege_clan_joined, state.castle_id, MapSet.to_list(state.registered_attackers),
       MapSet.to_list(new_defenders)}
    )

    {:reply, :ok, new_state}
  end

  def handle_call({:register_defender, _clan_id}, _from, state) do
    {:reply, {:error, :not_in_preparation}, state}
  end

  # ---- State machine casts ----

  @impl GenServer
  def handle_cast(:schedule_siege, %{siege_state: :idle} = state) do
    Logger.info("[Castle] #{state.castle_name} entering preparation phase.")

    defenders =
      if state.owner_clan_id,
        do: MapSet.put(state.registered_defenders, state.owner_clan_id),
        else: state.registered_defenders

    # Siege starts in 2 minutes (testing; production: real weekly schedule)
    Process.send_after(self(), :start_siege, 120_000)

    {:noreply,
     %{
       state
       | siege_state: :preparation,
         siege_start_at: DateTime.utc_now(),
         registered_defenders: defenders
     }}
  end

  def handle_cast(:schedule_siege, state), do: {:noreply, state}

  def handle_cast(:start_siege_manual, state) do
    send(self(), :start_siege)
    {:noreply, state}
  end

  def handle_cast({:relic_captured, by_clan_id}, state) do
    Logger.info("[Castle] #{state.castle_name} relic captured by clan #{by_clan_id}.")
    {:noreply, %{state | relics_held_by: by_clan_id}}
  end

  def handle_cast({:door_destroyed, door_id}, state) do
    Logger.info("[Castle] #{state.castle_name} door #{door_id} destroyed during siege.")

    Phoenix.PubSub.broadcast(
      L2E.PubSub,
      "world:siege_#{state.castle_id}",
      {:siege_announcement, "A door at #{state.castle_name} has been destroyed!"}
    )

    {:noreply, state}
  end

  def handle_cast({:record_kill, attacker_clan_id}, %{siege_state: :in_siege} = state) do
    new_scores = Map.update(state.kill_scores, attacker_clan_id, 1, &(&1 + 1))
    {:noreply, %{state | kill_scores: new_scores}}
  end

  def handle_cast({:record_kill, _}, state), do: {:noreply, state}

  # ---- State machine handle_info transitions ----

  @impl GenServer
  def handle_info(:start_siege, %{siege_state: :preparation} = state) do
    Logger.info("[Castle] #{state.castle_name} siege STARTED.")

    Phoenix.PubSub.broadcast(
      L2E.PubSub,
      "world:siege_start",
      {:siege_started, state.castle_id, state.castle_name}
    )

    L2E.Siege.GuardManager.spawn_guards(state.castle_id)

    # End siege in 2 minutes for testing (production: 2 hours = 7_200_000)
    timer = Process.send_after(self(), :end_siege, 120_000)

    {:noreply, %{state | siege_state: :in_siege, siege_end_timer: timer}}
  end

  def handle_info(:start_siege, state), do: {:noreply, state}

  def handle_info(:end_siege, %{siege_state: :in_siege} = state) do
    Logger.info("[Castle] #{state.castle_name} siege ENDED.")

    winner_clan_id = determine_winner(state)

    new_owner =
      if winner_clan_id != nil and winner_clan_id != state.owner_clan_id do
        announce_new_owner(winner_clan_id, state.castle_name)
        winner_clan_id
      else
        state.owner_clan_id
      end

    Task.start(fn -> sync_castle_owner(state.castle_id, new_owner) end)

    Phoenix.PubSub.broadcast(
      L2E.PubSub,
      "world:siege_end",
      {:siege_ended, state.castle_id, new_owner}
    )

    L2E.Siege.GuardManager.despawn_guards(state.castle_id)

    # Reset to idle in 10 minutes
    Process.send_after(self(), :reset_siege, 600_000)

    {:noreply,
     %{
       state
       | siege_state: :ended,
         owner_clan_id: new_owner,
         relics_held_by: nil,
         siege_end_timer: nil
     }}
  end

  def handle_info(:end_siege, state), do: {:noreply, state}

  def handle_info(:reset_siege, state) do
    Logger.info("[Castle] #{state.castle_name} siege reset to idle.")

    {:noreply,
     %{
       state
       | siege_state: :idle,
         registered_attackers: MapSet.new(),
         registered_defenders: MapSet.new(),
         relics_held_by: nil,
         siege_start_at: nil,
         siege_end_timer: nil
     }}
  end

  def handle_info(_, state), do: {:noreply, state}

  # -----------------------------------------------------------------------
  # Private helpers
  # -----------------------------------------------------------------------

  defp determine_winner(state) do
    holder = state.relics_held_by

    if holder != nil and MapSet.member?(state.registered_attackers, holder) do
      holder
    else
      nil
    end
  end

  # Sync ownership to Manager's ETS so existing SiegeInfo queries stay correct.
  defp sync_castle_owner(_castle_id, nil), do: :ok

  defp sync_castle_owner(castle_id, clan_id) do
    L2E.Siege.Manager.transfer_castle(castle_id, clan_id, "clan_#{clan_id}")
  rescue
    e -> Logger.error("[Castle] Failed to sync castle owner to Manager: #{inspect(e)}")
  end

  defp announce_new_owner(clan_id, castle_name) do
    Phoenix.PubSub.broadcast(
      L2E.PubSub,
      "world:system_message",
      {:system_message, "Clan #{clan_id} has captured #{castle_name}!"}
    )
  end
end
