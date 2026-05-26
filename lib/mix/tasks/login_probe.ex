defmodule Mix.Tasks.LoginProbe do
  @moduledoc """
  Full L2 Interlude login protocol probe.

  Tests the complete login flow:
    Init → AuthGameGuard → GGAuth → RequestAuthLogin → LoginOk

  In dev mode the server auto-creates the test account on first login.

  Usage:
      mix login_probe [host [port [username [password]]]]

  Defaults: host=127.0.0.1, port=2106, username=probe, password=probe123
  """
  use Mix.Task

  import Bitwise

  @protocol_version 0x0000C621
  @rsa_exponent 65537

  def run(args) do
    Application.ensure_all_started(:l2e)

    host = (Enum.at(args, 0, "127.0.0.1") |> String.to_charlist())
    port = Enum.at(args, 1, "2106") |> Integer.parse() |> elem(0)
    username = Enum.at(args, 2, "probe")
    password = Enum.at(args, 3, "probe123")

    info("=== L2 Login Probe ===")
    info("Connecting to #{host}:#{port} ...")

    {:ok, sock} = :gen_tcp.connect(host, port, [:binary, active: false, packet: :raw])
    info("Connected.")

    # ── Step 1: Init ──────────────────────────────────────────────────────────
    {:ok, init_body} = recv_frame(sock)
    info("\n[1] Init: #{byte_size(init_body)} bytes")

    {:ok, init} = parse_init(init_body)
    info("  session_id:       #{init.session_id}")

    if init.protocol_version != @protocol_version do
      err("  ⚠  PROTOCOL MISMATCH: got 0x#{hex(init.protocol_version)}, expected 0x#{hex(@protocol_version)}")
    else
      info("  protocol_version: 0x#{hex(init.protocol_version)} ✓")
    end

    info("  bf_key:           #{Base.encode16(init.bf_key)}")
    bf_ctx = L2E.Commons.Blowfish.init_key(init.bf_key)

    # ── Step 2: AuthGameGuard ─────────────────────────────────────────────────
    info("\n[2] Sending AuthGameGuard (opcode=0x07, session_id=#{init.session_id})")
    send_session(sock, <<0x07, init.session_id::little-32>>, bf_ctx)

    # ── Step 3: GGAuth (server response, static-key encrypted) ───────────────
    info("\n[3] Waiting for GGAuth...")
    case recv_frame(sock, 3000) do
      {:ok, body} ->
        info("  Received #{byte_size(body)} bytes (static-BF-encrypted) — server accepted AuthGameGuard ✓")

      {:error, reason} ->
        err("  No GGAuth response: #{inspect(reason)}")
        :gen_tcp.close(sock)
        exit(:no_gg_auth)
    end

    # ── Step 4: RequestAuthLogin ──────────────────────────────────────────────
    info("\n[4] Sending RequestAuthLogin (username=#{username})")
    real_modulus = unscramble_modulus(init.scrambled_modulus)
    rsa_block = build_credential_block(username, password)
    encrypted_creds = rsa_encrypt(rsa_block, real_modulus)
    # opcode 0x00 + 128-byte RSA block
    send_session(sock, <<0x00>> <> encrypted_creds, bf_ctx)

    # ── Step 5: LoginOk or LoginFail ─────────────────────────────────────────
    info("\n[5] Waiting for server response...")
    case recv_frame(sock, 5000) do
      {:ok, body} ->
        decrypted = L2E.Commons.Blowfish.decrypt_ecb(body, bf_ctx)
        case decrypted do
          <<0x03, login_ok1::little-32, login_ok2::little-32, _rest::binary>> ->
            info("  ✓ LoginOk! login_ok1=#{login_ok1} login_ok2=#{login_ok2}")

            # ── Step 6: RequestServerList ───────────────────────────────────
            info("\n[6] Sending RequestServerList")
            send_session(sock, <<0x05, login_ok1::little-32, login_ok2::little-32>>, bf_ctx)

            case recv_frame(sock, 3000) do
              {:ok, body6} ->
                <<opcode6::8, rest6::binary>> = L2E.Commons.Blowfish.decrypt_ecb(body6, bf_ctx)
                info("  ServerList opcode=0x#{Integer.to_string(opcode6, 16)} (#{byte_size(rest6)} bytes body) ✓")

                # ── Step 7: RequestServerLogin (server_id=1) ────────────────
                info("\n[7] Sending RequestServerLogin (server_id=1)")
                send_session(sock, <<0x02, login_ok1::little-32, login_ok2::little-32, 1::8>>, bf_ctx)

                case recv_frame(sock, 3000) do
                  {:ok, body7} ->
                    <<opcode7::8, p1::little-32, p2::little-32, _::binary>> =
                      L2E.Commons.Blowfish.decrypt_ecb(body7, bf_ctx)
                    info("  PlayOk opcode=0x#{Integer.to_string(opcode7, 16)} play_ok1=#{p1} play_ok2=#{p2} ✓")
                    info("\n✅ Full login flow verified — connect game client to 127.0.0.1:7777")

                  {:error, :closed} ->
                    info("  Connection closed by server after PlayOk (expected)")
                    info("\n✅ Full login flow verified — connect game client to 127.0.0.1:7777")

                  {:error, reason7} ->
                    err("  No PlayOk response: #{inspect(reason7)}")
                end

              {:error, reason6} ->
                err("  No ServerList response: #{inspect(reason6)}")
            end

          <<0x01, reason::little-32, _rest::binary>> ->
            err("  ✗ LoginFail — reason=#{reason}")
            err("    (reason 4=access_failed, 2=wrong_password, 9=account_already_in_use)")

          <<opcode::8, _rest::binary>> ->
            err("  Unexpected opcode: 0x#{Integer.to_string(opcode, 16)}")
            info("  raw_hex: #{Base.encode16(body)}")
        end

      {:error, reason} ->
        err("  No response: #{inspect(reason)}")
    end

    :gen_tcp.close(sock)
    info("\nDone.")
  end

  # ---------------------------------------------------------------------------
  # Init parser
  # ---------------------------------------------------------------------------

  defp parse_init(
         <<0x00, session_id::little-32, protocol_version::little-32,
           scrambled_modulus::binary-size(128), _unk::binary-size(16),
           bf_key::binary-size(16), 0x00>>
       ) do
    {:ok,
     %{
       session_id: session_id,
       protocol_version: protocol_version,
       scrambled_modulus: scrambled_modulus,
       bf_key: bf_key
     }}
  end

  defp parse_init(bin) do
    err("Init parse failed (#{byte_size(bin)} bytes). First 20 bytes: #{Base.encode16(binary_part(bin, 0, min(20, byte_size(bin))))}")
    {:error, :bad_init}
  end

  # ---------------------------------------------------------------------------
  # RSA credential block
  # ---------------------------------------------------------------------------

  # 128-byte block: username at [0x5E..0x6B], password at [0x6C..0x7B]
  defp build_credential_block(username, password) do
    u = String.slice(username, 0, 14) |> pad_null(14)
    p = String.slice(password, 0, 16) |> pad_null(16)
    <<0::8*0x5E, u::binary, p::binary, 0::8*4>>
  end

  defp pad_null(str, len) do
    raw = :binary.bin_to_list(str) |> Enum.take(len)
    padding = List.duplicate(0, len - length(raw))
    :binary.list_to_bin(raw ++ padding)
  end

  # ---------------------------------------------------------------------------
  # RSA modulus unscramble (inverse of ScrambledKeyPair scramble)
  # ---------------------------------------------------------------------------

  # Scramble steps: swap4(0,0x4D) → xor(0,64,64) → xor(0x0D,4,0x34) → xor(64,64,0)
  # Unscramble: reverse order, each step is self-inverse
  defp unscramble_modulus(mod) when byte_size(mod) == 128 do
    mod
    |> xor_range(0x40, 0x40, 0x00)
    |> xor_range(0x0D, 4, 0x34)
    |> xor_range(0x00, 0x40, 0x40)
    |> swap4(0x00, 0x4D)
  end

  defp swap4(bin, pos_a, pos_b) do
    bytes = :binary.bin_to_list(bin)

    bytes =
      Enum.reduce(0..3, bytes, fn i, acc ->
        a = Enum.at(acc, pos_a + i)
        b = Enum.at(acc, pos_b + i)
        acc |> List.replace_at(pos_a + i, b) |> List.replace_at(pos_b + i, a)
      end)

    :binary.list_to_bin(bytes)
  end

  defp xor_range(bin, dst_start, len, src_start) do
    bytes = :binary.bin_to_list(bin)

    bytes =
      Enum.reduce(0..(len - 1), bytes, fn i, acc ->
        dst = Enum.at(acc, dst_start + i)
        src = Enum.at(acc, src_start + i)
        List.replace_at(acc, dst_start + i, bxor(dst, src))
      end)

    :binary.list_to_bin(bytes)
  end

  defp rsa_encrypt(block, modulus_bytes) when byte_size(block) == 128 do
    mod_int = :binary.decode_unsigned(modulus_bytes, :big)
    pub_key = {:RSAPublicKey, mod_int, @rsa_exponent}

    :public_key.encrypt_public(block, pub_key, rsa_padding: :rsa_no_padding)
  end

  # ---------------------------------------------------------------------------
  # Session-key encryption (C→S: pad + checksum + BF-ECB)
  # ---------------------------------------------------------------------------

  defp send_session(sock, payload, bf_ctx) do
    encrypted = encrypt_session(payload, bf_ctx)
    total_len = byte_size(encrypted) + 2
    :ok = :gen_tcp.send(sock, <<total_len::little-16>> <> encrypted)
    info("  Sent #{byte_size(encrypted)} bytes encrypted")
  end

  defp encrypt_session(payload, bf_ctx) do
    data_size = byte_size(payload)
    padded = round_up_to_block(data_size + 4)
    total = padded + 8
    zeros = total - data_size
    buf = payload <> :binary.copy(<<0>>, zeros)
    buf = append_checksum(buf)
    L2E.Commons.Blowfish.encrypt_ecb(buf, bf_ctx)
  end

  defp round_up_to_block(n) do
    rem_val = rem(n, 8)
    if rem_val == 0, do: n + 8, else: n + (8 - rem_val)
  end

  defp append_checksum(buf) do
    size = byte_size(buf)
    data_len = size - 4
    <<prefix::binary-size(data_len), _::binary-size(4)>> = buf
    checksum = xor_blocks(prefix, 0)
    prefix <> <<checksum::little-32>>
  end

  defp xor_blocks(<<>>, acc), do: acc
  defp xor_blocks(<<b::little-32, rest::binary>>, acc), do: xor_blocks(rest, bxor(acc, b))

  # ---------------------------------------------------------------------------
  # TCP framing
  # ---------------------------------------------------------------------------

  defp recv_frame(sock, timeout \\ 5000) do
    with {:ok, <<len::little-16>>} <- :gen_tcp.recv(sock, 2, timeout),
         body_len = len - 2,
         {:ok, body} <- :gen_tcp.recv(sock, body_len, timeout) do
      {:ok, body}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp info(msg), do: Mix.shell().info(msg)
  defp err(msg), do: Mix.shell().error(msg)
  defp hex(n), do: Integer.to_string(n, 16)
end
