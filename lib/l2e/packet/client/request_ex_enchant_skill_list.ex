defmodule L2E.Packet.Client.RequestExEnchantSkillList do
  @moduledoc """
  0xD0/0x34 — Client requests the full list of enchantable skills.
  No body — the server responds with all skills eligible for enchanting.
  """
  @behaviour L2E.Packet.Decodable

  defstruct []

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end
