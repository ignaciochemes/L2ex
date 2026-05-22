defmodule L2E.Duel.Manager do
  @moduledoc """
  ETS-backed registry of active duels.

  Tracks: duel_id → duel_pid, attacker_id → duel_id, defender_id → duel_id

  OTP design: GenServer with ETS for O(1) lookup. Each duel is a separate
  supervised process (L2E.Duel.Session) under L2E.Duel.Supervisor.
  """

  use GenServer

  @table :duel_registry

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Register a new duel between two players."
  def register(duel_id, duel_pid, attacker_char_id, defender_char_id) do
    GenServer.cast(__MODULE__, {:register, duel_id, duel_pid, attacker_char_id, defender_char_id})
  end

  @doc "Get duel pid by duel_id."
  def get(duel_id) do
    case :ets.lookup(@table, {:duel, duel_id}) do
      [{_, pid}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc "Get duel_id for a player (by char_id). Returns nil if not in duel."
  def get_for_player(char_id) do
    case :ets.lookup(@table, {:player, char_id}) do
      [{_, duel_id}] -> {:ok, duel_id}
      [] -> {:error, :not_in_duel}
    end
  end

  @doc "Check if a player is currently in a duel."
  def in_duel?(char_id) do
    :ets.member(@table, {:player, char_id})
  end

  @doc "Remove a duel from the registry (called when duel ends)."
  def unregister(duel_id) do
    GenServer.cast(__MODULE__, {:unregister, duel_id})
  end

  @doc "Generate a unique duel ID."
  def new_duel_id do
    GenServer.call(__MODULE__, :new_duel_id)
  end

  @impl GenServer
  def init(_) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, %{counter: 0}}
  end

  @impl GenServer
  def handle_call(:new_duel_id, _from, state) do
    id = state.counter + 1
    {:reply, id, %{state | counter: id}}
  end

  @impl GenServer
  def handle_cast({:register, duel_id, duel_pid, attacker_id, defender_id}, state) do
    :ets.insert(@table, {{:duel, duel_id}, duel_pid})
    :ets.insert(@table, {{:player, attacker_id}, duel_id})
    :ets.insert(@table, {{:player, defender_id}, duel_id})
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:unregister, duel_id}, state) do
    case :ets.lookup(@table, {:duel, duel_id}) do
      [{_, _pid}] ->
        :ets.delete(@table, {:duel, duel_id})
        # Remove player entries — iterate to find them
        :ets.match_delete(@table, {{:player, :_}, duel_id})

      [] ->
        :ok
    end

    {:noreply, state}
  end
end
