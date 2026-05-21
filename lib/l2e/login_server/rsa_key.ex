defmodule L2E.LoginServer.RsaKey do
  @moduledoc """
  RSA-1024 key generation and public modulus scrambling for the Login Server.

  The L2 Interlude client requires the server's RSA public modulus to be
  scrambled in a specific way before transmission. The client unscrambles
  it on receipt and uses it to encrypt the login credentials block with
  RSA/ECB/NoPadding.

  The scramble algorithm is from `ScrambledKeyPair.java`.

  ## Key usage
  1. `generate/0` — produce a key pair + scrambled modulus at startup.
  2. Send the scrambled modulus (128 bytes) in every `Init` packet.
  3. `decrypt/2` — RSA-decrypt the 128-byte credential block from the client.
  """

  @doc "Generate a 1024-bit RSA key pair and return {private_key, scrambled_modulus}."
  @spec generate() :: {private_key :: term(), scrambled_modulus :: binary()}
  def generate do
    private_key = :public_key.generate_key({:rsa, 1024, 65537})
    {:RSAPrivateKey, _, modulus, _, _, _, _, _, _, _, _} = private_key
    scrambled = modulus |> modulus_to_128_bytes() |> scramble_modulus()
    {private_key, scrambled}
  end

  @doc "RSA-decrypt a 128-byte block using the private key (no padding)."
  @spec decrypt(term(), binary()) :: {:ok, binary()} | {:error, term()}
  def decrypt(private_key, ciphertext) when byte_size(ciphertext) == 128 do
    try do
      plain = :public_key.decrypt_private(ciphertext, private_key, rsa_padding: :rsa_no_padding)
      {:ok, plain}
    rescue
      e -> {:error, e}
    end
  end

  def decrypt(_key, _data), do: {:error, :wrong_size}

  # ---- private --------------------------------------------------------

  defp modulus_to_128_bytes(modulus) do
    bytes = :binary.encode_unsigned(modulus, :big)
    len = byte_size(bytes)

    cond do
      len == 128 -> bytes
      len == 129 and binary_part(bytes, 0, 1) == <<0>> -> binary_part(bytes, 1, 128)
      len < 128 -> :binary.copy(<<0>>, 128 - len) <> bytes
    end
  end

  # ScrambledKeyPair.java — 4-step byte scramble
  defp scramble_modulus(mod) when byte_size(mod) == 128 do
    mod
    # Step 1: swap bytes[0x00..0x03] ↔ bytes[0x4D..0x50]
    |> swap4(0x00, 0x4D)
    # Step 2: XOR bytes[0x00..0x3F] with bytes[0x40..0x7F]
    |> xor_range(0x00, 0x40, 0x40)
    # Step 3: XOR bytes[0x0D..0x10] with bytes[0x34..0x38]
    |> xor_range(0x0D, 4, 0x34)
    # Step 4: XOR bytes[0x40..0x7F] with bytes[0x00..0x3F] (using new step-2 values)
    |> xor_range(0x40, 0x40, 0x00)
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
        List.replace_at(acc, dst_start + i, Bitwise.bxor(dst, src))
      end)

    :binary.list_to_bin(bytes)
  end
end
