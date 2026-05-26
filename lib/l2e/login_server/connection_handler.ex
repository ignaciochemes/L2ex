defmodule L2E.LoginServer.ConnectionHandler do
  @moduledoc """
  ThousandIsland handler for login-server connections on port 2106.

  ## Auth state machine

  ```
  :connected  --[TCP connect]-->
    send Init (unencrypted, carries RSA modulus + session BF key)
  :wait_auth  --[RequestAuthLogin]--> RSA-decrypt creds → send LoginOk (static BF key encrypt)
  :wait_server_select  --[RequestServerList]--> send ServerList (session BF key encrypt)
                       --[RequestServerLogin]--> store in AccountStore → send PlayOk → close
  ```

  ## Framing
  L2 uses a 2-byte little-endian length prefix (inclusive of the 2 prefix bytes).
  A packet body `P` is sent as `<<byte_size(P)+2::little-16, P::binary>>`.
  """

  use ThousandIsland.Handler

  require Logger

  alias L2E.LoginServer.{Crypto, RsaKey, SessionKey, AccountStore, AuthService}
  alias L2E.LoginServer.Packet.{Decoder, Encoder}
  alias L2E.LoginServer.Packet.Client.{RequestAuthLogin, RequestServerList, RequestServerLogin}
  alias L2E.LoginServer.Packet.Client.AuthGameGuard

  alias L2E.LoginServer.Packet.Server.{
    Init,
    LoginOk,
    LoginFail,
    GGAuth,
    ServerList,
    PlayOk
  }

  @handshake_timeout_ms 15_000

  # -----------------------------------------------------------------------
  # ThousandIsland.Handler callbacks
  # -----------------------------------------------------------------------

  @impl ThousandIsland.Handler
  def handle_connection(socket, _server_info) do
    {private_key, scrambled_modulus} = RsaKey.generate()
    session_bf_key = :crypto.strong_rand_bytes(16)
    session_id = :rand.uniform(0x7FFFFFFF)
    bf_ctx = L2E.Commons.Blowfish.init_key(session_bf_key)

    state = %{
      rsa_private_key: private_key,
      session_bf_key: session_bf_key,
      bf_ctx: bf_ctx,
      session_id: session_id,
      auth_state: :wait_auth,
      username: nil,
      session_key: nil,
      login_ok_sent: false,
      buffer: <<>>,
      handshake_timer: nil
    }

    Logger.info("[LoginServer] New connection — sending Init (session_id=#{session_id})")

    case send_init(socket, session_id, scrambled_modulus, session_bf_key) do
      :ok -> Logger.info("[LoginServer] Init sent OK (#{170} bytes body, #{172} bytes total)")
      {:error, reason} -> Logger.warning("[LoginServer] Failed to send Init: #{inspect(reason)}")
    end

    timer = Process.send_after(self(), :handshake_timeout, @handshake_timeout_ms)
    {:continue, %{state | handshake_timer: timer}}
  end

  @impl ThousandIsland.Handler
  def handle_data(data, socket, state) do
    Logger.info("[LoginServer] Received #{byte_size(data)} bytes from client (state=#{state.auth_state}, buffer_was=#{byte_size(state.buffer)})")
    buffer = state.buffer <> data
    {packets, rest} = split_frames(buffer)

    state = %{state | buffer: rest}

    state =
      Enum.reduce_while(packets, state, fn pkt, acc ->
        case handle_packet(pkt, socket, acc) do
          {:continue, new_state} -> {:cont, new_state}
          {:stop, new_state} -> {:halt, new_state}
        end
      end)

    {:continue, state}
  end

  @impl GenServer
  def handle_info(:handshake_timeout, {socket, state}) do
    Logger.warning("[LoginServer] Handshake timeout — disconnecting #{inspect(socket)}")
    ThousandIsland.Socket.close(socket)
    {:stop, :normal, {socket, state}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -----------------------------------------------------------------------
  # Frame parser
  # -----------------------------------------------------------------------

  # Split a byte buffer into complete L2 frames, return {frames, remainder}
  defp split_frames(buffer), do: split_frames(buffer, [])

  defp split_frames(<<len::little-16, rest::binary>> = _buf, acc)
       when byte_size(rest) >= len - 2 do
    payload_len = len - 2
    <<payload::binary-size(payload_len), remaining::binary>> = rest
    split_frames(remaining, [payload | acc])
  end

  defp split_frames(buf, acc), do: {:lists.reverse(acc), buf}

  # -----------------------------------------------------------------------
  # Packet dispatch
  # -----------------------------------------------------------------------

  defp handle_packet(payload, socket, state) do
    Logger.info("[LoginServer] handle_packet: #{byte_size(payload)} bytes")

    case Crypto.decrypt(payload, state.bf_ctx) do
      {:ok, <<opcode::8, plain::binary>>} ->
        Logger.info("[LoginServer] Decrypted OK — opcode=0x#{Integer.to_string(opcode, 16)} plain_size=#{byte_size(plain)}")
        dispatch(opcode, plain, socket, state)

      {:ok, _} ->
        Logger.warning("[LoginServer] Decrypted but no opcode byte (empty payload)")
        {:continue, state}

      {:error, reason} ->
        Logger.warning("[LoginServer] Decrypt failed: #{reason} — payload_hex=#{Base.encode16(payload)}")
        {:continue, state}
    end
  end

  defp dispatch(opcode, body, socket, state) do
    case Decoder.decode(opcode, body) do
      {:ok, packet} ->
        handle_decoded(packet, socket, state)

      {:error, :unknown_opcode} ->
        Logger.debug("[LoginServer] Unknown opcode: 0x#{Integer.to_string(opcode, 16)}")
        {:continue, state}

      {:error, reason} ->
        Logger.warning(
          "[LoginServer] Malformed packet opcode 0x#{Integer.to_string(opcode, 16)}: #{reason}"
        )

        {:continue, state}
    end
  end

  # --- AuthGameGuard (state :wait_auth) ------------------------------------

  defp handle_decoded(%AuthGameGuard{session_id: sid}, socket, %{auth_state: :wait_auth} = state) do
    Logger.info("[LoginServer] Got AuthGameGuard (sid=#{sid}) — sending GGAuth")
    send_encrypted_static(socket, Encoder.encode(%GGAuth{session_id: sid}))
    {:continue, state}
  end

  # --- RequestAuthLogin (state :wait_auth) ---------------------------------

  defp handle_decoded(%RequestAuthLogin{} = pkt, socket, %{auth_state: :wait_auth} = state) do
    block = if pkt.new_method, do: binary_part(pkt.rsa_block, 0, 128), else: pkt.rsa_block

    case RsaKey.decrypt(state.rsa_private_key, block) do
      {:ok, plain} ->
        {username, password} = RequestAuthLogin.extract_credentials(plain)

        case AuthService.authenticate(username, password) do
          {:ok, _account} ->
            session_key = SessionKey.new()
            cancel_timer(state.handshake_timer)

            ok_packet = %LoginOk{
              login_ok1: session_key.login_ok1,
              login_ok2: session_key.login_ok2
            }

            send_encrypted_session(socket, Encoder.encode(ok_packet), state.bf_ctx)

            {:continue,
             %{
               state
               | username: username,
                 session_key: session_key,
                 login_ok_sent: true,
                 auth_state: :wait_server_select,
                 handshake_timer: nil
             }}

          {:error, reason} ->
            Logger.info("[LoginServer] Auth failed for #{username}: #{reason}")
            cancel_timer(state.handshake_timer)
            fail = %LoginFail{reason: LoginFail.reason_access_failed()}
            send_raw(socket, Encoder.encode(fail))
            {:stop, state}
        end

      {:error, reason} ->
        Logger.warning("[LoginServer] RSA decrypt failed for #{inspect(reason)}")
        fail = %LoginFail{reason: LoginFail.reason_access_failed()}
        send_raw(socket, Encoder.encode(fail))
        {:stop, state}
    end
  end

  # --- RequestServerList (state :wait_server_select) -----------------------

  defp handle_decoded(
         %RequestServerList{login_ok1: k1, login_ok2: k2},
         socket,
         %{auth_state: :wait_server_select} = state
       ) do
    if SessionKey.check_login_pair(state.session_key, k1, k2) do
      list = %ServerList{}
      send_encrypted_session(socket, Encoder.encode(list), state.bf_ctx)
      {:continue, state}
    else
      Logger.warning("[LoginServer] ServerList: invalid login pair from #{state.username}")
      {:stop, state}
    end
  end

  # --- RequestServerLogin (state :wait_server_select) ----------------------

  defp handle_decoded(
         %RequestServerLogin{login_ok1: k1, login_ok2: k2},
         socket,
         %{auth_state: :wait_server_select} = state
       ) do
    if SessionKey.check_login_pair(state.session_key, k1, k2) do
      AccountStore.put(state.username, state.session_key)
      ok = %PlayOk{play_ok1: state.session_key.play_ok1, play_ok2: state.session_key.play_ok2}
      send_encrypted_session(socket, Encoder.encode(ok), state.bf_ctx)
      ThousandIsland.Socket.close(socket)
      {:stop, state}
    else
      Logger.warning("[LoginServer] ServerLogin: invalid login pair from #{state.username}")
      {:stop, state}
    end
  end

  # Ignore packets in wrong state
  defp handle_decoded(pkt, _socket, state) do
    Logger.debug("[LoginServer] Unexpected packet in state #{state.auth_state}: #{inspect(pkt)}")
    {:continue, state}
  end

  # -----------------------------------------------------------------------
  # Send helpers
  # -----------------------------------------------------------------------

  # Init packet is NEVER encrypted; returns :ok | {:error, reason}
  defp send_init(socket, session_id, scrambled_modulus, bf_key) do
    payload =
      Encoder.encode(%Init{
        session_id: session_id,
        scrambled_modulus: scrambled_modulus,
        blowfish_key: bf_key
      })

    Logger.info("[LoginServer] send_init payload=#{byte_size(payload)} bytes (body), bf_key_hex=#{Base.encode16(bf_key)}")
    result = send_raw(socket, payload)
    result
  end

  # LoginOk uses STATIC Blowfish key + XOR-pass
  defp send_encrypted_static(socket, payload) do
    encrypted = Crypto.encrypt_static(payload)
    frame(socket, encrypted)
  end

  # Subsequent packets use SESSION Blowfish key
  defp send_encrypted_session(socket, payload, bf_ctx) do
    encrypted = Crypto.encrypt_session(payload, bf_ctx)
    frame(socket, encrypted)
  end

  defp send_raw(socket, payload), do: frame(socket, payload)

  defp frame(socket, payload) do
    total_len = byte_size(payload) + 2
    result = ThousandIsland.Socket.send(socket, <<total_len::little-16>> <> payload)
    if result != :ok, do: Logger.warning("[LoginServer] Socket.send failed: #{inspect(result)}")
    result
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)
end
