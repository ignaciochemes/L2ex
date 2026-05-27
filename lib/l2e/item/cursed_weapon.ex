defmodule L2E.Item.CursedWeapon do
  @moduledoc """
  GenServer representing a single Cursed Weapon (Zariche or Akamanah).

  Two instances are started on boot — one per weapon ID — under
  L2E.Item.CursedWeapon.Supervisor, registered by weapon_id in
  L2E.Item.CursedWeapon.Registry.

  Weapon IDs:
    8190 — Zariche
    8689 — Akamanah

  Possession rules:
    - Only one player may possess a given weapon at a time.
    - Possession expires after 6 hours (21600 seconds).
    - A decay check fires every 10 minutes via Process.send_after.
    - On expiry the weapon is deactivated and a PubSub broadcast is sent
      on the topic "world:cursed_weapon".

  Stage progression (based on kill count):
    kills  0 → stage 0
    kills 10 → stage 1
    kills 20 → stage 2
    kills 30 → stage 3
  """

  use GenServer
  require Logger

  @weapon_ids [8190, 8689]
  @possession_limit 21_600
  @decay_interval 600_000

  @stage_thresholds [{30, 3}, {20, 2}, {10, 1}, {0, 0}]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def weapon_ids, do: @weapon_ids

  def start_link(weapon_id) when weapon_id in @weapon_ids do
    GenServer.start_link(__MODULE__, weapon_id,
      name: {:via, Registry, {L2E.Item.CursedWeapon.Registry, weapon_id}}
    )
  end

  @doc "Attempt to give possession of weapon_id to char_id (pid = player session pid)."
  @spec activate(integer(), integer(), pid()) :: :ok | {:error, :already_owned}
  def activate(weapon_id, char_id, pid) do
    GenServer.call(via(weapon_id), {:activate, char_id, pid})
  end

  @doc "Remove possession of weapon_id (called on death, expiry, or GM intervention)."
  @spec deactivate(integer()) :: :ok
  def deactivate(weapon_id) do
    GenServer.call(via(weapon_id), :deactivate)
  end

  @doc "Record a kill on weapon_id. Returns the new stage."
  @spec add_kill(integer()) :: {:ok, 0..3} | {:error, :not_possessed}
  def add_kill(weapon_id) do
    GenServer.call(via(weapon_id), :add_kill)
  end

  @doc "Return weapon state map for weapon_id."
  @spec get_info(integer()) :: {:ok, map()} | {:error, :not_found}
  def get_info(weapon_id) do
    case GenServer.whereis(via(weapon_id)) do
      nil -> {:error, :not_found}
      _ -> GenServer.call(via(weapon_id), :get_info)
    end
  end

  @spec is_possessed?(integer()) :: boolean()
  def is_possessed?(weapon_id) do
    case get_info(weapon_id) do
      {:ok, %{owner_char_id: id}} when not is_nil(id) -> true
      _ -> false
    end
  end

  @doc "Return a list of currently active (possessed) weapon info maps."
  @spec get_active_weapons() :: [map()]
  def get_active_weapons do
    @weapon_ids
    |> Enum.flat_map(fn wid ->
      case get_info(wid) do
        {:ok, %{owner_char_id: id} = info} when not is_nil(id) -> [info]
        _ -> []
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(weapon_id) do
    state = %{
      weapon_id: weapon_id,
      owner_char_id: nil,
      owner_pid: nil,
      stage: 0,
      kills: 0,
      activated_at: nil,
      decay_timer: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:activate, char_id, pid}, _from, state) do
    if state.owner_char_id != nil do
      {:reply, {:error, :already_owned}, state}
    else
      now = System.system_time(:second)
      timer = Process.send_after(self(), :decay_check, @decay_interval)

      new_state = %{
        state
        | owner_char_id: char_id,
          owner_pid: pid,
          stage: 0,
          kills: 0,
          activated_at: now,
          decay_timer: timer
      }

      broadcast(:activated, new_state)

      Logger.info("[CursedWeapon] weapon_id=#{state.weapon_id} activated by char_id=#{char_id}")

      {:reply, :ok, new_state}
    end
  end

  def handle_call(:deactivate, _from, state) do
    new_state = clear_ownership(state)
    {:reply, :ok, new_state}
  end

  def handle_call(:add_kill, _from, %{owner_char_id: nil} = state) do
    {:reply, {:error, :not_possessed}, state}
  end

  def handle_call(:add_kill, _from, state) do
    new_kills = state.kills + 1
    new_stage = stage_for_kills(new_kills)

    new_state = %{state | kills: new_kills, stage: new_stage}

    if new_stage != state.stage do
      broadcast(:stage_changed, new_state)
    end

    {:reply, {:ok, new_stage}, new_state}
  end

  def handle_call(:get_info, _from, state) do
    info = %{
      weapon_id: state.weapon_id,
      owner_char_id: state.owner_char_id,
      owner_pid: state.owner_pid,
      stage: state.stage,
      kills: state.kills,
      activated_at: state.activated_at,
      object_id: state.weapon_id
    }

    {:reply, {:ok, info}, state}
  end

  @impl true
  def handle_info(:decay_check, %{owner_char_id: nil} = state) do
    {:noreply, state}
  end

  def handle_info(:decay_check, state) do
    now = System.system_time(:second)
    elapsed = now - state.activated_at

    if elapsed >= @possession_limit do
      Logger.info(
        "[CursedWeapon] weapon_id=#{state.weapon_id} expired after #{elapsed}s — deactivating"
      )

      new_state = clear_ownership(state)
      broadcast(:expired, new_state)
      {:noreply, new_state}
    else
      timer = Process.send_after(self(), :decay_check, @decay_interval)
      {:noreply, %{state | decay_timer: timer}}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp via(weapon_id) do
    {:via, Registry, {L2E.Item.CursedWeapon.Registry, weapon_id}}
  end

  defp clear_ownership(state) do
    if state.decay_timer, do: Process.cancel_timer(state.decay_timer)

    if state.owner_pid && Process.alive?(state.owner_pid) do
      send(
        state.owner_pid,
        {:cursed_weapon_notification, "Your cursed weapon has been taken away."}
      )
    end

    %{
      state
      | owner_char_id: nil,
        owner_pid: nil,
        stage: 0,
        kills: 0,
        activated_at: nil,
        decay_timer: nil
    }
  end

  defp broadcast(event, state) do
    Phoenix.PubSub.broadcast(L2E.PubSub, "world:cursed_weapon", {
      :cursed_weapon_event,
      event,
      %{
        weapon_id: state.weapon_id,
        owner_char_id: state.owner_char_id,
        stage: state.stage
      }
    })
  end

  defp stage_for_kills(kills) do
    Enum.find_value(@stage_thresholds, 0, fn {threshold, stage} ->
      if kills >= threshold, do: stage
    end)
  end
end

defmodule L2E.Item.CursedWeapon.Supervisor do
  @moduledoc """
  DynamicSupervisor that owns the two CursedWeapon GenServer processes.
  Started by L2E.Application; spawns one process per weapon ID on init.
  """

  use Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    children =
      Enum.map(L2E.Item.CursedWeapon.weapon_ids(), fn weapon_id ->
        Supervisor.child_spec({L2E.Item.CursedWeapon, weapon_id},
          id: {L2E.Item.CursedWeapon, weapon_id}
        )
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
