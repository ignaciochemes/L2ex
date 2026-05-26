defmodule L2E.Packet.Client.RequestSweep do
  @moduledoc """
  Opcode 0x42 — player sweeps a spoiled NPC corpse to collect items.

  Reference: L2J Interlude clientpackets/RequestSweep.java
  Layout: target_id(32LE)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:target_id]

  @impl true
  def decode(buf) do
    <<target_id::little-32, _rest::binary>> = buf
    {:ok, %__MODULE__{target_id: target_id}}
  end
end
