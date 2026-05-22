defmodule L2E.Packet.Client.RequestOlympiadMatchList do
  @moduledoc "Extended opcode 0xD0/0x13 — request current olympiad match list. No body. Reference: RequestOlympiadMatchList.java"
  @behaviour L2E.Packet.Decodable

  defstruct []

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end
