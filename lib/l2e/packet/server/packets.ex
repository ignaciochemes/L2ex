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

    <<2::little-32, page_slot::little-32, id::little-32, 1::little-32,
      -1::little-32-signed, 0::little-32, 0::little-32, 0::little-16, 0::little-16>>
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
      p.follower_z::little-32-signed, p.target_x::little-32-signed,
      p.target_y::little-32-signed, p.target_z::little-32-signed>>
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

    <<@opcode::8, p.recipe_id::little-32, is_common::little-32,
      p.current_mp::little-32, p.max_mp::little-32, success::little-32>>
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

  defstruct [
    int_bonus: 0,
    str_bonus: 0,
    con_bonus: 0,
    men_bonus: 0,
    dex_bonus: 0,
    wit_bonus: 0,
    hennas: []
  ]

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

    <<@opcode::8,
      p.int_bonus::8-signed, p.str_bonus::8-signed, p.con_bonus::8-signed,
      p.men_bonus::8-signed, p.dex_bonus::8-signed, p.wit_bonus::8-signed,
      3::little-32, henna_count::little-32, henna_bytes::binary>>
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

  defstruct [stat12: 0, stat34: 0, result: 0]

  @type t :: %__MODULE__{}

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{} = p) do
    <<0xFE::8, 0x0055::little-16, p.stat12::little-32, p.stat34::little-32,
      p.result::little-32>>
  end
end
