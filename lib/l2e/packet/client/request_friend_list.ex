defmodule L2E.Packet.Client.RequestFriendList do
  @moduledoc "Opcode 0x60 — request current friend list. No body. Reference: RequestFriendList.java"
  @behaviour L2E.Packet.Decodable

  defstruct []

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end
