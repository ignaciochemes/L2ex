defmodule L2E.Packet.Client.RequestExEnchantSkillInfo do
  @moduledoc """
  0xD0/0x35 — Client requests enchant info (SP cost, required items) for a specific skill.

  Binary layout (little-endian):
    skill_id(32)  skill_level(32)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:skill_id, :skill_level]

  @type t :: %__MODULE__{skill_id: integer(), skill_level: integer()}

  @impl L2E.Packet.Decodable
  def decode(<<skill_id::little-32, skill_level::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{skill_id: skill_id, skill_level: skill_level}}
  end

  def decode(_), do: {:error, :invalid_packet}
end
