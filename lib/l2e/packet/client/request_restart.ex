defmodule L2E.Packet.Client.RequestRestart do
  @moduledoc """
  Opcode 0x46 — sent by client to request return to character select screen.

  Body: empty (no fields).

  Reference: RequestRestart.java — REQUEST_RESTART(0x46, ...)
  """
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end
