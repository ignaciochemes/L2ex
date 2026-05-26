defmodule L2E.Packet.Client.RequestSubclassChange do
  @moduledoc """
  0xD0/0x32 — client requests switching the active sub-class.

  Sent when the player selects a sub-class to switch to from the Class Master
  NPC dialog.  In L2J Mobius CT0 Interlude this is done via `RequestBypassToServer`
  with `subclass_change&index=N`.  This module provides a dedicated extended-packet
  entry for the L2E Elixir server.

  Binary layout (little-endian):
    class_index  (int32) — 0-based index of the target sub-class slot

  Note: sub-opcode 0x32 is the second free slot after REQUEST_DUEL_SURRENDER (0x30).
  """

  defstruct [:class_index]

  @spec decode(binary()) :: {:ok, %__MODULE__{}} | :error
  def decode(<<class_index::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{class_index: class_index}}
  end

  def decode(_), do: :error
end
