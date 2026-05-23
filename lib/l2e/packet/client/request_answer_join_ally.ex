defmodule L2E.Packet.Client.RequestAnswerJoinAlly do
  @moduledoc "Opcode 0x83 — answer to an alliance join invitation."
  defstruct [:answer]
  def decode(<<answer::little-32, _::binary>>), do: {:ok, %__MODULE__{answer: answer}}
  def decode(_), do: {:error, :invalid}
end
