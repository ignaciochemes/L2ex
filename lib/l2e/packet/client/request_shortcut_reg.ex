defmodule L2E.Packet.Client.RequestShortcutReg do
  @moduledoc """
  Opcode 0x33 — client registers a shortcut on the action bar.

  Body (RequestShortcutReg.java):
    type    LE-32   (1=skill, 2=item, 3=action, 4=macro, 5=recipe, 6=bookmark)
    slot    LE-32   (page_slot = slot + page * 12; slot = page_slot % 12, page = page_slot / 12)
    id      LE-32   (skill_id / item_id / action_id)
    level   LE-32   (skill level; ignored for non-skill types)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:type, :slot, :page, :shortcut_id, :level]

  @type t :: %__MODULE__{
          type: non_neg_integer(),
          slot: non_neg_integer(),
          page: non_neg_integer(),
          shortcut_id: non_neg_integer(),
          level: non_neg_integer()
        }

  @impl L2E.Packet.Decodable
  def decode(<<type::little-32, page_slot::little-32, id::little-32, level::little-32,
               _::binary>>) do
    {:ok,
     %__MODULE__{
       type: type,
       slot: rem(page_slot, 12),
       page: div(page_slot, 12),
       shortcut_id: id,
       level: level
     }}
  end

  def decode(_), do: {:error, :malformed}
end
