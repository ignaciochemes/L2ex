defmodule L2E.LoginServer.IpRateLimiter do
  @moduledoc """
  Per-IP packet rate limiting for the login server.

  Tracks authentication attempts per IP address using ETS for O(1) lookup.
  Implements sliding window counting to enforce limits like "max 5 auth attempts per 5 minutes".

  ## Configuration

  In `config.exs`:
  ```elixir
  config :l2e,
    flood_protectors: [
      login_server: [
        auth_login: [threshold: 5, window_secs: 300]
      ]
    ]
  ```

  ## ETS Table Design

  Table: `:ip_rate_limits` (public, bag)
  Records: `{ip, timestamp_ms}`

  A "bag" allows multiple entries with the same IP key, which makes it
  easy to count and clean up old entries.
  """

  use GenServer
  require Logger

  @table :ip_rate_limits
  # Periodic cleanup interval (milliseconds)
  @cleanup_interval_ms 60_000

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if an IP is within rate limits for a given action.

  Returns:
  - `:ok` if the request is allowed
  - `{:error, :rate_limit_exceeded}` if the limit has been reached
  """
  @spec check_ip(String.t() | :inet.ip_address()) :: :ok | {:error, :rate_limit_exceeded}
  def check_ip(ip) do
    ip_str = format_ip(ip)
    config = get_ip_config()
    now_ms = System.monotonic_time(:millisecond)

    # Count recent entries for this IP
    window_ms = config.window_secs * 1000
    cutoff_ms = now_ms - window_ms

    # Query ETS for recent entries
    case :ets.select(@table, [
      {
        {:"$1", :"$2"},
        [
          {:==, :"$1", ip_str},
          {:>, :"$2", cutoff_ms}
        ],
        [:"$2"]
      }
    ]) do
      [] ->
        # First entry
        :ets.insert(@table, {ip_str, now_ms})
        :ok

      recent_timestamps ->
        count = length(recent_timestamps)

        if count >= config.threshold do
          Logger.warn("[IpRateLimiter] Rate limit exceeded for IP #{ip_str}: " <>
            "#{count} requests in #{config.window_secs}s (threshold: #{config.threshold})")
          {:error, :rate_limit_exceeded}
        else
          # Add current timestamp
          :ets.insert(@table, {ip_str, now_ms})
          :ok
        end
    end
  end

  @doc """
  Manually trigger cleanup of old entries. Typically called by the periodic timer.
  """
  def cleanup do
    GenServer.cast(__MODULE__, :cleanup)
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    # Create the ETS table if it doesn't exist
    :ets.new(@table, [:public, :bag, :named_table])
    Logger.info("[IpRateLimiter] ETS table '#{@table}' created")

    # Start periodic cleanup timer
    timer = Process.send_after(self(), :cleanup_tick, @cleanup_interval_ms)

    {:ok, %{timer: timer}}
  end

  @impl GenServer
  def handle_cast(:cleanup, state) do
    cleanup_old_entries()
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:cleanup_tick, state) do
    cleanup_old_entries()
    # Reschedule
    timer = Process.send_after(self(), :cleanup_tick, @cleanup_interval_ms)
    {:noreply, %{state | timer: timer}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -----------------------------------------------------------------------
  # Helpers
  # -----------------------------------------------------------------------

  defp cleanup_old_entries do
    config = get_ip_config()
    now_ms = System.monotonic_time(:millisecond)
    window_ms = config.window_secs * 1000
    cutoff_ms = now_ms - window_ms

    # Find and delete all entries older than the window
    :ets.select_delete(@table, [
      {
        {:"$1", :"$2"},
        [{:<, :"$2", cutoff_ms}],
        [true]
      }
    ])
  end

  @doc """
  Get IP rate limiter configuration from application config.
  """
  @spec get_ip_config() :: %{threshold: pos_integer(), window_secs: pos_integer()}
  def get_ip_config do
    config = Application.get_env(:l2e, :flood_protectors, %{})
    login_config = config[:login_server] || []
    auth_config = login_config[:auth_login] || []

    %{
      threshold: auth_config[:threshold] || 5,
      window_secs: auth_config[:window_secs] || 300
    }
  end

  defp format_ip(ip) when is_tuple(ip) do
    ip
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  defp format_ip(ip) when is_binary(ip) do
    ip
  end

  defp format_ip(ip) do
    inspect(ip)
  end
end
