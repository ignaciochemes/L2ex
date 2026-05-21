defmodule L2E.LoginServer.AccountStore do
  @moduledoc """
  ETS-backed store for pending game-server sessions.

  ## Lifecycle

  When the Login Server issues a `PlayOk`, it writes an entry here:
  `username → {SessionKey, expiry_monotonic_ms}`.

  When the Game Server receives `AuthLogin`, it calls `pop/3`. If the
  username and PlayOk pair match a non-expired entry, the entry is consumed
  and the session key is returned. Single-use: once popped it is gone.

  The `cleanup` timer removes stale entries every `@ttl_ms` milliseconds.

  ## OTP design
  A single named `GenServer` owns the ETS table. The table is `:public` so
  `pop/3` can read/delete from any process without a GenServer.call round-trip.
  Writes go through the GenServer to keep semantics simple.
  """

  use GenServer
  require Logger

  alias L2E.LoginServer.SessionKey

  @table :login_pending_sessions
  # Session window: 30 s to connect to game server after PlayOk
  @ttl_ms 30_000

  # -------------------------------------------------------------------
  # Public API — called from any process
  # -------------------------------------------------------------------

  @doc "Store a session key for `username`. Called by the login connection handler."
  @spec put(String.t(), SessionKey.t()) :: :ok
  def put(username, %SessionKey{} = session_key) do
    expiry = System.monotonic_time(:millisecond) + @ttl_ms
    :ets.insert(@table, {username, session_key, expiry})
    :ok
  end

  @doc """
  Consume and return the session key for `username` if it exists and the
  play-ok pair matches.  Returns `{:ok, session_key}` or `{:error, reason}`.
  """
  @spec pop(String.t(), integer(), integer()) ::
          {:ok, SessionKey.t()} | {:error, :not_found | :invalid_or_expired}
  def pop(username, play_ok1, play_ok2) do
    case :ets.lookup(@table, username) do
      [{^username, session_key, expiry}] ->
        now = System.monotonic_time(:millisecond)

        if now < expiry and SessionKey.check_play_pair(session_key, play_ok1, play_ok2) do
          :ets.delete(@table, username)
          {:ok, session_key}
        else
          {:error, :invalid_or_expired}
        end

      [] ->
        {:error, :not_found}
    end
  end

  # -------------------------------------------------------------------
  # GenServer lifecycle
  # -------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    Logger.debug("[AccountStore] Cleanup run at #{now}")
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup, do: Process.send_after(self(), :cleanup, @ttl_ms)
end
