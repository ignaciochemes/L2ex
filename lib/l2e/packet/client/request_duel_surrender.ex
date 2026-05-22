defmodule L2E.Packet.Client.RequestDuelSurrender do
  @moduledoc "Extended opcode 0xD0/0x30 — surrender an ongoing duel. No body. Reference: RequestDuelSurrender.java"
  @behaviour L2E.Packet.Decodable

  defstruct []

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end
