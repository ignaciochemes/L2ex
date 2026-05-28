defmodule L2E.ClanHall.Hall do
  @moduledoc """
  M125: Per-hall GenServer tracking ownership/rental state.

  States: :empty | :owned (derived from owner_clan_id)

  Monthly rental is deducted on a timer; if clan can't pay, hall reverts to :empty.
  DB fields: hall_id, hall_name, clan_id (0=no owner), paid_until, is_paid.
  """
  use GenServer
  require Logger

  # 30 days in ms (real Interlude cadence)
  @monthly_rent_ms 30 * 24 * 60 * 60 * 1000

  defp rent_interval_ms,
    do: Application.get_env(:l2e, :clan_hall_rent_ms, @monthly_rent_ms)

  # owner_clan_id: nil = no owner (maps to clan_id=0 in DB)
  # owner_clan_name: runtime-only, not persisted
  defstruct [:hall_id, :name, :owner_clan_id, :owner_clan_name, :functions, :paid_until]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: via(opts[:hall_id]))

  def get_info(hall_id), do: GenServer.call(via(hall_id), :get_info)

  def set_owner(hall_id, clan_id, clan_name),
    do: GenServer.cast(via(hall_id), {:set_owner, clan_id, clan_name})

  def clear_owner(hall_id), do: GenServer.cast(via(hall_id), :clear_owner)

  def activate_function(hall_id, function_type, level),
    do: GenServer.cast(via(hall_id), {:activate_function, function_type, level})

  def get_functions(hall_id), do: GenServer.call(via(hall_id), :get_functions)

  defp via(hall_id), do: {:via, Registry, {L2E.ClanHall.Registry, hall_id}}

  # ---------------------------------------------------------------------------
  # Init
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    hall_id = opts[:hall_id]
    db_hall = L2E.Repo.get_by(L2E.DB.ClanHall, hall_id: hall_id)

    state =
      if db_hall do
        owner = if db_hall.clan_id != 0, do: db_hall.clan_id, else: nil

        %__MODULE__{
          hall_id: hall_id,
          name: db_hall.hall_name,
          owner_clan_id: owner,
          owner_clan_name: nil,
          functions: %{},
          paid_until: db_hall.paid_until
        }
      else
        Logger.warning("[ClanHall] No DB record for hall_id=#{hall_id}, using defaults")

        %__MODULE__{
          hall_id: hall_id,
          name: "Hall #{hall_id}",
          owner_clan_id: nil,
          owner_clan_name: nil,
          functions: %{},
          paid_until: nil
        }
      end

    if state.owner_clan_id != nil do
      schedule_rent()
    end

    {:ok, state}
  end

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def handle_call(:get_info, _from, state), do: {:reply, state, state}
  def handle_call(:get_functions, _from, state), do: {:reply, state.functions, state}

  @impl true
  def handle_cast({:set_owner, clan_id, clan_name}, state) do
    paid_until =
      DateTime.utc_now()
      |> DateTime.add(30, :day)
      |> DateTime.truncate(:second)

    new_state = %{
      state
      | owner_clan_id: clan_id,
        owner_clan_name: clan_name,
        paid_until: paid_until
    }

    persist(new_state)
    schedule_rent()

    Phoenix.PubSub.broadcast(
      L2E.PubSub,
      "world:clan_hall",
      {:clan_hall_owner_changed, state.hall_id, clan_id, clan_name}
    )

    {:noreply, new_state}
  end

  def handle_cast(:clear_owner, state) do
    new_state = %{
      state
      | owner_clan_id: nil,
        owner_clan_name: nil,
        functions: %{},
        paid_until: nil
    }

    persist(new_state)

    Phoenix.PubSub.broadcast(
      L2E.PubSub,
      "world:clan_hall",
      {:clan_hall_owner_changed, state.hall_id, nil, nil}
    )

    {:noreply, new_state}
  end

  def handle_cast({:activate_function, type, level}, state) do
    func = L2E.ClanHall.Function.build(type, level)
    new_functions = Map.put(state.functions, type, func)
    Process.send_after(self(), {:function_expired, type}, func.duration_ms)
    {:noreply, %{state | functions: new_functions}}
  end

  @impl true
  def handle_info(:rent_due, state) do
    if state.owner_clan_id != nil do
      # TODO: deduct lease cost from clan warehouse adena (requires Clan.Warehouse integration)
      Logger.info(
        "[ClanHall #{state.hall_id}] Rent due for clan #{state.owner_clan_id} — adena deduction pending warehouse integration"
      )

      schedule_rent()
    end

    {:noreply, state}
  end

  def handle_info({:function_expired, type}, state) do
    Logger.debug("[ClanHall #{state.hall_id}] Function #{type} expired")
    {:noreply, %{state | functions: Map.delete(state.functions, type)}}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp schedule_rent, do: Process.send_after(self(), :rent_due, rent_interval_ms())

  defp persist(state) do
    case L2E.Repo.get_by(L2E.DB.ClanHall, hall_id: state.hall_id) do
      nil ->
        :ok

      record ->
        record
        |> L2E.DB.ClanHall.changeset(%{
          clan_id: state.owner_clan_id || 0,
          paid_until: state.paid_until,
          is_paid: state.owner_clan_id != nil
        })
        |> L2E.Repo.update()
    end
  end
end
