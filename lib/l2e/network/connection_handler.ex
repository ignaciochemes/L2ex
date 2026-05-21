defmodule L2E.Network.ConnectionHandler do
  @moduledoc """
  One process per TCP connection, managed by ThousandIsland.

  Responsibilities:
  - Own the process-local cipher state (never shared)
  - Buffer incomplete TCP frames (2-byte little-endian length prefix)
  - Decrypt and decode each complete packet
  - Dispatch pre-auth packets directly (before PlayerSession exists)
  - Forward post-auth packets to PlayerSession via cast
  - Write outbound packets sent back from PlayerSession

  Packet frame format:
    <<size::little-16, payload::binary>>
  where `size` includes the 2 header bytes.
  """

  use ThousandIsland.Handler
  require Logger

  alias L2E.Crypto.SessionCrypt
  alias L2E.Packet.{Decoder, Encoder, Router}

  # Maximum allowed payload size (bytes). Frames larger than this are
  # immediately rejected — prevents memory exhaustion from malformed clients.
  @max_packet_size 8_192

  # Milliseconds before a connection that never completes handshake is closed.
  @handshake_timeout_ms 15_000

  @type state :: %{
          session_pid: pid() | nil,
          crypt: SessionCrypt.t(),
          buffer: binary(),
          handshake_timer: reference() | nil
        }

  # -----------------------------------------------------------------------
  # ThousandIsland.Handler callbacks
  # -----------------------------------------------------------------------

  @impl ThousandIsland.Handler
  def handle_connection(socket, _opts) do
    key_8 = SessionCrypt.random_key_bytes()
    crypt = SessionCrypt.new(key_8)
    timer = Process.send_after(self(), :handshake_timeout, @handshake_timeout_ms)

    state = %{
      session_pid: nil,
      crypt: crypt,
      buffer: <<>>,
      handshake_timer: timer
    }

    :ok = ThousandIsland.Socket.send(socket, build_key_packet_frame(key_8, crypt))

    {:continue, state}
  end

  @impl ThousandIsland.Handler
  def handle_data(data, socket, state) do
    full_buffer = state.buffer <> data

    case drain_packets(full_buffer, state, socket) do
      {:ok, new_state} ->
        {:continue, new_state}

      {:error, reason} ->
        Logger.warning("[ConnectionHandler] Closing on framing error: #{inspect(reason)}")
        {:close, state}
    end
  end

  @impl ThousandIsland.Handler
  def handle_close(_socket, state) do
    if state.session_pid do
      GenServer.cast(state.session_pid, :connection_closed)
    end

    :ok
  end

  @impl ThousandIsland.Handler
  def handle_error(reason, _socket, _state) do
    Logger.warning("[ConnectionHandler] Socket error: #{inspect(reason)}")
    :ok
  end

  # Receives {:send_packet, struct} from PlayerSession
  # Receives {:session_ready, pid} from Router after session spawn
  @impl GenServer
  def handle_info({:send_packet, packet}, {socket, state}) do
    case Encoder.encode(packet) do
      {:ok, payload} ->
        {encrypted, new_crypt} = SessionCrypt.encrypt(payload, state.crypt)
        :ok = ThousandIsland.Socket.send(socket, frame(encrypted))
        {:noreply, {socket, %{state | crypt: new_crypt}}}

      {:error, reason} ->
        Logger.error("[ConnectionHandler] Encode failed: #{inspect(reason)}")
        {:noreply, {socket, state}}
    end
  end

  def handle_info({:session_ready, pid}, {socket, state}) do
    Logger.debug("[ConnectionHandler] Session #{inspect(pid)} registered")
    # Cancel handshake timeout — client proved it speaks the protocol
    if state.handshake_timer, do: Process.cancel_timer(state.handshake_timer)
    {:noreply, {socket, %{state | session_pid: pid, handshake_timer: nil}}}
  end

  def handle_info(:handshake_timeout, {socket, state}) do
    if state.session_pid == nil do
      Logger.warning("[ConnectionHandler] Handshake timeout — closing connection")
      {:close, {socket, state}}
    else
      {:noreply, {socket, state}}
    end
  end

  def handle_info(msg, {socket, state}) do
    Logger.debug("[ConnectionHandler] Unexpected message: #{inspect(msg)}")
    {:noreply, {socket, state}}
  end

  # -----------------------------------------------------------------------
  # Packet framing
  # -----------------------------------------------------------------------

  # Complete packet available — extract and process, then recurse
  defp drain_packets(<<size::little-16, _rest::binary>>, _state, _socket)
       when size - 2 > @max_packet_size do
    Logger.warning(
      "[ConnectionHandler] Oversized packet (#{size - 2} bytes) — dropping connection"
    )

    {:error, :packet_too_large}
  end

  defp drain_packets(<<size::little-16, rest::binary>> = _buf, state, socket)
       when byte_size(rest) >= size - 2 do
    payload_size = size - 2
    <<payload::binary-size(payload_size), remaining::binary>> = rest

    {decrypted, new_crypt} = SessionCrypt.decrypt(payload, state.crypt)
    new_state = %{state | crypt: new_crypt}

    case process_packet(decrypted, socket, new_state) do
      {:ok, updated_state} ->
        drain_packets(remaining, %{updated_state | buffer: remaining}, socket)

      {:error, _} = err ->
        err
    end
  end

  # Not enough data yet — store remaining bytes and wait
  defp drain_packets(remaining, state, _socket) do
    {:ok, %{state | buffer: remaining}}
  end

  defp process_packet(<<opcode::8, body::binary>>, _socket, state) do
    case Decoder.decode(opcode, body) do
      {:ok, packet} ->
        Router.dispatch(packet, self(), state.session_pid)
        {:ok, state}

      {:error, :unknown_opcode} ->
        Logger.debug("[ConnectionHandler] Unknown opcode 0x#{Integer.to_string(opcode, 16)}")
        {:ok, state}

      {:error, :malformed} ->
        {:error, :malformed_packet}
    end
  end

  defp process_packet(<<>>, _socket, state), do: {:ok, state}

  # -----------------------------------------------------------------------
  # KeyPacket (server → client, first frame, UNENCRYPTED)
  # -----------------------------------------------------------------------

  # Build the framed KeyPacket. The cipher is not yet enabled so `encrypt/2`
  # is a no-op on the first call — we call it here to advance the `enabled` flag
  # so that all *subsequent* outbound packets (sent via PlayerSession) are encrypted.
  defp build_key_packet_frame(key_8, crypt) do
    alias L2E.Packet.Server.KeyPacket
    payload = KeyPacket.encode(%KeyPacket{key: key_8})
    # First encrypt call is no-op (transitions enabled: false → true)
    {enc_payload, _} = L2E.Crypto.SessionCrypt.encrypt(payload, crypt)
    frame(enc_payload)
  end

  defp frame(payload) do
    size = byte_size(payload) + 2
    <<size::little-16, payload::binary>>
  end
end
