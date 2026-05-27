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
  defstruct [:char_id, :char_name, :x, :y, :z, :heading, :hp, :max_hp, pvp_flag: 0, karma: 0]
  @type t :: %__MODULE__{}

  @opcode 0x04

  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = p) do
    name = encode_utf16(p.char_name)
    pvp_flag = p.pvp_flag || 0
    karma = p.karma || 0

    <<@opcode::8, p.x::little-32-signed, p.y::little-32-signed, p.z::little-32-signed,
      p.heading::little-32, p.char_id::little-32, name::binary, p.hp::little-32,
      p.max_hp::little-32, pvp_flag::little-32, karma::little-32>>
  end

  defp encode_utf16(nil), do: <<0::16>>

  defp encode_utf16(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.CharInfo do
  @moduledoc "Sent to a player when another character enters their AOI."
  @behaviour L2E.Packet.Encodable

  defstruct [:char_id, :char_name, :x, :y, :z, :heading, pvp_flag: 0, karma: 0]
  @type t :: %__MODULE__{}

  @opcode 0x03

  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = p) do
    name = encode_utf16(p.char_name)
    pvp_flag = p.pvp_flag || 0
    karma = p.karma || 0

    <<@opcode::8, p.x::little-32-signed, p.y::little-32-signed, p.z::little-32-signed,
      p.char_id::little-32, name::binary, p.heading::little-32, pvp_flag::little-32,
      karma::little-32>>
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

# ── M16: NPC Interaction ──────────────────────────────────────────────────────

defmodule L2E.Packet.Server.NpcHtmlMessage do
  @moduledoc """
  Opcode 0x0F — sends an HTML dialog from an NPC to the client.

  Binary layout (NpcHtmlMessage.java):
    npc_object_id(32) html(string)

  Reference: ServerPackets.NPC_HTML_MESSAGE(0x0F)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:npc_object_id, :html]
  @type t :: %__MODULE__{}

  @opcode 0x0F

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{npc_object_id: npc_id, html: html}) do
    html_bin = encode_utf16(html || "")
    <<@opcode::8, npc_id::little-32>> <> html_bin
  end

  defp encode_utf16(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.ActionFail do
  @moduledoc """
  Opcode 0x25 — tells the client an action failed (e.g. out of range).

  Binary layout (ActionFail.java):
    (no body — opcode only)

  Reference: ServerPackets.ACTION_FAIL(0x25)
  """
  @behaviour L2E.Packet.Encodable

  defstruct []
  @type t :: %__MODULE__{}

  @opcode 0x25

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{}) do
    <<@opcode::8, 0::little-32>>
  end
end

defmodule L2E.Packet.Server.BuyList do
  @moduledoc """
  Opcode 0x11 — sends the list of items a merchant NPC sells.

  Binary layout (BuyList.java):
    npc_object_id(32) my_adena(64) count(16) + per item:
      item_id(32) item_type1(16) object_id(32) count(32) item_type2(16)
      custom1(16) equipped(16) bodypart(32) enchant(16) custom2(16)
      aug(32) element(32) price(32)

  Reference: ServerPackets.BUY_LIST(0x11)
  """
  @behaviour L2E.Packet.Encodable

  # items: list of %{item_id, price}
  defstruct [:npc_object_id, :my_adena, items: []]
  @type t :: %__MODULE__{}

  @opcode 0x11

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{npc_object_id: npc_id, my_adena: adena, items: items}) do
    count = length(items)
    body = Enum.map_join(items, &encode_entry/1)
    <<@opcode::8, npc_id::little-32, adena || 0::little-64, count::little-16>> <> body
  end

  defp encode_entry(%{item_id: item_id, price: price}) do
    <<item_id::little-32, 0::little-16, item_id::little-32, 1::little-32, 0::little-16,
      0::little-16, 0::little-16, 0::little-32, 0::little-16, 0::little-16, 0::little-32,
      0::little-32, price::little-32>>
  end
end

# ── M17: Chat System ──────────────────────────────────────────────────────────

defmodule L2E.Packet.Server.CreatureSay do
  @moduledoc """
  Opcode 0x4A — broadcasts a chat message from a creature to nearby players.

  chat_type:
    0 = SAY      1 = SHOUT     2 = TELL
    3 = PARTY    4 = CLAN      8 = TRADE
    12 = HERO   17 = ALL_WORLD

  Binary layout (CreatureSay.java):
    char_id(32) chat_type(32) char_name(string) message(string)

  Reference: ServerPackets.CREATURE_SAY(0x4A)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:char_id, :chat_type, :char_name, :message]
  @type t :: %__MODULE__{}

  @opcode 0x4A

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    name_bin = encode_utf16(p.char_name || "")
    msg_bin = encode_utf16(p.message || "")
    <<@opcode::8, p.char_id::little-32, p.chat_type::little-32>> <> name_bin <> msg_bin
  end

  defp encode_utf16(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.SystemMessage do
  @moduledoc """
  Opcode 0x64 — sends a predefined system message to the client.

  The client renders the message_id from its own message table (syschat.dat).

  Common message IDs:
    1281 = "You cannot invite yourself to a party."
    1305 = "You have joined a party."
    1306 = "You have left the party."
    1308 = "%s has joined the party."
    1309 = "%s has left the party."
    1332 = "You have joined the clan."
    1333 = "You have left the clan."
    614  = "Your invitation was rejected."

  Binary layout (SystemMessage.java):
    message_id(32)

  Reference: ServerPackets.SYSTEM_MESSAGE(0x64)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:message_id]
  @type t :: %__MODULE__{}

  @opcode 0x64

  # Common system message IDs
  def msg_cannot_invite_self, do: 1281
  def msg_joined_party, do: 1305
  def msg_left_party, do: 1306
  def msg_member_joined_party, do: 1308
  def msg_member_left_party, do: 1309
  def msg_joined_clan, do: 1332
  def msg_left_clan, do: 1333
  def msg_rejected, do: 614
  def msg_party_full, do: 1307

  # M82: Party loot mode
  # 1389 = "The party loot type has been changed to %s."  (syschat.dat)
  # 1390 = "Only a party leader may change the party loot type."
  def msg_loot_mode_changed, do: 1389
  def msg_only_leader_can_change_loot, do: 1390

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{message_id: id}) do
    <<@opcode::8, id::little-32>>
  end
end

# ── M18: Ground Items ─────────────────────────────────────────────────────────

defmodule L2E.Packet.Server.SpawnItem do
  @moduledoc """
  Opcode 0x0B — spawns an item on the ground (drop effect).

  Binary layout (SpawnItem.java):
    object_id(32) item_id(32) x(32) y(32) z(32) stackable(32) count(32)

  Reference: ServerPackets.SPAWN_ITEM(0x0B)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:object_id, :item_id, :x, :y, :z, :count, stackable: 0]
  @type t :: %__MODULE__{}

  @opcode 0x0B

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    <<@opcode::8, p.object_id::little-32, p.item_id::little-32, p.x::little-32-signed,
      p.y::little-32-signed, p.z::little-32-signed, p.stackable::little-32, p.count::little-32>>
  end
end

defmodule L2E.Packet.Server.GetItem do
  @moduledoc """
  Opcode 0x0D — tells nearby players that a ground item was picked up.

  Binary layout (GetItem.java):
    char_id(32) object_id(32) x(32) y(32) z(32)

  Reference: ServerPackets.GET_ITEM(0x0D)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:char_id, :object_id, :x, :y, :z]
  @type t :: %__MODULE__{}

  @opcode 0x0D

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    <<@opcode::8, p.char_id::little-32, p.object_id::little-32, p.x::little-32-signed,
      p.y::little-32-signed, p.z::little-32-signed>>
  end
end

# ── M21: Party ────────────────────────────────────────────────────────────────

defmodule L2E.Packet.Server.AskJoinParty do
  @moduledoc """
  Opcode 0x39 — asks the player to join a party.

  Binary layout (AskJoinParty.java):
    requestor_name(string) distribution_type(32)

  Reference: ServerPackets.ASK_JOIN_PARTY(0x39)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:requestor_name, :distribution_type]
  @type t :: %__MODULE__{}

  @opcode 0x39

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    name_bin = encode_utf16(p.requestor_name || "")
    <<@opcode::8>> <> name_bin <> <<p.distribution_type || 0::little-32>>
  end

  defp encode_utf16(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.PartySmallWindowAll do
  @moduledoc """
  Opcode 0x4E — sends the full party state to a member.

  Binary layout (PartySmallWindowAll.java):
    distribution_type(32) count(8) + per member:
      char_name(string) object_id(32) cur_hp(32) max_hp(32)
      cur_mp(32) max_mp(32) vitality(32) level(8) class_id(32)
      is_leader(8) race(32)

  Reference: ServerPackets.PARTY_SMALL_WINDOW_ALL(0x4E)
  """
  @behaviour L2E.Packet.Encodable

  # members: list of %{char_name, object_id, hp, max_hp, mp, max_mp, level, class_id, is_leader}
  defstruct [:distribution_type, members: []]
  @type t :: %__MODULE__{}

  @opcode 0x4E

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{distribution_type: dist, members: members}) do
    count = length(members)
    body = Enum.map_join(members, &encode_member/1)
    <<@opcode::8, dist || 0::little-32, count::8>> <> body
  end

  defp encode_member(m) do
    name_bin = encode_utf16(m.char_name || "")
    leader = if m[:is_leader], do: 1, else: 0

    name_bin <>
      <<m.object_id::little-32, trunc(m[:hp] || 0)::little-32, trunc(m[:max_hp] || 0)::little-32,
        trunc(m[:mp] || 0)::little-32, trunc(m[:max_mp] || 0)::little-32, 0::little-32,
        m[:level] || 1::8, m[:class_id] || 0::little-32, leader::8, 0::little-32>>
  end

  defp encode_utf16(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.PartySmallWindowAdd do
  @moduledoc """
  Opcode 0x4F — notifies existing party members that a new member joined.

  Binary layout (PartySmallWindowAdd.java):
    distribution_type(32) + member fields (same as PartySmallWindowAll member)

  Reference: ServerPackets.PARTY_SMALL_WINDOW_ADD(0x4F)
  """
  @behaviour L2E.Packet.Encodable

  # member: %{char_name, object_id, hp, max_hp, mp, max_mp, level, class_id, is_leader}
  defstruct [:distribution_type, :member]
  @type t :: %__MODULE__{}

  @opcode 0x4F

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{distribution_type: dist, member: m}) do
    name_bin = encode_utf16(m.char_name || "")
    leader = if m[:is_leader], do: 1, else: 0

    <<@opcode::8, dist || 0::little-32>> <>
      name_bin <>
      <<m.object_id::little-32, trunc(m[:hp] || 0)::little-32, trunc(m[:max_hp] || 0)::little-32,
        trunc(m[:mp] || 0)::little-32, trunc(m[:max_mp] || 0)::little-32, 0::little-32,
        m[:level] || 1::8, m[:class_id] || 0::little-32, leader::8, 0::little-32>>
  end

  defp encode_utf16(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.PartySmallWindowDelete do
  @moduledoc """
  Opcode 0x51 — notifies party members that a member has left.

  Binary layout (PartySmallWindowDelete.java):
    object_id(32) char_name(string)

  Reference: ServerPackets.PARTY_SMALL_WINDOW_DELETE(0x51)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:object_id, :char_name]
  @type t :: %__MODULE__{}

  @opcode 0x51

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    name_bin = encode_utf16(p.char_name || "")
    <<@opcode::8, p.object_id::little-32>> <> name_bin
  end

  defp encode_utf16(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.PartySmallWindowUpdate do
  @moduledoc """
  Opcode 0x52 — updates a party member's vitals in the party window.

  Binary layout (PartySmallWindowUpdate.java):
    object_id(32) cur_hp(32) max_hp(32) cur_mp(32) max_mp(32) vitality(32)

  Reference: ServerPackets.PARTY_SMALL_WINDOW_UPDATE(0x52)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:object_id, :hp, :max_hp, :mp, :max_mp]
  @type t :: %__MODULE__{}

  @opcode 0x52

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    <<@opcode::8, p.object_id::little-32, trunc(p.hp || 0)::little-32,
      trunc(p.max_hp || 0)::little-32, trunc(p.mp || 0)::little-32,
      trunc(p.max_mp || 0)::little-32, 0::little-32>>
  end
end

# ── M22: Clans ────────────────────────────────────────────────────────────────

defmodule L2E.Packet.Server.AskJoinPledge do
  @moduledoc """
  Opcode 0x32 — asks the player to join a clan.

  Binary layout (AskJoinPledge.java):
    requestor_id(32) clan_name(string)

  Reference: ServerPackets.ASK_JOIN_PLEDGE(0x32)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:requestor_id, :clan_name]
  @type t :: %__MODULE__{}

  @opcode 0x32

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    name_bin = encode_utf16(p.clan_name || "")
    <<@opcode::8, p.requestor_id::little-32>> <> name_bin
  end

  defp encode_utf16(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.PledgeShowMemberListAll do
  @moduledoc """
  Opcode 0x53 — sends the full clan member list.

  Binary layout (PledgeShowMemberListAll.java):
    type(32) clan_id(32) count(32) + per member:
      char_name(string) level(32) class_id(32) object_id(32) pledged(32)

  Reference: ServerPackets.PLEDGE_SHOW_MEMBER_LIST_ALL(0x53)
  """
  @behaviour L2E.Packet.Encodable

  # members: list of %{char_name, level, class_id, object_id}
  defstruct [:clan_id, members: []]
  @type t :: %__MODULE__{}

  @opcode 0x53

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{clan_id: clan_id, members: members}) do
    count = length(members)
    body = Enum.map_join(members, &encode_member/1)
    <<@opcode::8, 0::little-32, clan_id || 0::little-32, count::little-32>> <> body
  end

  defp encode_member(m) do
    name_bin = encode_utf16(m.char_name || "")

    name_bin <>
      <<m[:level] || 1::little-32, m[:class_id] || 0::little-32, m.object_id::little-32,
        1::little-32>>
  end

  defp encode_utf16(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.PledgeShowMemberListAdd do
  @moduledoc """
  Opcode 0x55 — notifies existing clan members that a new member joined.

  Binary layout (PledgeShowMemberListAdd.java):
    char_name(string) level(32) class_id(32) object_id(32) pledged(32)

  Reference: ServerPackets.PLEDGE_SHOW_MEMBER_LIST_ADD(0x55)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:char_name, :level, :class_id, :object_id]
  @type t :: %__MODULE__{}

  @opcode 0x55

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    name_bin = encode_utf16(p.char_name || "")

    <<@opcode::8>> <>
      name_bin <>
      <<p.level || 1::little-32, p.class_id || 0::little-32, p.object_id::little-32,
        1::little-32>>
  end

  defp encode_utf16(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.PledgeShowMemberListDelete do
  @moduledoc """
  Opcode 0x56 — notifies clan members that a member has left.

  Binary layout (PledgeShowMemberListDelete.java):
    char_name(string)

  Reference: ServerPackets.PLEDGE_SHOW_MEMBER_LIST_DELETE(0x56)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:char_name]
  @type t :: %__MODULE__{}

  @opcode 0x56

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{char_name: name}) do
    name_bin = encode_utf16(name || "")
    <<@opcode::8>> <> name_bin
  end

  defp encode_utf16(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.PledgeInfo do
  @moduledoc """
  Opcode 0x83 — sends basic clan identification info.

  Binary layout (PledgeInfo.java):
    clan_id(32) clan_name(string) ally_name(string)

  Reference: ServerPackets.PLEDGE_INFO(0x83)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:clan_id, :clan_name, ally_name: ""]
  @type t :: %__MODULE__{}

  @opcode 0x83

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    clan_name_bin = encode_utf16(p.clan_name || "")
    ally_name_bin = encode_utf16(p.ally_name || "")
    <<@opcode::8, p.clan_id || 0::little-32>> <> clan_name_bin <> ally_name_bin
  end

  defp encode_utf16(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.PledgeShowInfoUpdate do
  @moduledoc """
  Opcode 0x88 — sends detailed clan status info including level and reputation.

  Binary layout (PledgeShowInfoUpdate.java):
    clan_id(32) crest_id(32) level(32) castle_id(32) hideout_id(32)
    rank(32) reputation(32) unknown1(32) unknown2(32) ally_id(32)
    ally_name(string) ally_crest_id(32) is_at_war(32)

  Reference: ServerPackets.PLEDGE_SHOW_INFO_UPDATE(0x88)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [
    :clan_id,
    crest_id: 0,
    level: 1,
    castle_id: 0,
    clan_hall_id: 0,
    reputation_points: 0,
    ally_name: ""
  ]

  @type t :: %__MODULE__{}

  @opcode 0x88

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    ally_name_bin = encode_utf16(p.ally_name || "")

    <<@opcode::8, p.clan_id || 0::little-32, p.crest_id || 0::little-32, p.level || 1::little-32,
      p.castle_id || 0::little-32, p.clan_hall_id || 0::little-32, 0::little-32,
      p.reputation_points || 0::little-32, 0::little-32, 0::little-32,
      0::little-32>> <> ally_name_bin <> <<0::little-32, 0::little-32>>
  end

  defp encode_utf16(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.TeleportToLocation do
  @moduledoc """
  Opcode 0x29 — teleports a character (or NPC) to the given coordinates.

  The client immediately moves the target object to the new position and
  plays the teleport visual effect.

  Binary layout (TeleportToLocation.java):
    object_id(32) x(32) y(32) z(32)

  Reference: ServerPackets.TELEPORT_TO_LOCATION(0x29)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:object_id, :x, :y, :z]
  @type t :: %__MODULE__{}

  @opcode 0x29

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    <<@opcode::8, p.object_id::little-32, p.x::little-32-signed, p.y::little-32-signed,
      p.z::little-32-signed>>
  end
end

defmodule L2E.Packet.Server.WareHouseDepositList do
  @moduledoc """
  Opcode 0x41 — sends the list of items the player can deposit into their warehouse.

  The client shows the deposit UI with all inventory items eligible for deposit.

  Binary layout (WareHouseDepositList.java):
    player_adena(32) count(32) + per item: object_id(32) item_id(32) count(32) enchant(16)

  Reference: ServerPackets.WARE_HOUSE_DEPOSIT_LIST(0x41)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:player_adena, items: []]
  @type t :: %__MODULE__{}

  @opcode 0x41

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    count = length(p.items)

    items_bin =
      Enum.map_join(p.items, fn item ->
        <<item[:id] || item[:object_id] || 0::little-32, item.item_id::little-32,
          item.count::little-32, item[:enchant_level] || 0::little-16>>
      end)

    <<@opcode::8, p.player_adena || 0::little-32, count::little-32>> <> items_bin
  end
end

defmodule L2E.Packet.Server.WareHouseWithdrawList do
  @moduledoc """
  Opcode 0x42 — sends the list of items currently stored in the warehouse.

  The client shows the withdrawal UI.

  Binary layout (WareHouseWithdrawList.java):
    count(32) + per item: object_id(32) item_id(32) count(32) enchant(16)

  Reference: ServerPackets.WARE_HOUSE_WITHDRAW_LIST(0x42)
  """
  @behaviour L2E.Packet.Encodable

  defstruct items: []
  @type t :: %__MODULE__{}

  @opcode 0x42

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{items: items}) do
    count = length(items)

    items_bin =
      Enum.map_join(items, fn item ->
        <<item.id::little-32, item.item_id::little-32, item.count::little-32,
          item[:enchant_level] || 0::little-16>>
      end)

    <<@opcode::8, count::little-32>> <> items_bin
  end
end

defmodule L2E.Packet.Server.SendTradeRequest do
  @moduledoc """
  Opcode 0x5E — server sends a trade invite to the target player.

  Binary layout: partner_object_id(32)

  Reference: ServerPackets.SEND_TRADE_REQUEST(0x5E)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:partner_object_id, :partner_name]
  @type t :: %__MODULE__{}

  @opcode 0x5E

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    name_bin = encode_string(p.partner_name || "")
    <<@opcode::8, p.partner_object_id || 0::little-32>> <> name_bin
  end

  defp encode_string(s) do
    chars = :unicode.characters_to_binary(s, :utf8, {:utf16, :little})
    chars <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.TradeStart do
  @moduledoc """
  Opcode 0x1E — opens the trade window on the client.

  Binary layout (TradeStart.java): partner_object_id(32) count(32) + per item:
    object_id(32) item_id(32) count(64) enchant(16) ...

  Reference: ServerPackets.TRADE_START(0x1E)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:partner_object_id, items: []]
  @type t :: %__MODULE__{}

  @opcode 0x1E

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    count = length(p.items)

    items_bin =
      Enum.map_join(p.items, fn item ->
        obj_id = item[:id] || item[:object_id] || 0

        <<obj_id::little-32, item.item_id::little-32, item[:count] || 1::little-64,
          item[:enchant_level] || 0::little-16>>
      end)

    <<@opcode::8, p.partner_object_id || 0::little-32, count::little-32>> <> items_bin
  end
end

defmodule L2E.Packet.Server.TradeOwnAdd do
  @moduledoc """
  Opcode 0x20 — player's own offer updated.

  Binary layout: count(32) + per item: object_id(32) item_id(32) count(64) enchant(16)

  Reference: ServerPackets.TRADE_OWN_ADD(0x20)
  """
  @behaviour L2E.Packet.Encodable

  defstruct items: []
  @type t :: %__MODULE__{}

  @opcode 0x20

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{items: items}) do
    count = length(items)

    items_bin =
      Enum.map_join(items, fn {obj_id, qty} ->
        <<obj_id::little-32, 0::little-32, qty::little-64, 0::little-16>>
      end)

    <<@opcode::8, count::little-32>> <> items_bin
  end
end

defmodule L2E.Packet.Server.TradeOtherAdd do
  @moduledoc """
  Opcode 0x21 — partner's offer updated.

  Reference: ServerPackets.TRADE_OTHER_ADD(0x21)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:side, items: []]
  @type t :: %__MODULE__{}

  @opcode 0x21

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{items: items}) do
    count = length(items)

    items_bin =
      Enum.map_join(items, fn {obj_id, qty} ->
        <<obj_id::little-32, 0::little-32, qty::little-64, 0::little-16>>
      end)

    <<@opcode::8, count::little-32>> <> items_bin
  end
end

defmodule L2E.Packet.Server.TradeDone do
  @moduledoc """
  Opcode 0x22 — trade is complete (or failed).

  Binary layout: result(32) where 1=success, 0=cancel

  Reference: ServerPackets.TRADE_DONE(0x22)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:result]
  @type t :: %__MODULE__{}

  @opcode 0x22

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{result: result}) do
    result_int = if result == :success, do: 1, else: 0
    <<@opcode::8, result_int::little-32>>
  end
end

defmodule L2E.Packet.Server.TradeCancelled do
  @moduledoc """
  Opcode 0x22 with result=0 — trade was cancelled.

  We reuse TradeDone with result=:cancel for the same wire format.
  This module exists as a convenience alias.

  Reference: ServerPackets.TRADE_DONE(0x22) with result 0
  """
  @behaviour L2E.Packet.Encodable

  defstruct []
  @type t :: %__MODULE__{}

  @opcode 0x22

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{}) do
    <<@opcode::8, 0::little-32>>
  end
end

defmodule L2E.Packet.Server.TradeConfirm do
  @moduledoc """
  Opcode 0x75 or 0x7C — one player pressed OK in the trade window.

  0x75 = own side confirmed (TRADE_PRESS_OWN_OK)
  0x7C = other side confirmed (TRADE_PRESS_OTHER_OK)

  Reference: ServerPackets.TRADE_PRESS_OWN_OK(0x75), TRADE_PRESS_OTHER_OK(0x7C)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:side]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{side: :a}) do
    <<0x75::8>>
  end

  def encode(%__MODULE__{side: :b}) do
    <<0x7C::8>>
  end

  def encode(%__MODULE__{}) do
    <<0x75::8>>
  end
end

defmodule L2E.Packet.Server.EnchantResult do
  @moduledoc """
  Opcode 0x81 — reports the result of an enchant attempt to the client.

  Binary layout: result(32)
    0 = cancelled/failed + item destroyed
    1 = success
    2 = failed + item destroyed
    3 = blessed fail (item kept at current enchant)

  Reference: ServerPackets.ENCHANT_RESULT(0x81)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:result]
  @type t :: %__MODULE__{}

  @opcode 0x81

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{result: result}) do
    result_int =
      case result do
        :success -> 1
        :fail -> 2
        :blessed_fail -> 3
        _ -> 0
      end

    <<@opcode::8, result_int::little-32>>
  end
end

# M39 — Confirms auto soulshot/spiritshot toggle to client (extended 0xFE/0x12)
defmodule L2E.Packet.Server.ExAutoSoulShot do
  @moduledoc "0xFE/0x12 — confirms auto soulshot/spiritshot toggle."
  @behaviour L2E.Packet.Encodable

  defstruct [:item_id, :type]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{item_id: item_id, type: type}) do
    <<0xFE, 0x12::little-16, item_id::little-32, type::little-32>>
  end
end

# M35 — Private store server packets
defmodule L2E.Packet.Server.PrivateStoreMsgSell do
  @moduledoc "0x9C — broadcasts that a player opened (or updated) a sell store."
  @behaviour L2E.Packet.Encodable

  defstruct [:object_id, :title]
  @type t :: %__MODULE__{}

  @opcode 0x9C

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{object_id: object_id, title: title}) do
    title_bin = :unicode.characters_to_binary(title || "", :utf8, {:utf16, :little}) <> <<0, 0>>
    <<@opcode::8, object_id::little-32>> <> title_bin
  end
end

defmodule L2E.Packet.Server.PrivateStoreManageListSell do
  @moduledoc "0x9A — sends seller's inventory and current store config for store management UI."
  @behaviour L2E.Packet.Encodable

  # available_items and store_items: [%{type2, obj_id, item_id, count, enchant, bodypart, price, ref_price}]
  defstruct [:seller_id, :is_package, :adena, :available_items, :store_items]
  @type t :: %__MODULE__{}

  @opcode 0x9A

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{
        seller_id: seller_id,
        is_package: is_package,
        adena: adena,
        available_items: available_items,
        store_items: store_items
      }) do
    avail = available_items || []
    stored = store_items || []

    avail_bin =
      Enum.reduce(avail, <<length(avail)::little-32>>, fn item, acc ->
        acc <>
          <<item.type2::little-32, item.obj_id::little-32, item.item_id::little-32,
            item.count::little-32, 0::little-16, item.enchant::little-16, 0::little-16,
            item.bodypart::little-32, item.price::little-32>>
      end)

    stored_bin =
      Enum.reduce(stored, <<length(stored)::little-32>>, fn item, acc ->
        acc <>
          <<item.type2::little-32, item.obj_id::little-32, item.item_id::little-32,
            item.count::little-32, 0::little-16, item.enchant::little-16, 0::little-16,
            item.bodypart::little-32, item.price::little-32, item[:ref_price] || 0::little-32>>
      end)

    <<@opcode::8, seller_id::little-32, is_package::little-32, adena::little-32>> <>
      avail_bin <> stored_bin
  end
end

defmodule L2E.Packet.Server.PrivateStoreListSell do
  @moduledoc "0x9B — sends a seller's active store list to the buyer."
  @behaviour L2E.Packet.Encodable

  # items: [%{type2, obj_id, item_id, count, enchant, bodypart, price, ref_price}]
  defstruct [:seller_id, :is_package, :buyer_adena, :items]
  @type t :: %__MODULE__{}

  @opcode 0x9B

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{
        seller_id: seller_id,
        is_package: is_package,
        buyer_adena: buyer_adena,
        items: items
      }) do
    store_items = items || []

    items_bin =
      Enum.reduce(store_items, <<length(store_items)::little-32>>, fn item, acc ->
        acc <>
          <<item.type2::little-32, item.obj_id::little-32, item.item_id::little-32,
            item.count::little-32, 0::little-16, item.enchant::little-16, 0::little-16,
            item.bodypart::little-32, item.price::little-32, item[:ref_price] || 0::little-32>>
      end)

    <<@opcode::8, seller_id::little-32, is_package::little-32, buyer_adena::little-32>> <>
      items_bin
  end
end

# ---- M43: Private Store — Buy packets ----------------------------------------

defmodule L2E.Packet.Server.PrivateStoreMsgBuy do
  @moduledoc "0xB9 — broadcasts that a player opened (or closed) a buy store."
  @behaviour L2E.Packet.Encodable

  defstruct [:object_id, :title]
  @type t :: %__MODULE__{}

  @opcode 0xB9

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{object_id: object_id, title: title}) do
    title_bin =
      :unicode.characters_to_binary(title || "", :utf8, {:utf16, :little}) <> <<0, 0>>

    <<@opcode::8, object_id::little-32>> <> title_bin
  end
end

defmodule L2E.Packet.Server.PrivateStoreManageListBuy do
  @moduledoc """
  0xB7 — sends the owner's adena balance and current buy-list configuration
  back to the owner when they open the buy-store management UI.

  available_items: inventory items the owner has (shown on the left panel so the
    client can populate the \"what I want to buy\" list). Optional — an empty list
    is accepted by the client.

  buy_list: items already configured in the buy store.
    Each entry: %{item_id, count, price, ref_price \\\\ 0, bodypart \\\\ 0, type2 \\\\ 0}
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:owner_id, :adena, :available_items, :buy_list]
  @type t :: %__MODULE__{}

  @opcode 0xB7

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{
        owner_id: owner_id,
        adena: adena,
        available_items: available_items,
        buy_list: buy_list
      }) do
    avail = available_items || []
    buy = buy_list || []

    avail_bin =
      Enum.reduce(avail, <<length(avail)::little-32>>, fn item, acc ->
        acc <>
          <<Map.get(item, :item_id, 0)::little-32, 0::little-16,
            Map.get(item, :count, 0)::little-32, Map.get(item, :ref_price, 0)::little-32,
            0::little-16, Map.get(item, :bodypart, 0)::little-32,
            Map.get(item, :type2, 0)::little-16>>
      end)

    buy_bin =
      Enum.reduce(buy, <<length(buy)::little-32>>, fn item, acc ->
        acc <>
          <<Map.get(item, :item_id, 0)::little-32, 0::little-16,
            Map.get(item, :count, 0)::little-32, Map.get(item, :ref_price, 0)::little-32,
            0::little-16, Map.get(item, :bodypart, 0)::little-32,
            Map.get(item, :type2, 0)::little-16>>
      end)

    <<@opcode::8, owner_id::little-32, adena::little-32>> <> avail_bin <> buy_bin
  end
end

defmodule L2E.Packet.Server.PrivateStoreListBuy do
  @moduledoc """
  0xB8 — sends a buyer's active buy-store list to potential sellers who click on them.

  items: each entry must contain at minimum: item_id, count, price.
    Optional: obj_id (0 if absent), enchant (0), ref_price (0), bodypart (0), type2 (0).
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:owner_id, :owner_adena, :items]
  @type t :: %__MODULE__{}

  @opcode 0xB8

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{owner_id: owner_id, owner_adena: owner_adena, items: items}) do
    store_items = items || []

    items_bin =
      Enum.reduce(store_items, <<length(store_items)::little-32>>, fn item, acc ->
        count = Map.get(item, :count, 0)

        acc <>
          <<Map.get(item, :obj_id, 0)::little-32, Map.get(item, :item_id, 0)::little-32,
            Map.get(item, :enchant, 0)::little-16, count::little-32,
            Map.get(item, :ref_price, 0)::little-32, 0::little-16,
            Map.get(item, :bodypart, 0)::little-32, Map.get(item, :type2, 0)::little-16,
            Map.get(item, :price, 0)::little-32, count::little-32>>
      end)

    <<@opcode::8, owner_id::little-32, owner_adena || 0::little-32>> <> items_bin
  end
end

# ---- M44: Skill Learn packets ------------------------------------------------

defmodule L2E.Packet.Server.AcquireSkillInfo do
  @moduledoc """
  0x8B — responds to RequestAcquireSkillInfo with the skill's SP cost and
  minimum character level required to learn it.

  `acquire_type` is sent as 0 (CLASS skill) for all normal class skills.
  No item requirements are sent (the `reqs` list size is always 0 here).
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:skill_id, :skill_level, :sp_cost, :min_level]
  @type t :: %__MODULE__{}

  @opcode 0x8B

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{skill_id: skill_id, skill_level: skill_level, sp_cost: sp_cost}) do
    <<
      @opcode::8,
      skill_id || 0::little-32,
      skill_level || 1::little-32,
      sp_cost || 0::little-32,
      # acquire_type = 0 (CLASS)
      0::little-32,
      # item requirement count = 0
      0::little-32
    >>
  end
end

defmodule L2E.Packet.Server.AcquireSkillDone do
  @moduledoc "0x8E — confirms that the server processed a skill-learn request."
  @behaviour L2E.Packet.Encodable

  # skill_id and skill_level are stored for logging only; not sent in the packet.
  defstruct [:skill_id, :skill_level]
  @type t :: %__MODULE__{}

  @opcode 0x8E

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{}) do
    <<@opcode::8>>
  end
end

defmodule L2E.Packet.Server.DoorInfo do
  @moduledoc """
  Opcode 0x31 — sends initial door state to the client when entering a zone.

  Binary layout (DoorInfo.java):
    door_id(32LE) show_hp(8) is_open(8) is_attackable(8)
    max_hp(32LE) current_hp(32LE) x(32LE) y(32LE) z(32LE)

  Reference: ServerPackets.DOOR_INFO(0x31)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:door_id, :is_open, :max_hp, :current_hp, :x, :y, :z]
  @type t :: %__MODULE__{}

  @opcode 0x31

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    <<@opcode::8, p.door_id::little-32, 0::8, p.is_open::8, 0::8, p.max_hp || 0::little-32,
      p.current_hp || 0::little-32, p.x || 0::little-32, p.y || 0::little-32,
      p.z || 0::little-32>>
  end
end

defmodule L2E.Packet.Server.DoorStatusUpdate do
  @moduledoc """
  Opcode 0x2C — broadcast door open/close state change.

  Binary layout (DoorStatusUpdate.java): door_id(32LE) is_open(8)

  Reference: ServerPackets.DOOR_STATUS_UPDATE(0x2C)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:door_id, :is_open]
  @type t :: %__MODULE__{}

  @opcode 0x2C

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    <<@opcode::8, p.door_id::little-32, p.is_open::8>>
  end
end

defmodule L2E.Packet.Server.ShortcutInit do
  @moduledoc """
  Opcode 0x45 — sent on world entry with all registered shortcuts.

  Binary layout (ShortcutInit.java):
    count(32LE)
    for each shortcut:
      type(32LE)  page_slot(32LE)  then type-specific fields:
        SKILL (1): skill_id(32) level(32) 0(8) 1(32)
        ITEM  (2): item_id(32) 1(32) -1(32) 0(32) 0(32) 0(16) 0(16)
        other    : id(32) 1(32)

  Reference: ServerPackets.SHORT_CUT_INIT(0x45)
  """
  @behaviour L2E.Packet.Encodable

  defstruct shortcuts: []
  @type t :: %__MODULE__{}

  @opcode 0x45

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{shortcuts: shortcuts}) do
    count = length(shortcuts)
    body = Enum.map_join(shortcuts, &encode_shortcut/1)
    <<@opcode::8, count::little-32>> <> body
  end

  defp encode_shortcut(%{type: 1, slot: slot, page: page, shortcut_id: id, level: lvl}) do
    page_slot = slot + page * 12
    <<1::little-32, page_slot::little-32, id::little-32, lvl::little-32, 0::8, 1::little-32>>
  end

  defp encode_shortcut(%{type: 2, slot: slot, page: page, shortcut_id: id}) do
    page_slot = slot + page * 12

    <<2::little-32, page_slot::little-32, id::little-32, 1::little-32, -1::little-32-signed,
      0::little-32, 0::little-32, 0::little-16, 0::little-16>>
  end

  defp encode_shortcut(%{type: type, slot: slot, page: page, shortcut_id: id}) do
    page_slot = slot + page * 12
    <<type::little-32, page_slot::little-32, id::little-32, 1::little-32>>
  end
end

defmodule L2E.Packet.Server.ShortcutRegister do
  @moduledoc """
  Opcode 0x44 — confirms a shortcut registration to the client.

  Binary layout (ShortcutRegister.java):
    type(32LE)  page_slot(32LE)  type-specific fields  1(32LE)

  Reference: ServerPackets.SHORT_CUT_REGISTER(0x44)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:type, :slot, :page, :shortcut_id, :level]
  @type t :: %__MODULE__{}

  @opcode 0x44

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    page_slot = p.slot + p.page * 12
    type_body = encode_type_body(p)
    <<@opcode::8, p.type::little-32, page_slot::little-32>> <> type_body <> <<1::little-32>>
  end

  defp encode_type_body(%{type: 1, shortcut_id: id, level: lvl}) do
    <<id::little-32, lvl::little-32, 0::8>>
  end

  defp encode_type_body(%{shortcut_id: id}) do
    <<id::little-32>>
  end
end

defmodule L2E.Packet.Server.AutoAttackStart do
  @moduledoc """
  Opcode 0x2B — notifies client that an entity started auto-attacking.

  Binary layout (AutoAttackStart.java): object_id(32LE)

  Reference: ServerPackets.AUTO_ATTACK_START(0x2B)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:object_id]
  @type t :: %__MODULE__{}

  @opcode 0x2B

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{object_id: id}) do
    <<@opcode::8, id::little-32>>
  end
end

defmodule L2E.Packet.Server.AutoAttackStop do
  @moduledoc """
  Opcode 0x2C — notifies client that an entity stopped auto-attacking.

  Binary layout (AutoAttackStop.java): object_id(32LE)

  Reference: ServerPackets.AUTO_ATTACK_STOP(0x2C)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:object_id]
  @type t :: %__MODULE__{}

  @opcode 0x2C

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{object_id: id}) do
    <<@opcode::8, id::little-32>>
  end
end

defmodule L2E.Packet.Server.MoveToPawn do
  @moduledoc """
  Opcode 0x60 — entity is chasing a moving target (follow-type movement).

  Binary layout (MoveToPawn.java):
    follower_object_id(32) target_object_id(32) distance(32)
    follower_x(32) follower_y(32) follower_z(32)
    target_x(32) target_y(32) target_z(32)

  Reference: ServerPackets.MOVE_TO_PAWN(0x60)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [
    :follower_object_id,
    :target_object_id,
    :distance,
    :follower_x,
    :follower_y,
    :follower_z,
    :target_x,
    :target_y,
    :target_z
  ]

  @type t :: %__MODULE__{}

  @opcode 0x60

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    <<@opcode::8, p.follower_object_id::little-32, p.target_object_id::little-32,
      p.distance::little-32, p.follower_x::little-32-signed, p.follower_y::little-32-signed,
      p.follower_z::little-32-signed, p.target_x::little-32-signed, p.target_y::little-32-signed,
      p.target_z::little-32-signed>>
  end
end

# ---------------------------------------------------------------------------
# M56: RecipeItemMakeInfo (0xD7) — result of crafting via self-recipe
#
# Reference: RecipeItemMakeInfo.java
# Binary layout:
#   opcode(8), recipe_id(32LE), is_common(32LE), current_mp(32LE),
#   max_mp(32LE), success(32LE)
# ---------------------------------------------------------------------------
defmodule L2E.Packet.Server.RecipeItemMakeInfo do
  @moduledoc "Crafting result packet sent after RequestRecipeItemMakeSelf."

  @behaviour L2E.Packet.Encodable

  defstruct [:recipe_id, :current_mp, :max_mp, success: true, is_common: false]

  @type t :: %__MODULE__{}

  @opcode 0xD7

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    is_common = if p.is_common, do: 1, else: 0
    success = if p.success, do: 1, else: 0

    <<@opcode::8, p.recipe_id::little-32, is_common::little-32, p.current_mp::little-32,
      p.max_mp::little-32, success::little-32>>
  end
end

# ---------------------------------------------------------------------------
# M56: HennaInfo (0xE4) — current henna (dye/tattoo) state
#
# Reference: HennaInfo.java
# Binary layout:
#   opcode(8)
#   int_bonus(8s), str_bonus(8s), con_bonus(8s), men_bonus(8s),
#   dex_bonus(8s), wit_bonus(8s)
#   slots_count(32LE) = 3
#   henna_count(32LE)
#   For each henna: henna_id(32LE), dye_id(32LE), is_equipped(8=1)
# ---------------------------------------------------------------------------
defmodule L2E.Packet.Server.HennaInfo do
  @moduledoc "Sends current henna slot state to the client."

  @behaviour L2E.Packet.Encodable

  defstruct int_bonus: 0,
            str_bonus: 0,
            con_bonus: 0,
            men_bonus: 0,
            dex_bonus: 0,
            wit_bonus: 0,
            hennas: []

  @type t :: %__MODULE__{}

  @opcode 0xE4

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    henna_list = p.hennas || []
    henna_count = length(henna_list)

    henna_bytes =
      Enum.reduce(henna_list, <<>>, fn h, acc ->
        acc <> <<h.henna_id::little-32, h.dye_id::little-32, 1::8>>
      end)

    <<@opcode::8, p.int_bonus::8-signed, p.str_bonus::8-signed, p.con_bonus::8-signed,
      p.men_bonus::8-signed, p.dex_bonus::8-signed, p.wit_bonus::8-signed, 3::little-32,
      henna_count::little-32, henna_bytes::binary>>
  end
end

# ---------------------------------------------------------------------------
# M56: ExVariationResult (0xFE sub 0x0055) — augmentation result
#
# Reference: ExVariationResult.java
# Binary layout:
#   0xFE(8), 0x0055(16LE), stat12(32LE), stat34(32LE), result(32LE)
#   result: 1 = success, 0 = fail
# ---------------------------------------------------------------------------
defmodule L2E.Packet.Server.ExVariationResult do
  @moduledoc "Sent after RequestRefine (life stone augmentation)."

  @behaviour L2E.Packet.Encodable

  defstruct stat12: 0, stat34: 0, result: 0

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    <<0xFE::8, 0x0055::little-16, p.stat12::little-32, p.stat34::little-32, p.result::little-32>>
  end
end

# ---------------------------------------------------------------------------
# M60: RestartResponse (0x5F) — sent to confirm RequestRestart
#
# Binary layout:
#   0x5F(8), response(8)  — response: 1=ok
# ---------------------------------------------------------------------------
defmodule L2E.Packet.Server.RestartResponse do
  @moduledoc "Confirms a player's request to return to character select."

  @behaviour L2E.Packet.Encodable

  defstruct response: 1

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    <<0x5F::8, p.response::8>>
  end
end

# ---------------------------------------------------------------------------
# M61: ChangeMoveType (0x30) — run/walk mode broadcast
#
# Binary layout:
#   0x30(8), object_id(32LE), run_mode(32LE), x(32LE), y(32LE), z(32LE)
#   run_mode: 1=running, 0=walking
# ---------------------------------------------------------------------------
defmodule L2E.Packet.Server.ChangeMoveType do
  @moduledoc "Broadcasts a character's run/walk mode change to nearby players."

  @behaviour L2E.Packet.Encodable

  defstruct object_id: 0, run_mode: 1, x: 0, y: 0, z: 0

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    <<0x30::8, p.object_id::little-32, p.run_mode::little-32, p.x::little-32-signed,
      p.y::little-32-signed, p.z::little-32-signed>>
  end
end

# ---------------------------------------------------------------------------
# M61: ChangeWaitType (0x31) — sit/stand/fakedeath broadcast
#
# Binary layout:
#   0x31(8), object_id(32LE), move_type(32LE), x(32LE), y(32LE), z(32LE)
#   move_type: 0=standing, 1=sitting, 2=fakedeath
# ---------------------------------------------------------------------------
defmodule L2E.Packet.Server.ChangeWaitType do
  @moduledoc "Broadcasts a character's sit/stand state to nearby players."

  @behaviour L2E.Packet.Encodable

  defstruct object_id: 0, move_type: 0, x: 0, y: 0, z: 0

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    <<0x31::8, p.object_id::little-32, p.move_type::little-32, p.x::little-32-signed,
      p.y::little-32-signed, p.z::little-32-signed>>
  end
end

# ---------------------------------------------------------------------------
# M63: RelationChanged (0x60) — relation bitmask broadcast
#
# Sent to nearby players when a player's relation changes (attack mode,
# PvP flag, party membership). Clients use this to colour health bars.
#
# Binary layout:
#   0x60(8), object_id(32LE), relation(32LE), auto_attackable(8), rec_hp_percent(8)
#
# relation bitmask (L2 Interlude):
#   0x01 = party member, 0x02 = party leader, 0x04 = auto attackable,
#   0x08 = PvP mode, 0x10 = dead, 0x40 = in combat
# ---------------------------------------------------------------------------
defmodule L2E.Packet.Server.RelationChanged do
  @moduledoc "Notifies nearby clients of a relation/status change for an object."

  @behaviour L2E.Packet.Encodable

  defstruct object_id: 0, relation: 0, auto_attackable: 0, rec_hp_percent: 100

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    <<0x60::8, p.object_id::little-32, p.relation::little-32, p.auto_attackable::8,
      p.rec_hp_percent::8>>
  end
end

# ---------------------------------------------------------------------------
# M64: MultiSellList (0xFE/0x000B) — sends a multisell exchange list to client
#
# Binary layout (extended packet):
#   0xFE(8), 0x000B(16LE), list_id(32LE), page(8=0), entry_count(16LE),
#   for each entry:
#     entry_id(32LE), adena_cost(32LE=0), product_count(16LE),
#     for each product:
#       item_id(32LE), count(32LE), item_type(32LE=0),
#     ingredient_count(16LE),
#     for each ingredient:
#       item_id(32LE), count(32LE), item_type(32LE=0)
# ---------------------------------------------------------------------------
defmodule L2E.Packet.Server.MultiSellList do
  @moduledoc "Sends a multisell exchange list to the client for display."

  @behaviour L2E.Packet.Encodable

  defstruct list_id: 0, entries: []

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    entry_count = length(p.entries)
    entries_bin = encode_entries(p.entries)

    <<0xFE::8, 0x000B::little-16, p.list_id::little-32, 0::8, entry_count::little-16,
      entries_bin::binary>>
  end

  defp encode_entries(entries) do
    Enum.reduce(entries, <<>>, fn entry, acc ->
      products_bin = encode_items(entry.products)
      ingredients_bin = encode_items(entry.ingredients)
      product_count = length(entry.products)
      ingredient_count = length(entry.ingredients)

      acc <>
        <<entry.entry_id::little-32, 0::little-32, product_count::little-16, products_bin::binary,
          ingredient_count::little-16, ingredients_bin::binary>>
    end)
  end

  defp encode_items(items) do
    Enum.reduce(items, <<>>, fn {item_id, count}, acc ->
      acc <> <<item_id::little-32, count::little-32, 0::little-32>>
    end)
  end
end

# ---------------------------------------------------------------------------
# M67: QuestList (0x86) — sends the player's active quest list on login
#
# Binary layout:
#   0x86(8), count(16LE),
#   for each quest:
#     quest_id(32LE), cond(32LE)
# ---------------------------------------------------------------------------
defmodule L2E.Packet.Server.QuestList do
  @moduledoc "Sends the player's active and completed quest list on login/refresh."

  @behaviour L2E.Packet.Encodable

  # quests: list of %{quest_id: int, cond: int}
  defstruct quests: []

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    count = length(p.quests)

    quests_bin =
      Enum.reduce(p.quests, <<>>, fn q, acc ->
        acc <> <<q.quest_id::little-32, q.cond::little-32>>
      end)

    <<0x86::8, count::little-16, quests_bin::binary>>
  end
end

# ---- FASE 3: Friend packets --------------------------------------------------

defmodule L2E.Packet.Server.FriendList do
  @moduledoc "Opcode 0xFA — sends the full friend list to client on login."
  @behaviour L2E.Packet.Encodable

  @opcode 0xFA

  defstruct friends: []

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    count = length(p.friends)

    friends_bin =
      Enum.reduce(p.friends, <<>>, fn f, acc ->
        name_bin = utf16le_string(f.name)
        online_int = if f.online, do: 1, else: 0
        obj_id_online = if f.online, do: f.obj_id, else: 0

        acc <>
          <<f.obj_id::little-32>> <>
          name_bin <>
          <<online_int::little-32, obj_id_online::little-32>>
      end)

    <<@opcode::8, count::little-32>> <> friends_bin
  end

  defp utf16le_string(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.L2Friend do
  @moduledoc """
  Opcode 0xFB — friend add/remove notification.

  type: 1=add, 3=remove.
  """
  @behaviour L2E.Packet.Encodable

  @opcode 0xFB

  defstruct [:type, :obj_id, :name, :online]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    name_bin = utf16le_string(p.name || "")
    online_int = if p.online, do: 1, else: 0
    obj_id_online = if p.online, do: p.obj_id, else: 0

    <<@opcode::8, p.type::little-32, p.obj_id::little-32>> <>
      name_bin <>
      <<online_int::little-32, obj_id_online::little-32>>
  end

  defp utf16le_string(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.FriendStatusPacket do
  @moduledoc "Opcode 0xFC — notifies client that a friend came online or went offline."
  @behaviour L2E.Packet.Encodable

  @opcode 0xFC

  defstruct [:obj_id, :name, :online]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    online_int = if p.online, do: 1, else: 0
    name_bin = utf16le_string(p.name || "")

    <<@opcode::8, online_int::little-32>> <> name_bin <> <<p.obj_id::little-32>>
  end

  defp utf16le_string(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.FriendRecvMsg do
  @moduledoc "Opcode 0xFD — delivers a private friend message to the receiver."
  @behaviour L2E.Packet.Encodable

  @opcode 0xFD

  defstruct [:receiver_name, :sender_name, :message]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    receiver_bin = utf16le_string(p.receiver_name || "")
    sender_bin = utf16le_string(p.sender_name || "")
    message_bin = utf16le_string(p.message || "")

    <<@opcode::8, 0::little-32>> <> receiver_bin <> sender_bin <> message_bin
  end

  defp utf16le_string(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

# ---- FASE 3: Pet Info --------------------------------------------------------

defmodule L2E.Packet.Server.PetInfo do
  @moduledoc "Opcode 0xB1 — full summon/pet state packet sent to owner and nearby players."
  @behaviour L2E.Packet.Encodable

  @opcode 0xB1

  defstruct [
    :summon_type,
    :obj_id,
    :npc_id,
    :x,
    :y,
    :z,
    :heading,
    :m_atk_spd,
    :p_atk_spd,
    :run_spd,
    :walk_spd,
    :swim_run_spd,
    :swim_walk_spd,
    :fly_run_spd,
    :fly_walk_spd,
    :move_multiplier,
    :atk_spd_multiplier,
    :collision_radius,
    :collision_height,
    :weapon,
    :armor,
    :has_owner,
    :is_running,
    :in_combat,
    :is_dead,
    :summoned_value,
    :name,
    :title,
    :pvp_flag,
    :karma,
    :cur_fed,
    :max_fed,
    :cur_hp,
    :max_hp,
    :cur_mp,
    :max_mp,
    :sp,
    :level,
    :exp,
    :exp_this_level,
    :exp_next_level,
    :weight,
    :max_load,
    :p_atk,
    :p_def,
    :m_atk,
    :m_def,
    :accuracy,
    :evasion,
    :critical,
    :move_speed,
    :p_atk_spd2,
    :m_atk_spd2,
    :abnormal_visual_effects,
    :mountable,
    :zone_type,
    :team,
    :soul_shots_per_hit,
    :spirit_shots_per_hit
  ]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    name_bin = utf16le_string(p.name || "")
    title_bin = utf16le_string(p.title || "")
    fly_run = p.fly_run_spd || 0
    fly_walk = p.fly_walk_spd || 0

    <<@opcode::8, p.summon_type || 0::little-32, p.obj_id || 0::little-32,
      p.npc_id || 0::little-32, 0::little-32, p.x || 0::little-32-signed,
      p.y || 0::little-32-signed, p.z || 0::little-32-signed, p.heading || 0::little-32,
      0::little-32, p.m_atk_spd || 0::little-32, p.p_atk_spd || 0::little-32,
      p.run_spd || 0::little-32, p.walk_spd || 0::little-32, p.swim_run_spd || 0::little-32,
      p.swim_walk_spd || 0::little-32, fly_run::little-32, fly_walk::little-32,
      fly_run::little-32, fly_walk::little-32, p.move_multiplier || 1.0::little-float-64,
      p.atk_spd_multiplier || 1.0::little-float-64, p.collision_radius || 0.0::little-float-64,
      p.collision_height || 0.0::little-float-64, p.weapon || 0::little-32,
      p.armor || 0::little-32, 0::little-32, p.has_owner || 0::8, p.is_running || 0::8,
      p.in_combat || 0::8, p.is_dead || 0::8,
      p.summoned_value || 1::8>> <>
      name_bin <>
      title_bin <>
      <<1::little-32, p.pvp_flag || 0::little-32, p.karma || 0::little-32,
        p.cur_fed || 0::little-32, p.max_fed || 0::little-32, p.cur_hp || 0::little-32,
        p.max_hp || 0::little-32, p.cur_mp || 0::little-32, p.max_mp || 0::little-32,
        p.sp || 0::little-32, p.level || 1::little-32, p.exp || 0::little-64,
        p.exp_this_level || 0::little-64, p.exp_next_level || 0::little-64,
        p.weight || 0::little-32, p.max_load || 0::little-32, p.p_atk || 0::little-32,
        p.p_def || 0::little-32, p.m_atk || 0::little-32, p.m_def || 0::little-32,
        p.accuracy || 0::little-32, p.evasion || 0::little-32, p.critical || 0::little-32,
        p.move_speed || 0::little-32, p.p_atk_spd2 || 0::little-32, p.m_atk_spd2 || 0::little-32,
        p.abnormal_visual_effects || 0::little-32, p.mountable || 0::little-16,
        p.zone_type || 0::8, 0::little-16, p.team || 0::8, p.soul_shots_per_hit || 0::little-32,
        p.spirit_shots_per_hit || 0::little-32>>
  end

  defp utf16le_string(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

# ---- FASE 3: Siege Info ------------------------------------------------------

defmodule L2E.Packet.Server.SiegeInfo do
  @moduledoc """
  Opcode 0xC9 — shows siege information for a castle or clan hall.

  residence_id: castle or hall ID.
  show_controls: 1 if viewer is the owning clan leader, 0 otherwise.
  siege_times: optional list of unix timestamps (seconds) for time selection.
  """
  @behaviour L2E.Packet.Encodable

  @opcode 0xC9

  defstruct [
    :residence_id,
    :show_controls,
    :owner_id,
    :clan_name,
    :leader_name,
    :ally_id,
    :ally_name,
    :current_time,
    :siege_time,
    siege_times: []
  ]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    clan_name_bin = utf16le_string(p.clan_name || "")
    leader_name_bin = utf16le_string(p.leader_name || "")
    ally_name_bin = utf16le_string(p.ally_name || "")
    times = p.siege_times || []
    times_bin = Enum.reduce(times, <<>>, fn t, acc -> acc <> <<t::little-32>> end)

    <<@opcode::8, p.residence_id || 0::little-32, p.show_controls || 0::little-32,
      p.owner_id || 0::little-32>> <>
      clan_name_bin <>
      leader_name_bin <>
      <<p.ally_id || 0::little-32>> <>
      ally_name_bin <>
      <<p.current_time || 0::little-32, p.siege_time || 0::little-32, length(times)::little-32>> <>
      times_bin
  end

  defp utf16le_string(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

# ---- M100: Siege attacker/defender lists -------------------------------------

defmodule L2E.Packet.Server.SiegeAttackerList do
  @moduledoc """
  Opcode 0xCA — lists all attacker clans registered for a siege.

  clans: [{clan_id, clan_name, ally_id, ally_name, party_count, member_count}]
  """
  @behaviour L2E.Packet.Encodable

  @opcode 0xCA

  defstruct [:castle_id, clans: []]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{castle_id: castle_id, clans: clans}) do
    count = length(clans)

    clan_data =
      Enum.reduce(clans, <<>>, fn {clan_id, clan_name, ally_id, ally_name, _parties, members},
                                  acc ->
        acc <>
          <<clan_id::little-32>> <>
          utf16le_string(clan_name) <>
          <<ally_id::little-32>> <>
          utf16le_string(ally_name) <>
          <<0::little-32, members::little-32>>
      end)

    <<@opcode::8, castle_id::little-32, count::little-32, count::little-32>> <> clan_data
  end

  defp utf16le_string(str) do
    :unicode.characters_to_binary(str || "", :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.SiegeDefenderList do
  @moduledoc """
  Opcode 0xCB — lists all defender clans registered for a siege.

  clans: [{clan_id, clan_name, ally_id, ally_name, party_count, member_count}]
  """
  @behaviour L2E.Packet.Encodable

  @opcode 0xCB

  defstruct [:castle_id, clans: []]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{castle_id: castle_id, clans: clans}) do
    count = length(clans)

    clan_data =
      Enum.reduce(clans, <<>>, fn {clan_id, clan_name, ally_id, ally_name, _parties, members},
                                  acc ->
        acc <>
          <<clan_id::little-32>> <>
          utf16le_string(clan_name) <>
          <<ally_id::little-32>> <>
          utf16le_string(ally_name) <>
          <<0::little-32, members::little-32>>
      end)

    <<@opcode::8, castle_id::little-32, count::little-32, count::little-32>> <> clan_data
  end

  defp utf16le_string(str) do
    :unicode.characters_to_binary(str || "", :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

# ---- FASE 3: Duel packets (0xFE extended) ------------------------------------

defmodule L2E.Packet.Server.ExDuelAskStart do
  @moduledoc "0xFE/0x4B — duel request sent to target player."
  @behaviour L2E.Packet.Encodable

  defstruct [:requestor_name, :party_duel]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    name_bin = utf16le_string(p.requestor_name || "")
    party_duel = p.party_duel || 0

    <<0xFE::8, 0x4B::little-16>> <> name_bin <> <<party_duel::little-32>>
  end

  defp utf16le_string(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

defmodule L2E.Packet.Server.ExDuelReady do
  @moduledoc "0xFE/0x4C — signals that a duel is ready to start (party_duel: 1=party, 0=player)."
  @behaviour L2E.Packet.Encodable

  defstruct [:party_duel]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    party_duel_int = if p.party_duel, do: 1, else: 0

    <<0xFE::8, 0x4C::little-16, party_duel_int::little-32>>
  end
end

defmodule L2E.Packet.Server.ExDuelStart do
  @moduledoc "0xFE/0x4D — signals that a duel has started (party_duel: 1=party, 0=player)."
  @behaviour L2E.Packet.Encodable

  defstruct [:party_duel]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    party_duel_int = if p.party_duel, do: 1, else: 0

    <<0xFE::8, 0x4D::little-16, party_duel_int::little-32>>
  end
end

defmodule L2E.Packet.Server.ExDuelEnd do
  @moduledoc "0xFE/0x4E — signals that a duel has ended (party_duel: 1=party, 0=player)."
  @behaviour L2E.Packet.Encodable

  defstruct [:party_duel]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    party_duel_int = if p.party_duel, do: 1, else: 0

    <<0xFE::8, 0x4E::little-16, party_duel_int::little-32>>
  end
end

defmodule L2E.Packet.Server.ExDuelUpdateUserInfo do
  @moduledoc """
  0xFE/0x4F — Updates HP/CP display for duel participants.
  Sent to both players whenever one takes damage during a duel.
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:char_name, :hp, :max_hp, :cp, :max_cp]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{char_name: char_name, hp: hp, max_hp: max_hp, cp: cp, max_cp: max_cp}) do
    name_bytes = encode_utf16le(char_name || "")

    <<0xFE::8, 0x4F::little-16, byte_size(name_bytes) + 2::little-32, name_bytes::binary, 0, 0,
      trunc(hp || 0)::little-32, trunc(max_hp || 0)::little-32, trunc(cp || 0)::little-32,
      trunc(max_cp || 0)::little-32>>
  end

  defp encode_utf16le(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little})
  end
end

# ---- FASE 3: Olympiad Mode ---------------------------------------------------

defmodule L2E.Packet.Server.ExOlympiadMode do
  @moduledoc "0xFE/0x2B — sets the client's Olympiad UI mode (0=off/return, 3=spectate)."
  @behaviour L2E.Packet.Encodable

  defstruct [:mode]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    <<0xFE::8, 0x2B::little-16, p.mode || 0::8>>
  end
end

defmodule L2E.Packet.Server.SendMacroList do
  @moduledoc "0xCB — sends the character's macro list."
  @opcode 0xCB

  defstruct [:revision, :macros]

  def encode(%__MODULE__{revision: rev, macros: macros}) when is_list(macros) do
    count = length(macros)

    macro_bin =
      Enum.reduce(macros, <<>>, fn m, acc ->
        name_b = encode_utf16le(Map.get(m, :name, "") || "")
        descr_b = encode_utf16le(Map.get(m, :descr, "") || "")
        key_b = encode_utf16le(Map.get(m, :keybind, "") || "")
        icon = Map.get(m, :icon, 0) || 0
        mid = Map.get(m, :macro_id, 0) || 0
        acc <> <<mid::little-32>> <> name_b <> descr_b <> key_b <> <<icon::8, 0::8>>
      end)

    payload = <<rev::8, count::8>> <> macro_bin <> <<0::8>>
    <<byte_size(payload) + 2::little-16, @opcode::8>> <> payload
  end

  defp encode_utf16le(str) do
    chars = :unicode.characters_to_binary(str, :utf8, {:utf16, :little})
    len = div(byte_size(chars), 2)
    <<len::little-16>> <> chars
  end
end

# ---- M68-B: Sub-class packets -----------------------------------------------

defmodule L2E.Packet.Server.ExSubclassInfo do
  @moduledoc """
  0xFE/0x58 — sends the player's sub-class list and active index.

  Project-specific opcode (0x58 is unused in L2J Mobius CT0 ServerPackets enum;
  the last defined entry before this gap is EX_VARIATION_CANCEL_RESULT at 0x57).
  In CT0 Interlude, sub-class info is embedded in CharInfo/UserInfo; this packet
  provides a dedicated refresh path for the L2E Elixir server.

  Binary layout (little-endian):
    0xFE(8)  sub_opcode(16LE=0x0058)
    active_index(32LE)  count(32LE)
    for each sub-class:
      class_index(32LE)  class_id(32LE)
      exp(64LE)          sp(32LE)
      level(32LE)        is_max(8)

  `subclasses` is a list of maps with keys:
    class_index, class_id, exp, sp, level, is_max
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:active_index, subclasses: []]

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{active_index: active_index, subclasses: subclasses}) do
    count = length(subclasses)
    subs_bin = encode_subclasses(subclasses)

    <<0xFE::8, 0x0058::little-16, active_index || 0::little-32, count::little-32,
      subs_bin::binary>>
  end

  defp encode_subclasses(subclasses) do
    Enum.reduce(subclasses, <<>>, fn s, acc ->
      is_max = if Map.get(s, :is_max, false), do: 1, else: 0

      acc <>
        <<Map.get(s, :class_index, 0)::little-32, Map.get(s, :class_id, 0)::little-32,
          Map.get(s, :exp, 0)::little-64, Map.get(s, :sp, 0)::little-32,
          Map.get(s, :level, 40)::little-32, is_max::8>>
    end)
  end
end

# ---- M70-B: Olympiad Match Result (for Bishop) --------------------------------

defmodule L2E.Packet.Server.ExOlympiadMatchResult do
  @moduledoc """
  0xFE/0x59 — reports the winner and loser of an Olympiad match.

  Project-specific opcode (0x59 is unused in L2J Mobius CT0 ServerPackets enum).
  L2J Mobius CT0 has `ExOlympiadMatchEnd` (0xFE/0x2C) as a static no-payload signal;
  this packet carries the full winner/loser data for Bishop's `Olympiad.Match` GenServer.

  Binary layout (little-endian):
    0xFE(8)  sub_opcode(16LE=0x0059)
    winner_char_id(32LE)  winner_name(utf16le null-terminated)
    loser_char_id(32LE)   loser_name(utf16le null-terminated)
    draw(32LE=0)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:winner_char_id, :winner_name, :loser_char_id, :loser_name]

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{
        winner_char_id: winner_id,
        winner_name: winner_name,
        loser_char_id: loser_id,
        loser_name: loser_name
      }) do
    winner_name_bin = encode_utf16le(winner_name || "")
    loser_name_bin = encode_utf16le(loser_name || "")

    <<0xFE::8, 0x0059::little-16, winner_id || 0::little-32>> <>
      winner_name_bin <>
      <<loser_id || 0::little-32>> <>
      loser_name_bin <>
      <<0::little-32>>
  end

  defp encode_utf16le(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little}) <> <<0::16>>
  end
end

# ---------------------------------------------------------------------------
# M76: ExHeroList (0xFE/0x24) — sends the full hero list to the client.
# Sent on world entry and after each olympiad cycle.
#
# Binary layout (little-endian):
#   0xFE(8)  sub_opcode(16LE=0x0024)  count(32LE)
#   per hero: class_id(32LE)  name_byte_len+2(32LE)  name(utf16le)  null(16)  1(32LE)
# ---------------------------------------------------------------------------
defmodule L2E.Packet.Server.ExHeroList do
  @moduledoc """
  Packet 0xFE / 0x24 — Sends the full hero list to the client.
  Sent on world entry and after each olympiad cycle.
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:heroes]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{heroes: heroes}) do
    count = length(heroes)

    entries =
      Enum.map(heroes, fn h ->
        name_utf16 = encode_utf16le(Map.get(h, :char_name, ""))
        class_id = Map.get(h, :class_id, 0)

        <<class_id::little-32, byte_size(name_utf16) + 2::little-32, name_utf16::binary, 0, 0,
          1::little-32>>
      end)

    <<0xFE::8, 0x0024::little-16, count::little-32, IO.iodata_to_binary(entries)::binary>>
  end

  defp encode_utf16le(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little})
  end
end

# ---- M83: Command Channel (MPCC) packets ------------------------------------

defmodule L2E.Packet.Server.ExOpenMPCC do
  @moduledoc """
  0xFE/0x48 — Opens the Command Channel (MPCC) UI on the client.
  Sent to all party members when their party joins a CC.
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:cc_leader_name]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{cc_leader_name: name}) do
    name_utf16 = encode_utf16le(name || "")
    <<0xFE::8, 0x48::little-16, byte_size(name_utf16) + 2::little-32, name_utf16::binary, 0, 0>>
  end

  defp encode_utf16le(str) do
    :unicode.characters_to_binary(str, :utf8, {:utf16, :little})
  end
end

defmodule L2E.Packet.Server.ExCloseMPCC do
  @moduledoc "0xFE/0x49 — Closes the Command Channel UI on the client."
  @behaviour L2E.Packet.Encodable

  defstruct []

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{}) do
    <<0xFE::8, 0x49::little-16>>
  end
end

defmodule L2E.Packet.Server.ExMPCCPartyInfoUpdate do
  @moduledoc """
  0xFE/0x4A — Updates the party info display inside the CC UI.
  type: 0 = party joined, 1 = party left
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:char_id, :type]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{char_id: char_id, type: type}) do
    <<0xFE::8, 0x4A::little-16, char_id || 0::little-32, type || 0::little-32>>
  end
end

# ---- M86: Fishing packets (0xFE extended) ------------------------------------

defmodule L2E.Packet.Server.ExFishingStart do
  @moduledoc """
  0xFE/0x1F — Starts the fishing minigame UI on the client.
  Sent when the player casts their line and fishing begins.
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:char_id, :x, :y, :z]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{char_id: char_id, x: x, y: y, z: z}) do
    <<0xFE::8, 0x1F::little-16, char_id::little-32, x::little-32-signed, y::little-32-signed,
      z::little-32-signed>>
  end
end

defmodule L2E.Packet.Server.ExFishingEnd do
  @moduledoc """
  0xFE/0x22 — Ends the fishing minigame UI on the client.
  win: 0 = escaped or cancelled, 1 = fish caught.
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:char_id, :win]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{char_id: char_id, win: win}) do
    <<0xFE::8, 0x22::little-16, char_id::little-32, win::little-32>>
  end
end

defmodule L2E.Packet.Server.ExFishingHpRegen do
  @moduledoc """
  0xFE/0x21 — Updates the HP bar of the fish during the reel minigame.
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:char_id, :fish_hp, :fish_max_hp]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{char_id: char_id, fish_hp: fish_hp, fish_max_hp: fish_max_hp}) do
    <<0xFE::8, 0x21::little-16, char_id::little-32, fish_hp::little-32, fish_max_hp::little-32>>
  end
end

# -- M89: Community Board (BBS) -----------------------------------------------
defmodule L2E.Packet.Server.ShowBoard do
  @moduledoc """
  Opcode 0x7A -- sends a BBS HTML page to the client Community Board window.

  Binary layout (ShowBoard.java):
    opcode(8) + unknown1(32LE=1) + html(utf16le null-terminated string)

  Reference: ServerPackets.SHOW_BOARD(0x7A)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:html]
  @type t :: %__MODULE__{html: String.t()}

  @opcode 0x7A

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{html: html}) do
    html_bin = :unicode.characters_to_binary(html || "", :utf8, {:utf16, :little}) <> <<0::16>>
    <<@opcode::8, 1::little-32, html_bin::binary>>
  end
end

# ---- M97: Olympiad Registration Acknowledgment -------------------------------

defmodule L2E.Packet.Server.ExOlympiadRegistration do
  @moduledoc """
  0xFE/0x3C — confirms Olympiad registration status to the player.

  registered: true = registered, false = unregistered.
  player_count: total registered players in the current period.

  Binary layout (ExOlympiadMatchInfo.java / L2 CT0 Interlude):
    0xFE(8)  sub_opcode(16LE=0x003C)
    registered(32LE)  player_count(32LE)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:registered, :player_count]

  @type t :: %__MODULE__{registered: boolean(), player_count: non_neg_integer()}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{registered: registered, player_count: player_count}) do
    reg_int = if registered, do: 1, else: 0
    <<0xFE::8, 0x003C::little-16, reg_int::little-32, player_count || 0::little-32>>
  end
end

# ---- M101: Clan Wars UI -------------------------------------------------------

defmodule L2E.Packet.Server.PledgeReceiveWarList do
  @moduledoc """
  Opcode 0x85 — sends the list of active clan wars to the client on enter world.

  wars: list of {enemy_clan_id, enemy_clan_name, their_kills, my_kills, is_mutual}

  Binary layout (PledgeReceiveWarList.java):
    opcode(8) count(32LE) [enemy_id(32LE) enemy_name(utf16le) their_kills(32LE) my_kills(32LE) flags(32LE)]*

  Reference: ServerPackets.PLEDGE_RECEIVE_WAR_LIST(0x85)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:wars]
  @type t :: %__MODULE__{}

  @opcode 0x85

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{wars: wars}) do
    wars = wars || []
    count = length(wars)

    war_data =
      Enum.map_join(wars, "", fn {enemy_id, enemy_name, their_kills, my_kills, is_mutual} ->
        name_bin =
          :unicode.characters_to_binary(enemy_name || "", :utf8, {:utf16, :little}) <> <<0::16>>

        flags = if is_mutual, do: 1, else: 0

        <<enemy_id::little-32, name_bin::binary, their_kills::little-32, my_kills::little-32,
          flags::little-32>>
      end)

    <<@opcode::8, count::little-32, war_data::binary>>
  end
end

# ---- M102: Olympiad Arena UI -------------------------------------------------

defmodule L2E.Packet.Server.ExOlympiadUserInfo do
  @moduledoc """
  0xFE/0x3D — shows the opponent's HP/MP bar in the arena UI.

  side: 1 = blue (challenger), 2 = red (defender)

  Binary layout:
    0xFE(8)  sub_opcode(16LE=0x3D)
    char_id(32LE)  char_name(utf16le null-terminated)
    class_id(32LE)  cur_hp(32LE)  max_hp(32LE)
    cur_mp(32LE)  max_mp(32LE)  level(32LE)  side(32LE)
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:char_id, :char_name, :class_id, :cur_hp, :max_hp, :cur_mp, :max_mp, :level, :side]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    name_bytes =
      :unicode.characters_to_binary((p.char_name || "") <> "\0", :utf8, {:utf16, :little})

    cur_hp = trunc(p.cur_hp || 0)
    max_hp = trunc(p.max_hp || 1)
    cur_mp = trunc(p.cur_mp || 0)
    max_mp = trunc(p.max_mp || 1)

    <<0xFE::8, 0x3D::little-16, p.char_id::little-32, name_bytes::binary,
      p.class_id || 0::little-32, cur_hp::little-32, max_hp::little-32, cur_mp::little-32,
      max_mp::little-32, p.level || 1::little-32, p.side || 1::little-32>>
  end
end

defmodule L2E.Packet.Server.ExOlympiadSpelledInfo do
  @moduledoc """
  0xFE/0x3E — shows the opponent's active buffs in the arena UI.

  effects: list of {skill_id, skill_level, duration_ms} tuples.

  Binary layout:
    0xFE(8)  sub_opcode(16LE=0x3E)
    target_char_id(32LE)  count(32LE)
    [skill_id(32LE)  skill_level(32LE)  duration_ms(32LE)]*
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:target_char_id, :effects]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    effects = p.effects || []
    count = length(effects)

    effects_bin =
      Enum.map_join(effects, "", fn {skill_id, skill_level, duration_ms} ->
        <<skill_id::little-32, skill_level::little-32, duration_ms::little-32>>
      end)

    <<0xFE::8, 0x3E::little-16, p.target_char_id || 0::little-32, count::little-32,
      effects_bin::binary>>
  end
end
