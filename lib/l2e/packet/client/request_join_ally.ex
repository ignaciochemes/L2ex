defmodule L2E.Packet.Client.RequestJoinAlly do
  @moduledoc "Opcode 0x82 — request to form or join an alliance."
  defstruct [:target_obj_id]
  def decode(<<obj_id::little-32, _::binary>>), do: {:ok, %__MODULE__{target_obj_id: obj_id}}
  def decode(_), do: {:error, :invalid}
end
