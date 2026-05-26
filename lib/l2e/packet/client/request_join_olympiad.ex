defmodule L2E.Packet.Client.RequestJoinOlympiad do
  @moduledoc "Extended opcode 0xD0/0x29 — register for Olympiad (RequestExEnterOlympiad). No body. Reference: RequestExEnterOlympiad.java"
  @behaviour L2E.Packet.Decodable

  defstruct []

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end
