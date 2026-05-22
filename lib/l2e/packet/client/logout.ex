defmodule L2E.Packet.Client.Logout do
  @moduledoc """
  Opcode 0x09 — sent by client to request logout.

  Body: empty (no fields).

  Reference: Logout.java — LOGOUT(0x09, ...)
  """
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end
