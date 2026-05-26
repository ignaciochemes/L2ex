defmodule L2E.Network.FloodProtector do
  @moduledoc """
  Per-connection packet rate limiting using a sliding window approach.

  Tracks packet timestamps per opcode and validates against configurable
  thresholds. Uses a sliding window (last N seconds) to count packets.

  ## Configuration

  In `config.exs`:
  ```elixir
  config :l2e,
    flood_protectors: [
      game_server: [
        move_to_location: [threshold: 10, window_secs: 10],
        request_action: [threshold: 50, window_secs: 60]
      ]
    ]
  ```

  ## State

  ```elixir
  %{
    "0x01" => [timestamp1, timestamp2, ...],  # timestamps in milliseconds
    "0x0A" => [...]
  }
  ```

  Only timestamps within the last `window_secs` are kept.
  """

  require Logger

  @doc """
  Create initial flood protector state.
  """
  def new_state do
    %{}
  end

  @doc """
  Check if a packet should be allowed or dropped due to flood limits.

  Returns:
  - `{:ok, new_state}` if packet is allowed
  - `{:error, :flood_detected, reason}` if packet should be dropped

  The new_state includes updated counters with old timestamps pruned.
  """
  @spec check_packet(map(), integer(), atom()) ::
          {:ok, map()} | {:error, :flood_detected, String.t()}
  def check_packet(state, opcode, opcode_name \\ nil) do
    config = get_opcode_config(opcode_name || opcode)
    now_ms = System.monotonic_time(:millisecond)

    # Get or initialize the timestamp list for this opcode
    timestamps = Map.get(state, opcode, [])

    # Remove timestamps older than the window
    window_ms = config.window_secs * 1000
    recent_timestamps = Enum.filter(timestamps, &(now_ms - &1 < window_ms))

    # Check if we exceed the threshold
    count = length(recent_timestamps)

    if count >= config.threshold do
      reason =
        "Flood detected on opcode #{format_opcode(opcode)}: " <>
          "#{count} packets in #{config.window_secs}s (threshold: #{config.threshold})"

      Logger.warning("[FloodProtector] #{reason}")
      {:error, :flood_detected, reason}
    else
      # Add current timestamp and update state
      new_timestamps = [now_ms | recent_timestamps]
      new_state = Map.put(state, opcode, new_timestamps)
      {:ok, new_state}
    end
  end

  @doc """
  Get configuration for a specific opcode from application config.

  Returns a map with `:threshold` and `:window_secs` keys.
  Falls back to default if opcode is not explicitly configured.
  """
  @spec get_opcode_config(integer() | atom()) :: %{
          threshold: pos_integer(),
          window_secs: pos_integer()
        }
  def get_opcode_config(opcode) do
    config = Application.get_env(:l2e, :flood_protectors, %{})
    game_server_config = config[:game_server] || []

    # Try to find the opcode in the config
    # Config is typically a keyword list like [move_to_location: [...]]
    case Enum.find(game_server_config, fn {_key, _val} -> true end) do
      nil ->
        default_config()

      _ ->
        # Look for explicit opcode config
        case Enum.find(game_server_config, fn {_name, cfg} ->
               cfg[:opcode] == opcode
             end) do
          {_name, cfg} ->
            %{threshold: cfg[:threshold] || 100, window_secs: cfg[:window_secs] || 10}

          nil ->
            default_config()
        end
    end
  end

  @doc """
  Get default flood protection config.
  """
  @spec default_config() :: %{threshold: pos_integer(), window_secs: pos_integer()}
  def default_config do
    %{threshold: 100, window_secs: 10}
  end

  defp format_opcode(opcode) when is_integer(opcode) do
    "0x#{Integer.to_string(opcode, 16)}"
  end

  defp format_opcode(opcode) do
    inspect(opcode)
  end
end
