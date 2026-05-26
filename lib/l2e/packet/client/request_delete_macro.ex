defmodule L2E.Packet.Client.RequestDeleteMacro do
  @moduledoc "Opcode 0xC2 — client deletes a macro by ID."
  defstruct [:macro_id]

  def decode(<<macro_id::little-32, _::binary>>) do
    {:ok, %__MODULE__{macro_id: macro_id}}
  end

  def decode(_), do: {:error, :invalid}
end
