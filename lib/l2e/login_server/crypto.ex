defmodule L2E.LoginServer.Crypto do
  @moduledoc """
  Blowfish-ECB cipher for the Login Server protocol.

  ## Two-phase encryption (LoginEncryption.java)

  ### Client → Server (decrypt)
  All client packets are encrypted with the **session Blowfish key** (the
  random 16 bytes sent in the `Init` packet). Decrypt then verify checksum.

  ### Server → Client (encrypt)
  - **First encrypted packet** (`LoginOk`): XOR-pass + Blowfish-ECB with the
    **static key** (hardcoded in both client and server).
  - **All subsequent packets** (`ServerList`, `PlayOk`): append checksum,
    pad to 8-byte boundary, Blowfish-ECB with the **session key**.

  ## Checksum (NewCrypt.java)
  XOR of all 4-byte little-endian blocks. Stored in the last 4 bytes of
  the padded buffer. `verifyChecksum/1` validates incoming packets.
  """

  import Bitwise

  alias L2E.Commons.Blowfish

  # Hardcoded in both client binary and LoginEncryption.java
  @static_bf_key <<0x6B, 0x60, 0xCB, 0x5B, 0x82, 0xCE, 0x90, 0xB1, 0xCC, 0x2B, 0x6C, 0x55, 0x6C,
                   0x6C, 0x6C, 0x6C>>

  # Precompute the static-key Blowfish context at module load time (avoid recomputing
  # per-connection). The session-key context is computed once per connection in the
  # connection handler and passed here.
  @static_bf_ctx Blowfish.init_key(@static_bf_key)

  @bf_block 8
  # Extra bytes for the static (XOR-pass) path (LoginEncryption.STATIC_HEADER_SIZE)
  @static_header 8
  # Extra bytes for the session path (LoginEncryption.DYNAMIC_HEADER_SIZE)
  @dynamic_header 4
  # Tail bytes reserved for checksum/key in both paths (LoginEncryption.CHECKSUM_SIZE)
  @checksum_tail 8

  # -------------------------------------------------------------------
  # Decrypt (client → server)
  # -------------------------------------------------------------------

  @doc """
  Decrypt an incoming login-client packet and verify its checksum.

  The client ALWAYS encrypts with the session key (received from Init).
  Returns `{:ok, plaintext}` or `{:error, reason}`.
  """
  @spec decrypt(binary(), bf_ctx :: {tuple(), tuple(), tuple(), tuple(), tuple()}) ::
          {:ok, binary()} | {:error, :bad_checksum | :size_error}
  def decrypt(data, bf_ctx) when rem(byte_size(data), @bf_block) == 0 do
    plain = Blowfish.decrypt_ecb(data, bf_ctx)

    if verify_checksum(plain) do
      {:ok, plain}
    else
      {:error, :bad_checksum}
    end
  end

  def decrypt(_data, _bf_ctx), do: {:error, :size_error}

  # -------------------------------------------------------------------
  # Encrypt (server → client)
  # -------------------------------------------------------------------

  @doc """
  Encrypt `LoginOk` — the first encrypted server packet.

  Uses XOR-pass (NewCrypt.encXORPass) then Blowfish-ECB with the STATIC key.
  After this call the connection must switch to `encrypt_session/2` for all
  subsequent packets.
  """
  @spec encrypt_static(binary()) :: binary()
  def encrypt_static(payload) do
    {buf, total} = pad_for_static(payload)
    xor_key = :rand.uniform(0x7FFFFFFF)
    buf = enc_xor_pass(buf, total, xor_key)
    Blowfish.encrypt_ecb(buf, @static_bf_ctx)
  end

  @doc """
  Encrypt any packet after `LoginOk` (`ServerList`, `PlayOk`, etc.).

  Appends a 4-byte checksum then Blowfish-ECB with the session key.
  """
  @spec encrypt_session(binary(), bf_ctx :: {tuple(), tuple(), tuple(), tuple(), tuple()}) ::
          binary()
  def encrypt_session(payload, bf_ctx) do
    {buf, _total} = pad_for_session(payload)
    buf = append_checksum(buf)
    Blowfish.encrypt_ecb(buf, bf_ctx)
  end

  # -------------------------------------------------------------------
  # Checksum
  # -------------------------------------------------------------------

  @doc "Verify that the last 4 bytes of `data` equal the XOR of all preceding 4-byte blocks."
  @spec verify_checksum(binary()) :: boolean()
  def verify_checksum(data) do
    size = byte_size(data)

    if rem(size, 4) != 0 or size <= 4 do
      false
    else
      data_len = size - 4
      <<prefix::binary-size(data_len), stored::little-32>> = data
      xor_blocks(prefix, 0) == stored
    end
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  # Padding for the static (first encrypted) packet
  # sizeWithHeader = dataSize + STATIC_HEADER (8), rounded up to BF block,
  # then add CHECKSUM_TAIL (8) for total.
  defp pad_for_static(payload) do
    data_size = byte_size(payload)
    padded = round_up_to_block(data_size + @static_header)
    total = padded + @checksum_tail
    zeros = total - 4 - data_size
    buf = <<0::32>> <> payload <> :binary.copy(<<0>>, zeros)
    {buf, total}
  end

  # Padding for session-key packets
  # sizeWithHeader = dataSize + DYNAMIC_HEADER (4), rounded up, then + 8.
  defp pad_for_session(payload) do
    data_size = byte_size(payload)
    padded = round_up_to_block(data_size + @dynamic_header)
    total = padded + @checksum_tail
    zeros = total - data_size
    buf = payload <> :binary.copy(<<0>>, zeros)
    {buf, total}
  end

  # Like Java: always adds at least 1 byte even when already aligned.
  defp round_up_to_block(n) do
    rem = rem(n, @bf_block)
    if rem == 0, do: n + @bf_block, else: n + (@bf_block - rem)
  end

  # Append 4-byte checksum at last 4 bytes of buf
  defp append_checksum(buf) do
    size = byte_size(buf)
    data_len = size - 4
    <<prefix::binary-size(data_len), _::binary-size(4)>> = buf
    checksum = xor_blocks(prefix, 0)
    prefix <> <<checksum::little-32>>
  end

  # NewCrypt.encXORPass — XOR pass for the static key path.
  # Processes bytes [4..end_pos-1] (4 skipped at front, 8 reserved at end).
  # Writes final key at [end_pos..end_pos+3]. Bytes [end_pos+4..total-1] = zeros.
  defp enc_xor_pass(buf, total, xor_key) do
    end_pos = total - @checksum_tail
    do_xor_pass(buf, 4, end_pos, xor_key)
  end

  defp do_xor_pass(buf, pos, end_pos, key) when pos >= end_pos do
    # Write the final accumulated key at end_pos
    <<before::binary-size(end_pos), _::binary-size(4), rest::binary>> = buf
    before <> <<key::little-32>> <> rest
  end

  defp do_xor_pass(buf, pos, end_pos, key) do
    <<before::binary-size(pos), block::little-32, rest::binary>> = buf
    new_key = key + block &&& 0xFFFFFFFF
    new_block = Bitwise.bxor(block, new_key)
    do_xor_pass(before <> <<new_block::little-32>> <> rest, pos + 4, end_pos, new_key)
  end

  defp xor_blocks(<<>>, acc), do: acc
  defp xor_blocks(<<b::little-32, rest::binary>>, acc), do: xor_blocks(rest, Bitwise.bxor(acc, b))
end
