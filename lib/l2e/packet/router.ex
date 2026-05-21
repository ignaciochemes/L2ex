defmodule L2E.Packet.Router do
  @moduledoc """
  Dispatches decoded client packets to the correct handler.

  This is a plain module — NOT a GenServer. No state, no process.

  ## Two dispatch paths

  ### Pre-auth (no PlayerSession yet)
  Handled directly in this module via private functions.
  Only `ProtocolVersion` is valid before a session exists.
  All other packets are dropped with a warning.

  ### Post-auth (PlayerSession running)
  All packets are forwarded via `GenServer.cast/2`.
  The cast is non-blocking; the ConnectionHandler never waits for the
  session to process the packet. If the session mailbox fills up,
  the client will experience lag — not the server.

  ## Adding a new pre-auth packet

  Add a new `dispatch/3` head matching the specific struct before the
  generic `nil` catch-all. Pattern matching is O(1) — no list scan.
  """

  require Logger

  alias L2E.Packet.Client

  @spec dispatch(struct(), conn_pid :: pid(), session_pid :: pid() | nil) :: :ok

  # ── Pre-auth dispatch ────────────────────────────────────────────────────────
  # Each pre-auth packet gets its own function head.
  # No list membership check, no MapSet — pure pattern match.

  def dispatch(%Client.ProtocolVersion{} = packet, conn_pid, nil) do
    Logger.debug("[Router] ProtocolVersion=#{packet.version}")

    case L2E.Session.Supervisor.start_session(conn_pid) do
      {:ok, session_pid} ->
        send(conn_pid, {:session_ready, session_pid})

      {:error, reason} ->
        Logger.error("[Router] Failed to start session: #{inspect(reason)}")
    end

    :ok
  end

  # AuthLogin arrives before the session is ready — forward to session once available.
  # In practice the session has already been started by ProtocolVersion, so
  # session_pid will be set. However if it somehow arrives pre-session, drop it.
  def dispatch(%Client.AuthLogin{} = packet, _conn_pid, nil) do
    Logger.warning("[Router] AuthLogin received with no session — dropping: #{packet.login_name}")
    :ok
  end

  # Any other packet before auth — close-worthy but we just drop for now
  def dispatch(packet, _conn_pid, nil) do
    Logger.warning("[Router] Pre-auth drop: #{inspect(packet.__struct__)}")
    :ok
  end

  # ── Post-auth dispatch ───────────────────────────────────────────────────────
  # Forward everything to PlayerSession. The session owns the handler logic.
  # Adding a new packet requires zero changes here.

  def dispatch(packet, _conn_pid, session_pid) do
    GenServer.cast(session_pid, {:packet, packet})
  end
end
