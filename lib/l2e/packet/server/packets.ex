defmodule L2E.Packet.Server.KeyPacket do
  @moduledoc """
  Opcode 0x00 — first packet sent by the game server, UNENCRYPTED.

  Contains the 8-byte XOR key the client will use for all subsequent
  packets (plus 8 zero bytes for the rolling-counter extension).

  Reference: `KeyPacket.java`
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:key]
  @type t :: %__MODULE__{key: <<_::64>>}

  @server_id Application.compile_env(:l2e, :server_id, 1)
  @packet_encryption 1

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{key: key}) when byte_size(key) == 8 do
    <<0x00, 0x01, key::binary-size(8), @packet_encryption::little-32, @server_id::little-32, 0x01,
      0::little-32>>
  end
end

defmodule L2E.Packet.Server.UserInfo do
  @moduledoc "Sent to a player after entering the world. Contains their own character data."
  @behaviour L2E.Packet.Encodable

  # TODO: expand fields as character model grows
  defstruct [:char_id, :char_name, :x, :y, :z, :heading, :hp, :max_hp]
  @type t :: %__MODULE__{}

  @opcode 0x04

  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = p) do
    name = encode_utf16(p.char_name)

    <<@opcode::8, p.x::little-32-signed, p.y::little-32-signed, p.z::little-32-signed,
      p.heading::little-32, p.char_id::little-32, name::binary, p.hp::little-32,
      p.max_hp::little-32>>
  end

  defp encode_utf16(nil), do: <<0::16>>

  defp encode_utf16(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.CharInfo do
  @moduledoc "Sent to a player when another character enters their AOI."
  @behaviour L2E.Packet.Encodable

  defstruct [:char_id, :char_name, :x, :y, :z, :heading]
  @type t :: %__MODULE__{}

  @opcode 0x03

  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = p) do
    name = encode_utf16(p.char_name)

    <<@opcode::8, p.x::little-32-signed, p.y::little-32-signed, p.z::little-32-signed,
      p.char_id::little-32, name::binary, p.heading::little-32>>
  end

  defp encode_utf16(nil), do: <<0::16>>

  defp encode_utf16(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.CharMoveToLocation do
  @moduledoc "Broadcast to nearby players when a character moves."
  @behaviour L2E.Packet.Encodable

  defstruct [:char_id, :x, :y, :z, :origin_x, :origin_y, :origin_z]
  @type t :: %__MODULE__{}

  @opcode 0x01

  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = p) do
    <<@opcode::8, p.char_id::little-32, p.x::little-32-signed, p.y::little-32-signed,
      p.z::little-32-signed, p.origin_x::little-32-signed, p.origin_y::little-32-signed,
      p.origin_z::little-32-signed>>
  end
end

defmodule L2E.Packet.Server.CharSelectInfo do
  @moduledoc """
  Opcode 0x13 — character selection list sent after `AuthLogin` succeeds.

  For Milestone 2 this always sends a single hardcoded test character so
  the client can proceed to the character screen.

  Binary layout follows CharSelectionInfo.java exactly.
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:login_name, :session_id, characters: []]

  @type character :: %{
          name: String.t(),
          object_id: non_neg_integer(),
          class_id: non_neg_integer(),
          race: non_neg_integer(),
          sex: non_neg_integer(),
          level: non_neg_integer(),
          exp: non_neg_integer(),
          sp: non_neg_integer(),
          hp: float(),
          max_hp: float(),
          mp: float(),
          max_mp: float(),
          x: integer(),
          y: integer(),
          z: integer(),
          karma: non_neg_integer(),
          hair_style: non_neg_integer(),
          hair_color: non_neg_integer(),
          face: non_neg_integer(),
          is_active: boolean()
        }

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{login_name: login_name, session_id: session_id, characters: chars}) do
    count = length(chars)
    active_id = active_id(chars)

    chars_bin =
      chars
      |> Enum.with_index()
      |> Enum.map_join(&encode_char(&1, login_name, session_id, active_id))

    <<0x13, count::little-32>> <> chars_bin
  end

  defp active_id([]), do: -1

  defp active_id(chars) do
    # Return the index of the last-accessed char (simplified: always slot 0)
    if Enum.any?(chars), do: 0, else: -1
  end

  defp encode_char({char, idx}, login_name, session_id, active_id) do
    name_bin = utf16le_string(char.name)
    login_bin = utf16le_string(login_name)
    title_bin = utf16le_string("")
    # 17 paperdoll objectId slots, all 0
    paperdoll_obj = :binary.copy(<<0::32>>, 17)
    # 17 paperdoll itemId slots, all 0
    paperdoll_item = :binary.copy(<<0::32>>, 17)
    is_active = if idx == active_id, do: 1, else: 0
    # not used in CharSelectionInfo (uses loginName not title)
    _ = title_bin

    <<>> <>
      name_bin <>
      <<char.object_id::little-32>> <>
      login_bin <>
      <<
        session_id::little-32,
        # clan_id
        0::little-32,
        # builder level
        0::little-32,
        char.sex::little-32,
        char.race::little-32,
        char.class_id::little-32,
        # GameServerName placeholder
        1::little-32,
        0::little-32,
        0::little-32,
        0::little-32,
        char.hp::little-float-64,
        char.mp::little-float-64,
        char.sp::little-32,
        char.exp::little-64,
        char.level::little-32,
        char.karma::little-32,
        # pvpKills
        0::little-32,
        # pkKills
        0::little-32,
        0::little-32,
        0::little-32,
        0::little-32,
        0::little-32,
        0::little-32,
        0::little-32,
        0::little-32
      >> <>
      paperdoll_obj <>
      paperdoll_item <>
      <<
        char.hair_style::little-32,
        char.hair_color::little-32,
        char.face::little-32,
        char.max_hp::little-float-64,
        char.max_mp::little-float-64,
        # delete_timer (0 = not deleted)
        0::little-32,
        char.class_id::little-32,
        is_active::little-32,
        # enchant_effect
        0::8,
        # augmentation_id
        0::little-32
      >>
  end

  defp utf16le_string(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.CharSelected do
  @moduledoc """
  Opcode 0x15 — confirms character selection and transitions client to world loading.

  Reference: CharSelected.java
  """
  @behaviour L2E.Packet.Encodable

  defstruct [
    :name,
    :object_id,
    :session_id,
    :clan_id,
    :sex,
    :race,
    :class_id,
    :x,
    :y,
    :z,
    :hp,
    :max_hp,
    :mp,
    :max_mp,
    :sp,
    :exp,
    :level,
    :karma
  ]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    name_bin = utf16le_string(p.name)
    title_bin = utf16le_string("")

    <<0x15>> <>
      name_bin <>
      <<p.object_id::little-32>> <>
      title_bin <>
      <<p.session_id::little-32, p.clan_id::little-32, 0::little-32, p.sex::little-32,
        p.race::little-32, p.class_id::little-32, 1::little-32, p.x::little-32-signed,
        p.y::little-32-signed, p.z::little-32-signed, p.hp::little-float-64,
        p.mp::little-float-64, p.sp::little-32, p.exp::little-64>>
  end

  defp utf16le_string(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.NewCharacterSuccess do
  @moduledoc """
  Opcode 0x17 (CHAR_TEMPLATES) — sent in response to NewCharacter (0x0E).

  Contains one entry per playable initial class showing base stats used by the
  client to render the stat bars on the character-creation screen.

  Layout per entry: race(int) class_id(int) then for each of 6 stats
  (STR DEX CON INT WIT MEN): 0x46(int) value(int) 0x0A(int)
  """
  @behaviour L2E.Packet.Encodable

  defstruct []
  @type t :: %__MODULE__{}

  # {race, class_id, str, dex, con, int, wit, men}
  @templates [
    # Human Fighter
    {0, 0, 40, 30, 43, 21, 11, 25},
    # Human Mystic
    {0, 11, 22, 23, 20, 40, 33, 32},
    # Elven Fighter
    {1, 18, 36, 37, 36, 26, 15, 30},
    # Elven Mystic
    {1, 25, 21, 28, 20, 41, 33, 34},
    # Dark Elven Fighter
    {2, 31, 41, 37, 34, 26, 12, 25},
    # Dark Elven Mystic
    {2, 38, 25, 28, 23, 41, 33, 27},
    # Orc Fighter
    {3, 44, 40, 23, 43, 20, 11, 23},
    # Orc Shaman
    {3, 49, 36, 23, 30, 21, 20, 34},
    # Dwarven Fighter
    {4, 53, 42, 23, 46, 20, 11, 28}
  ]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{}) do
    count = length(@templates)
    body = Enum.map_join(@templates, &encode_template/1)
    <<0x17, count::little-32>> <> body
  end

  defp encode_template({race, class_id, str, dex, con, int_, wit, men}) do
    <<
      race::little-32,
      class_id::little-32,
      0x46::little-32,
      str::little-32,
      0x0A::little-32,
      0x46::little-32,
      dex::little-32,
      0x0A::little-32,
      0x46::little-32,
      con::little-32,
      0x0A::little-32,
      0x46::little-32,
      int_::little-32,
      0x0A::little-32,
      0x46::little-32,
      wit::little-32,
      0x0A::little-32,
      0x46::little-32,
      men::little-32,
      0x0A::little-32
    >>
  end
end

defmodule L2E.Packet.Server.CharCreateOk do
  @moduledoc "Opcode 0x19 — confirms that a character was successfully created."
  @behaviour L2E.Packet.Encodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{}) do
    <<0x19, 1::little-32>>
  end
end

defmodule L2E.Packet.Server.CharCreateFail do
  @moduledoc """
  Opcode 0x1A — character creation failed.

  Reason codes (CharCreateFail.java):
    0 = generic failure
    1 = name too long (> 16 eng chars)
    2 = characters per server limit
    3 = no more chars on account
    4 = name already exists
    5 = invalid name (bad chars)
    6 = choose another server
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:reason]
  @type t :: %__MODULE__{reason: non_neg_integer()}

  @reason_invalid_name 0
  @reason_name_exists 4

  def reason_invalid_name, do: @reason_invalid_name
  def reason_name_exists, do: @reason_name_exists

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{reason: reason}) do
    <<0x1A, reason::little-32>>
  end
end

defmodule L2E.Packet.Server.CharDeleteOk do
  @moduledoc "Opcode 0x23 — confirms that a character was successfully deleted."
  @behaviour L2E.Packet.Encodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{}) do
    <<0x23>>
  end
end

defmodule L2E.Packet.Server.CharDeleteFail do
  @moduledoc "Opcode 0x24 — character deletion failed."
  @behaviour L2E.Packet.Encodable

  defstruct [:reason]
  @type t :: %__MODULE__{reason: non_neg_integer()}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{reason: reason}) do
    <<0x24, reason::little-32>>
  end
end

defmodule L2E.Packet.Server.StatusUpdate do
  @moduledoc """
  Opcode 0x0E — sends one or more stat values for an object to the client.

  Used for HP/MP/CP bars, P.Atk, P.Def, etc. The client updates the
  relevant UI elements for any attr_id it recognises.

  Reference: StatusUpdate.java
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:object_id, :attributes]

  @type attribute :: {non_neg_integer(), integer()}
  @type t :: %__MODULE__{object_id: pos_integer(), attributes: [attribute()]}

  # Well-known attribute IDs used by the client
  @level 0x01
  @exp 0x02
  @str 0x03
  @dex 0x04
  @con 0x05
  @int 0x06
  @wit 0x07
  @men 0x08
  @cur_hp 0x09
  @max_hp 0x0A
  @cur_mp 0x0B
  @max_mp 0x0C
  @sp 0x0D
  @p_atk 0x11
  @atk_spd 0x12
  @p_def 0x13
  @evasion 0x14
  @accuracy 0x15
  @critical 0x16
  @m_atk 0x17
  @cast_spd 0x18
  @m_def 0x19
  @cur_cp 0x21
  @max_cp 0x22

  def attr_level, do: @level
  def attr_exp, do: @exp
  def attr_str, do: @str
  def attr_dex, do: @dex
  def attr_con, do: @con
  def attr_int, do: @int
  def attr_wit, do: @wit
  def attr_men, do: @men
  def attr_cur_hp, do: @cur_hp
  def attr_max_hp, do: @max_hp
  def attr_cur_mp, do: @cur_mp
  def attr_max_mp, do: @max_mp
  def attr_sp, do: @sp
  def attr_p_atk, do: @p_atk
  def attr_atk_spd, do: @atk_spd
  def attr_p_def, do: @p_def
  def attr_evasion, do: @evasion
  def attr_accuracy, do: @accuracy
  def attr_critical, do: @critical
  def attr_m_atk, do: @m_atk
  def attr_cast_spd, do: @cast_spd
  def attr_m_def, do: @m_def
  def attr_cur_cp, do: @cur_cp
  def attr_max_cp, do: @max_cp

  @doc "Build a StatusUpdate containing all full-character stats."
  @spec from_char_stats(pos_integer(), map(), float(), float()) :: t()
  def from_char_stats(object_id, stats, cur_hp, cur_mp) do
    %__MODULE__{
      object_id: object_id,
      attributes: [
        {@level, stats.level},
        {@str, stats.str},
        {@dex, stats.dex},
        {@con, stats.con},
        {@int, stats.int},
        {@wit, stats.wit},
        {@men, stats.men},
        {@cur_hp, round(cur_hp)},
        {@max_hp, stats.max_hp},
        {@cur_mp, round(cur_mp)},
        {@max_mp, stats.max_mp},
        {@p_atk, stats.p_atk},
        {@atk_spd, stats.atk_speed},
        {@p_def, stats.p_def},
        {@evasion, stats.evasion},
        {@accuracy, stats.accuracy},
        {@critical, stats.crit_rate},
        {@m_atk, stats.m_atk},
        {@cast_spd, stats.cast_speed},
        {@m_def, stats.m_def},
        {@max_cp, stats.max_cp}
      ]
    }
  end

  @doc "Build a StatusUpdate containing only current HP and MP (e.g. after taking damage)."
  @spec hp_mp(pos_integer(), number(), number()) :: t()
  def hp_mp(object_id, cur_hp, cur_mp) do
    %__MODULE__{
      object_id: object_id,
      attributes: [
        {@cur_hp, round(cur_hp)},
        {@cur_mp, round(cur_mp)}
      ]
    }
  end

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{object_id: obj_id, attributes: attrs}) do
    count = length(attrs)
    body = Enum.map_join(attrs, fn {id, val} -> <<id::little-32, val::little-32>> end)
    <<0x0E, obj_id::little-32, count::little-32>> <> body
  end
end

defmodule L2E.Packet.Server.NpcInfo do
  @moduledoc """
  Opcode 0x16 — describes an NPC to the client when it enters the player's AOI.

  Reference: AbstractNpcInfo.java / NpcInfo.java
  """
  @behaviour L2E.Packet.Encodable

  defstruct [
    :object_id,
    :npc_type_id,
    :name,
    :title,
    :x,
    :y,
    :z,
    :heading,
    :max_hp,
    :cur_hp,
    :max_mp,
    :cur_mp,
    :run_speed,
    :walk_speed,
    :p_atk,
    :p_def,
    :m_atk,
    :m_def,
    :atk_speed,
    :cast_speed,
    :level,
    :is_attackable
  ]

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    name = utf16le_null(p.name || "")
    title = utf16le_null(p.title || "")
    display_id = (p.npc_type_id || 0) + 1_000_000
    attackable = if p.is_attackable, do: 1, else: 0

    <<0x16, p.object_id::little-32, display_id::little-32, attackable::little-32,
      p.x::little-32-signed, p.y::little-32-signed, p.z::little-32-signed, p.heading::little-32,
      0::little-32, p.atk_speed::little-32, p.atk_speed::little-32, p.run_speed::little-32,
      p.walk_speed::little-32, p.run_speed::little-32, p.walk_speed::little-32,
      p.run_speed::little-32, p.walk_speed::little-32, p.run_speed::little-32,
      p.walk_speed::little-32, 1.0::little-float-64, 1.0::little-float-64, 10.0::little-float-64,
      25.0::little-float-64, 0::little-32, 0::little-32, 0::little-32, 1::8, 1::8, 0::8, 0::8,
      0::8>> <>
      name <>
      title <>
      <<0::little-32, 0::little-32, 0::little-32, 0::little-32, 0::little-32, 0::little-32,
        0::little-32, 0::little-32, 0::8, 0::8, 10.0::little-float-64, 25.0::little-float-64,
        0::little-32, 0::little-32>>
  end

  defp utf16le_null(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.DeleteObject do
  @moduledoc """
  Opcode 0x12 — removes an object (NPC, player, item) from the client's world view.

  Sent when an entity dies or leaves the player's AOI.
  Reference: DeleteObject.java
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:object_id]
  @type t :: %__MODULE__{object_id: pos_integer()}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{object_id: obj_id}) do
    <<0x12, obj_id::little-32>>
  end
end

defmodule L2E.Packet.Server.TargetSelected do
  @moduledoc """
  Opcode 0x29 — confirms that the player has selected a target.

  color field: 0 = same level, >0 = higher level (danger indicator).
  Reference: TargetSelected.java
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:object_id, :target_id, :color]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{object_id: obj_id, target_id: target_id, color: color}) do
    <<0x29, obj_id::little-32, target_id::little-32, color || 0::little-16>>
  end
end

defmodule L2E.Packet.Server.MyTargetSelected do
  @moduledoc """
  Opcode 0xA6 — sent to the attacker to show the target selection indicator with HP.

  color: level difference indicator (0 = same, positive = stronger, negative = weaker).
  Reference: MyTargetSelected.java
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:target_id, :color]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{target_id: target_id, color: color}) do
    <<0xA6, target_id::little-32, color || 0::little-16>>
  end
end

defmodule L2E.Packet.Server.Attack do
  @moduledoc """
  Opcode 0x05 — broadcasts a physical attack to nearby players.

  Encodes the attacker, the primary target, and whether it was a hit, miss, or crit.
  Reference: Attack.java
  """
  @behaviour L2E.Packet.Encodable

  defstruct [
    :attacker_id,
    :attacker_x,
    :attacker_y,
    :attacker_z,
    :target_id,
    :damage,
    :miss,
    :crit,
    :target_x,
    :target_y,
    :target_z
  ]

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    miss_flag = if p.miss, do: 1, else: 0
    crit_flag = if p.crit, do: 0x10, else: 0
    damage = max(0, p.damage || 0)

    <<0x05, p.attacker_id::little-32, 0::little-32, p.attacker_x::little-32-signed,
      p.attacker_y::little-32-signed, p.attacker_z::little-32-signed, 1::little-16,
      p.target_id::little-32, damage::little-32, miss_flag::8, crit_flag::little-32,
      p.target_x::little-32-signed, p.target_y::little-32-signed, p.target_z::little-32-signed>>
  end
end

defmodule L2E.Packet.Server.Die do
  @moduledoc """
  Opcode 0x06 — notifies the client that an object has died.

  can_sweep is set to 1 for monsters that can be swept (after skill use).
  Reference: Die.java
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:object_id, can_sweep: false]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{object_id: obj_id, can_sweep: sweep}) do
    sweep_flag = if sweep, do: 1, else: 0

    <<0x06, obj_id::little-32, 1::little-32, sweep_flag::little-32, 0::little-32, 0::little-32,
      0::little-32>>
  end
end

defmodule L2E.Packet.Server.Revive do
  @moduledoc """
  Opcode 0x07 — notifies the client that an object has been revived.

  Reference: Revive.java
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:object_id]
  @type t :: %__MODULE__{object_id: pos_integer()}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{object_id: obj_id}) do
    <<0x07, obj_id::little-32>>
  end
end

defmodule L2E.Packet.Server.SocialAction do
  @moduledoc """
  Opcode 0xC3 — plays a social/emote animation on a creature.

  action_id 2316 = level-up animation.

  Reference: SocialAction.java
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:object_id, :action_id]
  @type t :: %__MODULE__{object_id: pos_integer(), action_id: non_neg_integer()}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{object_id: obj_id, action_id: action}) do
    <<0xC3, obj_id::little-32, action::little-32>>
  end
end

defmodule L2E.Packet.Server.ItemList do
  @moduledoc """
  Opcode 0x1B — sends the full inventory list to the client on enter-world.

  Each item entry follows the AbstractItemPacket.writeItem() format used by
  L2J Mobius Interlude:
    type1(16) obj_id(32) item_id(32) count(32) type2(16)
    custom1(16) equipped(16) bodypart(32) enchant(16)
    custom2(16) aug_id(32) element(32)

  Reference: ItemList.java, AbstractItemPacket.java
  """
  @behaviour L2E.Packet.Encodable

  # items: [{Instance.t(), Template.t()}]
  defstruct items: []

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{items: items}) do
    count = length(items)
    body = Enum.map_join(items, &encode_item/1)
    # show_window=0 (don't force-open inventory UI on login)
    <<0x1B, 0::8, count::little-16>> <> body
  end

  defp encode_item({instance, template}) do
    equipped = if instance.is_equipped, do: 1, else: 0

    <<
      template.type1 || 0::little-16,
      instance.id::little-32,
      template.item_id::little-32,
      instance.count || 1::little-32,
      template.type2 || 0::little-16,
      0::little-16,
      equipped::little-16,
      template.bodypart || 0::little-32,
      instance.enchant_level || 0::little-16,
      0::little-16,
      0::little-32,
      0::little-32
    >>
  end
end

defmodule L2E.Packet.Server.InventoryUpdate do
  @moduledoc """
  Opcode 0x27 — differential inventory update sent after any inventory change.

  change_type: 1 = item added, 2 = item modified, 3 = item removed.

  Reference: InventoryUpdate.java, AbstractItemPacket.java
  """
  @behaviour L2E.Packet.Encodable

  # changes: [{change_type_integer, Instance.t(), Template.t()}]
  defstruct changes: []

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{changes: changes}) do
    count = length(changes)
    body = Enum.map_join(changes, &encode_change/1)
    <<0x27, count::little-16>> <> body
  end

  defp encode_change({change_type, instance, template}) do
    <<change_type::8>> <> encode_item(instance, template)
  end

  defp encode_item(instance, template) do
    equipped = if instance.is_equipped, do: 1, else: 0

    <<
      template.type1 || 0::little-16,
      instance.id::little-32,
      template.item_id::little-32,
      instance.count || 1::little-32,
      template.type2 || 0::little-16,
      0::little-16,
      equipped::little-16,
      template.bodypart || 0::little-32,
      instance.enchant_level || 0::little-16,
      0::little-16,
      0::little-32,
      0::little-32
    >>
  end
end

defmodule L2E.Packet.Server.SkillList do
  @moduledoc """
  Opcode 0x58 — sends the player's full skill list to populate the skill window.

  `skills` is a list of maps: %{skill_id, level, passive, disabled}.

  Binary layout (SkillList.java):
    count(32) + per skill: passive(32) level(32) id(32) disabled(8)

  Reference: ServerPackets.SKILL_LIST(0x58)
  """
  @behaviour L2E.Packet.Encodable

  defstruct skills: []

  @type t :: %__MODULE__{
          skills: [
            %{skill_id: integer(), level: integer(), passive: boolean(), disabled: boolean()}
          ]
        }

  @opcode 0x58

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{skills: skills}) do
    count = length(skills)

    skills_bin =
      Enum.map_join(skills, fn s ->
        passive = if Map.get(s, :passive, false), do: 1, else: 0
        disabled = if Map.get(s, :disabled, false), do: 1, else: 0
        <<passive::little-32, s.level::little-32, s.skill_id::little-32, disabled::8>>
      end)

    <<@opcode::8, count::little-32>> <> skills_bin
  end
end

defmodule L2E.Packet.Server.MagicSkillUse do
  @moduledoc """
  Opcode 0x48 — tells nearby clients that a creature started casting a skill.
  Triggers the cast animation and the cast-bar on the client.

  Binary layout (MagicSkillUse.java):
    caster_id(32) target_id(32) skill_id(32) skill_level(32)
    hit_time(32) reuse_delay(32) x(32) y(32) z(32)

  Reference: ServerPackets.MAGIC_SKILL_USE(0x48)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [
    :caster_id,
    :target_id,
    :skill_id,
    :skill_level,
    :hit_time,
    :reuse_delay,
    :x,
    :y,
    :z
  ]

  @type t :: %__MODULE__{}
  @opcode 0x48

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    <<
      @opcode::8,
      p.caster_id::little-32,
      p.target_id::little-32,
      p.skill_id::little-32,
      p.skill_level::little-32,
      p.hit_time::little-32,
      p.reuse_delay::little-32,
      p.x::little-32-signed,
      p.y::little-32-signed,
      p.z::little-32-signed
    >>
  end
end

defmodule L2E.Packet.Server.MagicSkillLaunched do
  @moduledoc """
  Opcode 0x76 — sent after cast completes; tells clients the effect has landed.

  Binary layout (MagicSkillLaunched.java):
    caster_id(32) skill_id(32) skill_level(32) target_count(32) [target_id(32)...]

  Reference: ServerPackets.MAGIC_SKILL_LAUNCHED(0x76)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:caster_id, :skill_id, :skill_level, target_ids: []]
  @type t :: %__MODULE__{}

  @opcode 0x76

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    count = length(p.target_ids)
    targets_bin = Enum.map_join(p.target_ids, fn id -> <<id::little-32>> end)

    <<@opcode::8, p.caster_id::little-32, p.skill_id::little-32, p.skill_level::little-32,
      count::little-32>> <> targets_bin
  end
end

defmodule L2E.Packet.Server.AbnormalStatusUpdate do
  @moduledoc """
  Opcode 0x7F — sends active buff/debuff icons to the client's effect bar.
  Sent whenever a buff is applied or expires.

  Binary layout (AbnormalStatusUpdate.java):
    count(16) + per effect: skill_id(32) level(16) remaining_ticks(32)

  Reference: ServerPackets.ABNORMAL_STATUS_UPDATE(0x7F)
  """
  @behaviour L2E.Packet.Encodable

  alias L2E.Skill.BuffInfo

  defstruct effects: []
  @type t :: %__MODULE__{effects: [BuffInfo.t()]}

  @opcode 0x7F

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{effects: effects}) do
    count = length(effects)

    effects_bin =
      Enum.map_join(effects, fn buff ->
        remaining = BuffInfo.remaining_ticks(buff)
        <<buff.skill_id::little-32, buff.level::little-16, remaining::little-32>>
      end)

    <<@opcode::8, count::little-16>> <> effects_bin
  end
end
