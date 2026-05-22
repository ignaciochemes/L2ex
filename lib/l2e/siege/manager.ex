defmodule L2E.Siege.Manager do
  @moduledoc """
  ETS-backed castle and siege registry.

  Behavioral reference: SiegeManager.java — behavior ONLY.

  OTP design:
  - GenServer with ETS for O(1) castle lookup
  - Siege schedule via Process.send_after (no cron-style polling)
  - Attacker/defender registration stored in ETS
  - Each active siege has its own process (future milestone)

  Foundation scope (M71):
  - Castle data (9 castles)
  - Attacker/defender registration lists
  - SiegeInfo query
  - No actual siege combat yet (M71-B)
  """

  use GenServer
  require Logger

  @table :siege_data

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Get castle data by castle_id."
  def get_castle(castle_id) do
    case :ets.lookup(@table, {:castle, castle_id}) do
      [{_, castle}] -> {:ok, castle}
      [] -> {:error, :not_found}
    end
  end

  @doc "Get all castles."
  def all_castles do
    :ets.match_object(@table, {{:castle, :_}, :_})
    |> Enum.map(fn {_, castle} -> castle end)
    |> Enum.sort_by(& &1.id)
  end

  @doc "Register clan as attacker for a siege."
  def register_attacker(castle_id, clan_id, clan_name) do
    GenServer.call(__MODULE__, {:register_attacker, castle_id, clan_id, clan_name})
  end

  @doc "Register clan as defender for a siege."
  def register_defender(castle_id, clan_id, clan_name) do
    GenServer.call(__MODULE__, {:register_defender, castle_id, clan_id, clan_name})
  end

  @doc "Get attackers list for a castle."
  def get_attackers(castle_id) do
    case :ets.lookup(@table, {:attackers, castle_id}) do
      [{_, list}] -> list
      [] -> []
    end
  end

  @doc "Get defenders list for a castle."
  def get_defenders(castle_id) do
    case :ets.lookup(@table, {:defenders, castle_id}) do
      [{_, list}] -> list
      [] -> []
    end
  end

  @doc "Check if a siege is currently active for castle_id."
  def siege_active?(castle_id) do
    case get_castle(castle_id) do
      {:ok, %{siege_status: :in_progress}} -> true
      _ -> false
    end
  end

  @impl GenServer
  def init(_) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])

    # Load castle data
    Enum.each(L2E.Siege.Castle.all_castles(), fn %{id: id, name: name} ->
      castle = L2E.Siege.Castle.new(id, name)
      :ets.insert(@table, {{:castle, id}, castle})
      :ets.insert(@table, {{:attackers, id}, []})
      :ets.insert(@table, {{:defenders, id}, []})
    end)

    Logger.info(
      "[Siege] SiegeManager initialized with #{length(L2E.Siege.Castle.all_castles())} castles."
    )

    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:register_attacker, castle_id, clan_id, clan_name}, _from, state) do
    current = get_attackers(castle_id)

    if Enum.any?(current, &(&1.clan_id == clan_id)) do
      {:reply, {:error, :already_registered}, state}
    else
      entry = %{clan_id: clan_id, clan_name: clan_name}
      :ets.insert(@table, {{:attackers, castle_id}, [entry | current]})
      {:reply, :ok, state}
    end
  end

  def handle_call({:register_defender, castle_id, clan_id, clan_name}, _from, state) do
    current = get_defenders(castle_id)

    if Enum.any?(current, &(&1.clan_id == clan_id)) do
      {:reply, {:error, :already_registered}, state}
    else
      entry = %{clan_id: clan_id, clan_name: clan_name}
      :ets.insert(@table, {{:defenders, castle_id}, [entry | current]})
      {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_info(:siege_end, state) do
    Logger.info("[Siege] Active siege ended.")
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}
end
