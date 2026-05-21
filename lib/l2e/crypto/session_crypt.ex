defmodule L2E.Crypto.SessionCrypt do
  @moduledoc """
  Process-local XOR cipher for a single game-server client connection.

  ## Protocol (from Encryption.java)

  The game server uses a 16-byte rolling XOR key:
  - Bytes [0..7]:  random key sent in KeyPacket (first 8 bytes)
  - Bytes [8..11]: rolling counter, starts at 0, incremented by packet size
  - Bytes [12..15]: zeros (constant)

  ### encrypt/2
  - First call: no-op, marks cipher as enabled. The first server→client
    packet (KeyPacket) is always sent unencrypted.
  - Subsequent calls:
      for each byte i: `out[i] = in[i] XOR key[i & 0xF] XOR prev`; `prev = out[i]`
      advance: key[8..11] += packet_size (LE uint32)

  ### decrypt/2
  - While not enabled: passthrough (ProtocolVersion from client is unencrypted).
  - Once enabled:
      for each byte i: `tmp = in[i]`; `out[i] = tmp XOR key[i & 0xF] XOR prev`; `prev = tmp`
      advance: key[8..11] += packet_size

  This struct is NEVER shared between connections.
  """

  import Bitwise

  defstruct key: <<0::128>>,
            enabled: false

  @type t :: %__MODULE__{
          key: <<_::128>>,
          enabled: boolean()
        }

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Create a cipher seeded with 8 random bytes (as sent in KeyPacket)."
  @spec new(binary()) :: t()
  def new(random_8) when byte_size(random_8) == 8 do
    # bytes [8..15] start as zeros; [8..11] is the rolling counter
    %__MODULE__{key: random_8 <> <<0::64>>}
  end

  @doc "Generate the 8-byte random portion to send in KeyPacket."
  @spec random_key_bytes() :: binary()
  def random_key_bytes, do: :crypto.strong_rand_bytes(8)

  # -----------------------------------------------------------------------
  # encrypt/2
  # -----------------------------------------------------------------------

  @doc "Encrypt an outbound payload. First call is a no-op that enables the cipher."
  @spec encrypt(binary(), t()) :: {binary(), t()}
  def encrypt(data, %__MODULE__{enabled: false} = crypt) do
    # First call: enable cipher, return data unchanged (KeyPacket goes raw)
    {data, %{crypt | enabled: true}}
  end

  def encrypt(data, %__MODULE__{key: key} = crypt) do
    encrypted = do_encrypt(data, key, 0, 0, [])
    new_key = advance_key(key, byte_size(data))
    {encrypted, %{crypt | key: new_key}}
  end

  # -----------------------------------------------------------------------
  # decrypt/2
  # -----------------------------------------------------------------------

  @doc "Decrypt an inbound payload. Passthrough until cipher is enabled."
  @spec decrypt(binary(), t()) :: {binary(), t()}
  def decrypt(data, %__MODULE__{enabled: false} = crypt), do: {data, crypt}

  def decrypt(data, %__MODULE__{key: key} = crypt) do
    decrypted = do_decrypt(data, key, 0, 0, [])
    new_key = advance_key(key, byte_size(data))
    {decrypted, %{crypt | key: new_key}}
  end

  # -----------------------------------------------------------------------
  # Private: XOR loops
  # -----------------------------------------------------------------------

  defp do_encrypt(<<>>, _key, _i, _prev, acc),
    do: acc |> :lists.reverse() |> :binary.list_to_bin()

  defp do_encrypt(<<byte, rest::binary>>, key, i, prev, acc) do
    k = :binary.at(key, band(i, 15))
    out = Bitwise.bxor(Bitwise.bxor(byte, k), prev)
    do_encrypt(rest, key, i + 1, out, [out | acc])
  end

  defp do_decrypt(<<>>, _key, _i, _prev, acc),
    do: acc |> :lists.reverse() |> :binary.list_to_bin()

  defp do_decrypt(<<byte, rest::binary>>, key, i, prev, acc) do
    k = :binary.at(key, band(i, 15))
    out = Bitwise.bxor(Bitwise.bxor(byte, k), prev)
    do_decrypt(rest, key, i + 1, byte, [out | acc])
  end

  # Advance rolling counter at key[8..11] by adding packet size (LE uint32)
  defp advance_key(<<head::binary-size(8), counter::little-32, tail::binary-size(4)>>, size) do
    new_counter = counter + size &&& 0xFFFFFFFF
    <<head::binary, new_counter::little-32, tail::binary>>
  end
end
