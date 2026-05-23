defmodule L2E.Packet.Client.RequestDismissAlly do
  @moduledoc "Opcode 0x86 — founder dismisses the alliance."
  defstruct []
  def decode(_), do: {:ok, %__MODULE__{}}
end
