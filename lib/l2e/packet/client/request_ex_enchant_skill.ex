defmodule L2E.Packet.Client.RequestExEnchantSkill do
  @moduledoc """
  0xD0/0x36 — Client requests to enchant a skill using a scroll.

  Binary layout (little-endian):
    skill_id(32)  skill_level(32)  enchant_scroll_object_id(32)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:skill_id, :skill_level, :enchant_scroll_object_id]

  @type t :: %__MODULE__{
          skill_id: integer(),
          skill_level: integer(),
          enchant_scroll_object_id: integer()
        }

  @impl L2E.Packet.Decodable
  def decode(
        <<skill_id::little-32, skill_level::little-32, scroll_obj_id::little-32, _rest::binary>>
      ) do
    {:ok,
     %__MODULE__{
       skill_id: skill_id,
       skill_level: skill_level,
       enchant_scroll_object_id: scroll_obj_id
     }}
  end

  def decode(_), do: {:error, :invalid_packet}
end
