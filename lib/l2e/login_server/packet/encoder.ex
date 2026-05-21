defmodule L2E.LoginServer.Packet.Encoder do
  @moduledoc "Dispatch encode/1 to the appropriate server-packet module."

  @spec encode(struct()) :: binary()
  def encode(%module{} = packet), do: module.encode(packet)
end
