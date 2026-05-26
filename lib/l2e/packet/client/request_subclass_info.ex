defmodule L2E.Packet.Client.RequestSubclassInfo do
  @moduledoc """
  0xD0/0x31 — client requests the list of available sub-classes and the
  character's current sub-class configuration.

  In L2J Mobius CT0 Interlude this flow is handled via `RequestBypassToServer`
  with bypass string `subclass_list` through the Class Master NPC.  This module
  provides a dedicated extended-packet entry for the L2E Elixir server so that
  future protocol revisions (Gracia+) can reuse the same handler path without
  touching `player_session.ex`.

  Binary layout: (no payload — client sends opcode only)

  Note: verified ExClientPackets.java — sub-opcode 0x31 is the first slot
  available after REQUEST_DUEL_SURRENDER (0x30).
  """

  defstruct []

  @spec decode(binary()) :: {:ok, %__MODULE__{}} | :error
  def decode(_body) do
    {:ok, %__MODULE__{}}
  end
end
