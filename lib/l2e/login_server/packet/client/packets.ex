defmodule L2E.LoginServer.Packet.Client.RequestAuthLogin do
  @moduledoc """
  First packet sent by the client after receiving `Init`.
  Opcode 0x00 on the login server.

  Body: 128 bytes of RSA/ECB/NoPadding ciphertext (old auth method).

  After RSA-decryption with the server's private key, the 128-byte
  plaintext block contains:
  - username: bytes [0x5E..0x6B] (14 bytes, null-padded ASCII)
  - password: bytes [0x6C..0x7B] (16 bytes, null-padded ASCII)

  Reference: `RequestAuthLogin.java`
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:rsa_block, :new_method]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<block1::binary-size(128), block2::binary-size(128), _::binary>>) do
    {:ok, %__MODULE__{rsa_block: block1 <> block2, new_method: true}}
  end

  def decode(<<block1::binary-size(128), _::binary>>) do
    {:ok, %__MODULE__{rsa_block: block1, new_method: false}}
  end

  def decode(_), do: {:error, :malformed}

  @doc """
  Extract plaintext username and password from an RSA-decrypted 128-byte block.
  Old auth method only (single block). Trims null bytes.
  """
  @spec extract_credentials(binary()) :: {username :: String.t(), password :: String.t()}
  def extract_credentials(decrypted) when byte_size(decrypted) == 128 do
    username = decrypted |> binary_part(0x5E, 14) |> trim_null()
    password = decrypted |> binary_part(0x6C, 16) |> trim_null()
    {username, password}
  end

  defp trim_null(bin),
    do: bin |> :binary.bin_to_list() |> Enum.take_while(&(&1 != 0)) |> :binary.list_to_bin()
end

defmodule L2E.LoginServer.Packet.Client.RequestServerList do
  @moduledoc """
  Opcode 0x05 — sent after `LoginOk` to request the server list.
  Carries loginOk1 + loginOk2 for verification.
  Reference: `RequestServerList.java`
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:login_ok1, :login_ok2]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<login_ok1::little-32, login_ok2::little-32, _::binary>>) do
    {:ok, %__MODULE__{login_ok1: login_ok1, login_ok2: login_ok2}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.LoginServer.Packet.Client.RequestServerLogin do
  @moduledoc """
  Opcode 0x02 — client selects a game server to connect to.
  Carries loginOk1 + loginOk2 for verification + server ID.
  Reference: `RequestServerLogin.java`
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:login_ok1, :login_ok2, :server_id]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<login_ok1::little-32, login_ok2::little-32, server_id::8, _::binary>>) do
    {:ok, %__MODULE__{login_ok1: login_ok1, login_ok2: login_ok2, server_id: server_id}}
  end

  def decode(_), do: {:error, :malformed}
end
