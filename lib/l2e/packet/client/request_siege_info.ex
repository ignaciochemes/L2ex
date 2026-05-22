defmodule L2E.Packet.Client.RequestSiegeInfo do
  @moduledoc "Opcode 0x47 — request siege information. No body (empty readImpl). Reference: RequestSiegeInfo.java"
  @behaviour L2E.Packet.Decodable

  defstruct []

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end
