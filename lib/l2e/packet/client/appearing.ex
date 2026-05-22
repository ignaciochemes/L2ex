defmodule L2E.Packet.Client.Appearing do
  @moduledoc """
  Opcode 0x30 — sent by client when it has finished entering the world and
  the character is visible on screen.

  Body: empty (no fields).

  Reference: Appearing.java — APPEARING(0x30, ...)
  """
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end
