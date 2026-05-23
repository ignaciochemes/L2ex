defmodule L2E.Packet.Client.AllyLeave do
  @moduledoc "Opcode 0x84 — member clan leaves an alliance voluntarily."
  defstruct []
  def decode(_), do: {:ok, %__MODULE__{}}
end
