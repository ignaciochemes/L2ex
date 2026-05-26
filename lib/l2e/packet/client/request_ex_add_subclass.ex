defmodule L2E.Packet.Client.RequestExAddSubclass do
  @moduledoc """
  0xD0/0x33 — client requests adding a new sub-class.

  Sent when the player selects a class to add as a sub-class from the Class
  Master NPC dialog.  In L2J Mobius CT0 Interlude this is done via
  `RequestBypassToServer` with `subclass_add&classId=XX`.  This module
  provides a dedicated extended-packet entry for the L2E Elixir server.

  Binary layout (little-endian):
    class_id  (int32) — ID of the class to add as a sub-class

  Note: sub-opcode 0x33 is the third free slot after REQUEST_DUEL_SURRENDER (0x30).
  """

  defstruct [:class_id]

  @spec decode(binary()) :: {:ok, %__MODULE__{}} | :error
  def decode(<<class_id::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{class_id: class_id}}
  end

  def decode(_), do: :error
end
