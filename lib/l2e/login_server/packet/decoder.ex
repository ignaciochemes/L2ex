defmodule L2E.LoginServer.Packet.Decoder do
  @moduledoc """
  Function-clause dispatcher for login-client packets.
  Strips the opcode byte then delegates to the matching decode/1 callback.
  """

  alias L2E.LoginServer.Packet.Client.{RequestAuthLogin, RequestServerList, RequestServerLogin}

  @spec decode(byte(), binary()) ::
          {:ok, struct()} | {:error, :unknown_opcode | :malformed}
  def decode(0x00, body), do: RequestAuthLogin.decode(body)
  def decode(0x05, body), do: RequestServerList.decode(body)
  def decode(0x02, body), do: RequestServerLogin.decode(body)
  def decode(_, _), do: {:error, :unknown_opcode}
end
