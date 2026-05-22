defmodule L2E.Packet.Client.ProtocolVersion do
  @moduledoc "First packet sent by the game client. Contains the protocol version number."
  @behaviour L2E.Packet.Decodable

  defstruct [:version]
  @type t :: %__MODULE__{version: non_neg_integer() | nil}

  @spec decode(binary()) :: {:ok, t()} | {:error, :malformed}
  def decode(<<version::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{version: version}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.AuthLogin do
  @moduledoc """
  Opcode 0x08 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â sent by the game client after connecting to confirm the
  session established with the login server.

  Body (from AuthLogin.java):
    loginName   UTF-16LE null-terminated string
    play_ok2    LE-32
    play_ok1    LE-32
    login_ok1   LE-32
    login_ok2   LE-32
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:login_name, :play_ok1, :play_ok2, :login_ok1, :login_ok2]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(body) do
    case decode_utf16le_string(body) do
      {name,
       <<play_ok2::little-32, play_ok1::little-32, login_ok1::little-32, login_ok2::little-32,
         _::binary>>} ->
        {:ok,
         %__MODULE__{
           login_name: name,
           play_ok1: play_ok1,
           play_ok2: play_ok2,
           login_ok1: login_ok1,
           login_ok2: login_ok2
         }}

      _ ->
        {:error, :malformed}
    end
  end

  # Read a UTF-16LE null-terminated string from the head of a binary.
  # Returns {string, rest_of_binary} or :error.
  defp decode_utf16le_string(bin), do: do_utf16le(bin, [])

  defp do_utf16le(<<0, 0, rest::binary>>, acc) do
    chars = Enum.reverse(acc)
    str = chars |> Enum.map(&<<&1::utf8>>) |> Enum.join()
    {str, rest}
  end

  defp do_utf16le(<<cp::little-16, rest::binary>>, acc), do: do_utf16le(rest, [cp | acc])
  defp do_utf16le(_, _), do: :error
end

defmodule L2E.Packet.Client.EnterWorld do
  @moduledoc "Opcode 0x03 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â client confirms character selection and requests world entry."
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end

defmodule L2E.Packet.Client.CharacterSelect do
  @moduledoc "Opcode 0x0D ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â client selects a character slot on the character screen."
  @behaviour L2E.Packet.Decodable

  defstruct [:slot]
  @type t :: %__MODULE__{slot: non_neg_integer()}

  @impl L2E.Packet.Decodable
  def decode(
        <<slot::little-32, _unk1::little-16, _unk2::little-32, _unk3::little-32, _unk4::little-32,
          _::binary>>
      ) do
    {:ok, %__MODULE__{slot: slot}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.MoveToLocation do
  @moduledoc "Client is moving to a target position."
  @behaviour L2E.Packet.Decodable

  defstruct [:x, :y, :z, :origin_x, :origin_y, :origin_z]

  @type t :: %__MODULE__{
          x: integer() | nil,
          y: integer() | nil,
          z: integer() | nil,
          origin_x: integer() | nil,
          origin_y: integer() | nil,
          origin_z: integer() | nil
        }

  @spec decode(binary()) :: {:ok, t()} | {:error, :malformed}
  def decode(
        <<x::little-32-signed, y::little-32-signed, z::little-32-signed, ox::little-32-signed,
          oy::little-32-signed, oz::little-32-signed, _rest::binary>>
      ) do
    {:ok, %__MODULE__{x: x, y: y, z: z, origin_x: ox, origin_y: oy, origin_z: oz}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.ValidatePosition do
  @moduledoc "Client confirms its current position (anti-cheat sync)."
  @behaviour L2E.Packet.Decodable

  defstruct [:x, :y, :z, :heading]

  @type t :: %__MODULE__{
          x: integer() | nil,
          y: integer() | nil,
          z: integer() | nil,
          heading: non_neg_integer() | nil
        }

  @spec decode(binary()) :: {:ok, t()} | {:error, :malformed}
  def decode(
        <<x::little-32-signed, y::little-32-signed, z::little-32-signed, heading::little-32,
          _rest::binary>>
      ) do
    {:ok, %__MODULE__{x: x, y: y, z: z, heading: heading}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.NewCharacter do
  @moduledoc "Opcode 0x0E ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â client requests the character template list for the creation screen."
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end

defmodule L2E.Packet.Client.CharacterCreate do
  @moduledoc """
  Opcode 0x0B ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â client submits a new character creation request.

  Body (CharacterCreate.java): name(string) race(int) sex(int) class_id(int)
    int_s(int) str_s(int) con_s(int) men_s(int) dex_s(int) wit_s(int)
    hair_style(int) hair_color(int) face(int)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:name, :race, :sex, :class_id, :hair_style, :hair_color, :face]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(body) do
    case decode_utf16le_string(body) do
      {name,
       <<race::little-32, sex::little-32, class_id::little-32, _int_s::little-32,
         _str_s::little-32, _con_s::little-32, _men_s::little-32, _dex_s::little-32,
         _wit_s::little-32, hair_style::little-32, hair_color::little-32, face::little-32,
         _::binary>>} ->
        {:ok,
         %__MODULE__{
           name: name,
           race: race,
           sex: sex,
           class_id: class_id,
           hair_style: hair_style,
           hair_color: hair_color,
           face: face
         }}

      _ ->
        {:error, :malformed}
    end
  end

  defp decode_utf16le_string(bin), do: do_utf16le(bin, [])

  defp do_utf16le(<<0, 0, rest::binary>>, acc) do
    str = acc |> Enum.reverse() |> Enum.map_join(&<<&1::utf8>>)
    {str, rest}
  end

  defp do_utf16le(<<cp::little-16, rest::binary>>, acc), do: do_utf16le(rest, [cp | acc])
  defp do_utf16le(_, _), do: :error
end

defmodule L2E.Packet.Client.CharacterDelete do
  @moduledoc "Opcode 0x0C ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â client requests deletion of a character in the given slot."
  @behaviour L2E.Packet.Decodable

  defstruct [:slot]
  @type t :: %__MODULE__{slot: non_neg_integer()}

  @impl L2E.Packet.Decodable
  def decode(<<slot::little-32, _::binary>>) do
    {:ok, %__MODULE__{slot: slot}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.Action do
  @moduledoc """
  Opcode 0x04 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player clicks on an object.

  action_id 0 = normal interaction / target selection
  action_id 1 = shift-click (force-attack)

  Body (Action.java): obj_id(int) x(int) y(int) z(int) action_id(byte)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:object_id, :x, :y, :z, :action_id]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(
        <<obj_id::little-32, x::little-32-signed, y::little-32-signed, z::little-32-signed,
          action_id::8, _::binary>>
      ) do
    {:ok, %__MODULE__{object_id: obj_id, x: x, y: y, z: z, action_id: action_id}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.AttackRequest do
  @moduledoc """
  Opcode 0x0A ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â direct attack request on a target.

  Body (AttackRequest.java): obj_id(int) x(int) y(int) z(int) attack_id(byte)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:object_id, :x, :y, :z, :attack_id]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(
        <<obj_id::little-32, x::little-32-signed, y::little-32-signed, z::little-32-signed,
          attack_id::8, _::binary>>
      ) do
    {:ok, %__MODULE__{object_id: obj_id, x: x, y: y, z: z, attack_id: attack_id}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.RequestTargetCanceld do
  @moduledoc "Opcode 0x37 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player cancels their current target."
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end

defmodule L2E.Packet.Client.UseItem do
  @moduledoc """
  Opcode 0x19 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player activates an item (equip weapon/armor, consume potion).

  Body: obj_id(32) ctrl(32)
  `ctrl` is 0 for normal use, 1 for ctrl-click (forced action).

  Reference: UseItem.java
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:object_id, :ctrl]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<object_id::little-32, ctrl::little-32, _::binary>>) do
    {:ok, %__MODULE__{object_id: object_id, ctrl: ctrl}}
  end

  def decode(<<object_id::little-32>>) do
    {:ok, %__MODULE__{object_id: object_id, ctrl: 0}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.RequestPickUpItem do
  @moduledoc """
  Opcode 0x16 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player attempts to pick up a ground item.

  Body: object_id(32)

  Reference: RequestPickUpItem.java
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:object_id]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<object_id::little-32, _::binary>>) do
    {:ok, %__MODULE__{object_id: object_id}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.RequestMagicSkillUse do
  @moduledoc """
  Opcode 0x2F ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player activates a skill from their skill bar.

  Body (RequestMagicSkillUse.java):
    skill_id     LE-32  ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â the skill to cast
    ctrl_pressed LE-32  ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â non-zero if Ctrl was held (force-attack in peace zones)
    shift_key    byte   ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â non-zero if Shift was held (cast without movement)

  Reference: ClientPackets.java REQUEST_MAGIC_SKILL_USE(0x2F)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:skill_id, :ctrl_pressed, :shift_pressed]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<skill_id::little-32, ctrl::little-32, shift::8, _::binary>>) do
    {:ok, %__MODULE__{skill_id: skill_id, ctrl_pressed: ctrl != 0, shift_pressed: shift != 0}}
  end

  def decode(<<skill_id::little-32, ctrl::little-32>>) do
    {:ok, %__MODULE__{skill_id: skill_id, ctrl_pressed: ctrl != 0, shift_pressed: false}}
  end

  def decode(<<skill_id::little-32>>) do
    {:ok, %__MODULE__{skill_id: skill_id, ctrl_pressed: false, shift_pressed: false}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.RequestSkillList do
  @moduledoc """
  Opcode 0x3F ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â client requests a refresh of the skill list window.

  Body: empty.

  Reference: ClientPackets.java REQUEST_SKILL_LIST(0x3F)
  """
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end

# ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ M16: NPC Interaction ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬

defmodule L2E.Packet.Client.RequestBypassToServer do
  @moduledoc """
  Opcode 0x21 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â client-side NPC dialog action (bypass command).

  Sent when the player clicks a link inside an NPC HTML dialog.
  The bypass string is the "href" value from the HTML, e.g.
  "_bbshome" or "npc_%objectId%_Buy".

  Body (RequestBypassToServer.java): bypass_string(string)

  Reference: ClientPackets.java REQUEST_BYPASS_TO_SERVER(0x21)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:command]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(body) do
    case decode_utf16le(body) do
      {cmd, _rest} -> {:ok, %__MODULE__{command: cmd}}
      _ -> {:error, :malformed}
    end
  end

  defp decode_utf16le(bin), do: do_utf16(bin, [])

  defp do_utf16(<<0, 0, rest::binary>>, acc),
    do: {acc |> Enum.reverse() |> Enum.map_join(&<<&1::utf8>>), rest}

  defp do_utf16(<<cp::little-16, rest::binary>>, acc), do: do_utf16(rest, [cp | acc])
  defp do_utf16(_, _), do: :error
end

defmodule L2E.Packet.Client.RequestBuyItem do
  @moduledoc """
  Opcode 0x1F ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â client buys items from a merchant NPC.

  Body (RequestBuyItem.java):
    npc_object_id(32) count(16) + per item: item_id(32) count(64)

  Reference: ClientPackets.java REQUEST_BUY_ITEM(0x1F)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:npc_object_id, items: []]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<npc_id::little-32, count::little-16, rest::binary>>) do
    items = parse_items(rest, count, [])
    {:ok, %__MODULE__{npc_object_id: npc_id, items: items}}
  end

  def decode(_), do: {:error, :malformed}

  defp parse_items(_, 0, acc), do: Enum.reverse(acc)

  defp parse_items(<<item_id::little-32, count::little-64, rest::binary>>, n, acc) do
    parse_items(rest, n - 1, [{item_id, count} | acc])
  end

  defp parse_items(_, _, acc), do: Enum.reverse(acc)
end

defmodule L2E.Packet.Client.RequestSellItem do
  @moduledoc """
  Opcode 0x1E ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â client sells items to a merchant NPC.

  Body (RequestSellItem.java):
    npc_object_id(32) count(16) + per item: obj_id(32) item_id(32) count(64)

  Reference: ClientPackets.java REQUEST_SELL_ITEM(0x1E)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:npc_object_id, items: []]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<npc_id::little-32, count::little-16, rest::binary>>) do
    items = parse_items(rest, count, [])
    {:ok, %__MODULE__{npc_object_id: npc_id, items: items}}
  end

  def decode(_), do: {:error, :malformed}

  defp parse_items(_, 0, acc), do: Enum.reverse(acc)

  defp parse_items(
         <<obj_id::little-32, item_id::little-32, count::little-64, rest::binary>>,
         n,
         acc
       ) do
    parse_items(rest, n - 1, [{obj_id, item_id, count} | acc])
  end

  defp parse_items(_, _, acc), do: Enum.reverse(acc)
end

# ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ M17: Chat ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬

defmodule L2E.Packet.Client.Say2 do
  @moduledoc """
  Opcode 0x38 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player sends a chat message.

  chat_type:
    0 = SAY (normal, nearby)    1 = SHOUT (wider area)
    2 = TELL (whisper)          3 = PARTY
    4 = CLAN                    8 = TRADE
    12 = HERO                  17 = ALL_WORLD

  Body (Say2.java): text(string) chat_type(32) [target_name(string) if whisper]

  Reference: ClientPackets.java SAY2(0x38)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:message, :chat_type, :target_name]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(body) do
    case decode_utf16le(body) do
      {message, <<chat_type::little-32, rest::binary>>} ->
        target =
          if chat_type == 2 do
            case decode_utf16le(rest) do
              {name, _} -> name
              _ -> nil
            end
          else
            nil
          end

        {:ok, %__MODULE__{message: message, chat_type: chat_type, target_name: target}}

      _ ->
        {:error, :malformed}
    end
  end

  defp decode_utf16le(bin), do: do_utf16(bin, [])

  defp do_utf16(<<0, 0, rest::binary>>, acc),
    do: {acc |> Enum.reverse() |> Enum.map_join(&<<&1::utf8>>), rest}

  defp do_utf16(<<cp::little-16, rest::binary>>, acc), do: do_utf16(rest, [cp | acc])
  defp do_utf16(_, _), do: :error
end

# ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ M21: Party ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬

defmodule L2E.Packet.Client.RequestJoinParty do
  @moduledoc """
  Opcode 0x29 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player invites another player to a party.

  Body (RequestJoinParty.java): target_name(string) distribution_type(32)

  distribution_type:
    1 = RANDOM    2 = RANDOM_SPOIL    3 = BY_TURN
    4 = BY_TURN_SPOIL    5 = FINDERS_KEEPERS

  Reference: ClientPackets.java REQUEST_JOIN_PARTY(0x29)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:target_name, :distribution_type]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(body) do
    case decode_utf16le(body) do
      {name, <<dist::little-32, _::binary>>} ->
        {:ok, %__MODULE__{target_name: name, distribution_type: dist}}

      {name, <<>>} ->
        {:ok, %__MODULE__{target_name: name, distribution_type: 1}}

      _ ->
        {:error, :malformed}
    end
  end

  defp decode_utf16le(bin), do: do_utf16(bin, [])

  defp do_utf16(<<0, 0, rest::binary>>, acc),
    do: {acc |> Enum.reverse() |> Enum.map_join(&<<&1::utf8>>), rest}

  defp do_utf16(<<cp::little-16, rest::binary>>, acc), do: do_utf16(rest, [cp | acc])
  defp do_utf16(_, _), do: :error
end

defmodule L2E.Packet.Client.RequestAnswerJoinParty do
  @moduledoc """
  Opcode 0x2A ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player accepts or refuses a party invitation.

  Body (RequestAnswerJoinParty.java): response(32) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â 1=accept, 0=refuse

  Reference: ClientPackets.java REQUEST_ANSWER_JOIN_PARTY(0x2A)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:response]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<response::little-32, _::binary>>) do
    {:ok, %__MODULE__{response: response}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.RequestWithDrawalParty do
  @moduledoc """
  Opcode 0x2B ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player leaves the party voluntarily.

  Body: empty.

  Reference: ClientPackets.java REQUEST_WITH_DRAWAL_PARTY(0x2B)
  """
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_), do: {:ok, %__MODULE__{}}
end

defmodule L2E.Packet.Client.RequestOustPartyMember do
  @moduledoc """
  Opcode 0x2C ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â party leader kicks a member.

  Body (RequestOustPartyMember.java): target_name(string)

  Reference: ClientPackets.java REQUEST_OUST_PARTY_MEMBER(0x2C)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:target_name]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(body) do
    case decode_utf16le(body) do
      {name, _} -> {:ok, %__MODULE__{target_name: name}}
      _ -> {:error, :malformed}
    end
  end

  defp decode_utf16le(bin), do: do_utf16(bin, [])

  defp do_utf16(<<0, 0, rest::binary>>, acc),
    do: {acc |> Enum.reverse() |> Enum.map_join(&<<&1::utf8>>), rest}

  defp do_utf16(<<cp::little-16, rest::binary>>, acc), do: do_utf16(rest, [cp | acc])
  defp do_utf16(_, _), do: :error
end

# ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ M22: Clans ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬

defmodule L2E.Packet.Client.RequestJoinPledge do
  @moduledoc """
  Opcode 0x24 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â clan leader invites a player to the clan.

  Body (RequestJoinPledge.java): target_id(32) pledge_type(32)

  Reference: ClientPackets.java REQUEST_JOIN_PLEDGE(0x24)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:target_id, :pledge_type]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<target_id::little-32, pledge_type::little-32, _::binary>>) do
    {:ok, %__MODULE__{target_id: target_id, pledge_type: pledge_type}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.RequestAnswerJoinPledge do
  @moduledoc """
  Opcode 0x25 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player accepts or refuses a clan invitation.

  Body (RequestAnswerJoinPledge.java): response(32) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â 1=accept, 0=refuse

  Reference: ClientPackets.java REQUEST_ANSWER_JOIN_PLEDGE(0x25)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:response]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<response::little-32, _::binary>>) do
    {:ok, %__MODULE__{response: response}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.RequestWithdrawalPledge do
  @moduledoc """
  Opcode 0x26 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player leaves the clan voluntarily.

  Body: empty.

  Reference: ClientPackets.java REQUEST_WITHDRAWAL_PLEDGE(0x26)
  """
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_), do: {:ok, %__MODULE__{}}
end

defmodule L2E.Packet.Client.RequestOustPledgeMember do
  @moduledoc """
  Opcode 0x27 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â clan leader kicks a member.

  Body (RequestOustPledgeMember.java): target_name(string)

  Reference: ClientPackets.java REQUEST_OUST_PLEDGE_MEMBER(0x27)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:target_name]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(body) do
    case decode_utf16le(body) do
      {name, _} -> {:ok, %__MODULE__{target_name: name}}
      _ -> {:error, :malformed}
    end
  end

  defp decode_utf16le(bin), do: do_utf16(bin, [])

  defp do_utf16(<<0, 0, rest::binary>>, acc),
    do: {acc |> Enum.reverse() |> Enum.map_join(&<<&1::utf8>>), rest}

  defp do_utf16(<<cp::little-16, rest::binary>>, acc), do: do_utf16(rest, [cp | acc])
  defp do_utf16(_, _), do: :error
end

defmodule L2E.Packet.Client.RequestTeleportToLocation do
  @moduledoc """
  Opcode 0x1F ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player confirms a teleport from an NPC dialog.

  Body (RequestTeleportToLocation.java):
    target_id(32) x(32) y(32) z(32)

  Reference: ClientPackets.java REQUEST_TELEPORT_TO_LOCATION(0x1F)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:target_id, :x, :y, :z]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(
        <<target_id::little-32-signed, x::little-32-signed, y::little-32-signed,
          z::little-32-signed, _rest::binary>>
      ) do
    {:ok, %__MODULE__{target_id: target_id, x: x, y: y, z: z}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.RequestWarehouseWithdraw do
  @moduledoc """
  Opcode 0x32 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player withdraws one or more items from their private warehouse.

  Body (RequestWarehouseWithdraw.java):
    count(16) + per item: object_id(32) count(64)

  Reference: ClientPackets.java REQUEST_WARE_HOUSE_WITHDRAW_ITEM(0x32)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:items]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<count::little-16, rest::binary>>) do
    case decode_items(rest, count, []) do
      {:ok, items} -> {:ok, %__MODULE__{items: items}}
      :error -> {:error, :malformed}
    end
  end

  def decode(_), do: {:error, :malformed}

  defp decode_items(_, 0, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_items(<<obj_id::little-32, qty::little-64, rest::binary>>, n, acc) do
    decode_items(rest, n - 1, [%{object_id: obj_id, count: qty} | acc])
  end

  defp decode_items(_, _, _), do: :error
end

defmodule L2E.Packet.Client.RequestWarehouseDeposit do
  @moduledoc """
  Opcode 0x33 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player deposits one or more items into their private warehouse.

  Body (RequestWarehouseDeposit.java):
    count(16) + per item: object_id(32) count(64)

  Reference: ClientPackets.java REQUEST_WARE_HOUSE_DEPOSIT_ITEM(0x33)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:items]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<count::little-16, rest::binary>>) do
    case decode_deposit_items(rest, count, []) do
      {:ok, items} -> {:ok, %__MODULE__{items: items}}
      :error -> {:error, :malformed}
    end
  end

  def decode(_), do: {:error, :malformed}

  defp decode_deposit_items(_, 0, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_deposit_items(<<obj_id::little-32, qty::little-64, rest::binary>>, n, acc) do
    decode_deposit_items(rest, n - 1, [%{object_id: obj_id, count: qty} | acc])
  end

  defp decode_deposit_items(_, _, _), do: :error
end

defmodule L2E.Packet.Client.TradeRequest do
  @moduledoc """
  Opcode 0x15 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player initiates a trade with a target.

  Body (TradeRequest.java): target_object_id(32)

  Reference: ClientPackets.TRADE_REQUEST(0x15)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:target_object_id]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<target_id::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{target_object_id: target_id}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.AddTradeItem do
  @moduledoc """
  Opcode 0x16 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player adds items to their trade offer.

  Body (AddTradeItem.java): count(16) + per item: object_id(32) count(64)

  Reference: ClientPackets.ADD_TRADE_ITEM(0x16)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:items]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<count::little-16, rest::binary>>) do
    case decode_trade_items(rest, count, []) do
      {:ok, items} -> {:ok, %__MODULE__{items: items}}
      :error -> {:error, :malformed}
    end
  end

  def decode(_), do: {:error, :malformed}

  defp decode_trade_items(_, 0, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_trade_items(<<obj_id::little-32, qty::little-64, rest::binary>>, n, acc) do
    decode_trade_items(rest, n - 1, [%{object_id: obj_id, count: qty} | acc])
  end

  defp decode_trade_items(_, _, _), do: :error
end

defmodule L2E.Packet.Client.TradeDone do
  @moduledoc """
  Opcode 0x17 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â player confirms or cancels the trade.

  Body (TradeDone.java): response(32) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â 1=confirm, 0=cancel

  Reference: ClientPackets.TRADE_DONE(0x17)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:response]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<response::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{response: response}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.AnswerTradeRequest do
  @moduledoc """
  Opcode 0x44 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â target player accepts or rejects the trade invite.

  Body (AnswerTradeRequest.java): response(32) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â 1=accept, 0=decline

  Reference: ClientPackets.ANSWER_TRADE_REQUEST(0x44)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:response]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<response::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{response: response}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.RequestEnchantItem do
  @behaviour L2E.Packet.Decodable

  defstruct [:object_id]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<object_id::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{object_id: object_id}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.RequestDestroyItem do
  @moduledoc "0x59 Ã¢â‚¬â€ request to destroy an item from inventory."
  @behaviour L2E.Packet.Decodable

  defstruct [:object_id, :count]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<object_id::little-32, count::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{object_id: object_id, count: count}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.RequestDropItem do
  @moduledoc "0x12 Ã¢â‚¬â€ request to drop an item to the ground."
  @behaviour L2E.Packet.Decodable

  defstruct [:object_id, :count, :x, :y, :z]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(
        <<object_id::little-32, count::little-32, x::little-32-signed, y::little-32-signed,
          z::little-32-signed, _rest::binary>>
      ) do
    {:ok, %__MODULE__{object_id: object_id, count: count, x: x, y: y, z: z}}
  end

  def decode(_), do: {:error, :malformed}
end

# M39 Ã¢â‚¬â€ Soulshot / Spiritshot auto-use toggle (extended opcode 0xD0/0x05)
defmodule L2E.Packet.Client.RequestAutoSoulShot do
  @moduledoc "0xD0/0x05 Ã¢â‚¬â€ toggle auto soulshot/spiritshot for an item. type: 1=on, 0=off."
  @behaviour L2E.Packet.Decodable

  defstruct [:item_id, :type]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<item_id::little-32, type::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{item_id: item_id, type: type}}
  end

  def decode(_), do: {:error, :malformed}
end

# M35 Ã¢â‚¬â€ Private store management
defmodule L2E.Packet.Client.RequestPrivateStoreManageSell do
  @moduledoc "0x73 Ã¢â‚¬â€ player opens the sell store management interface."
  @behaviour L2E.Packet.Decodable

  defstruct []

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end

defmodule L2E.Packet.Client.SetPrivateStoreListSell do
  @moduledoc "0x74 Ã¢â‚¬â€ player submits their sell store item list. Each item: object_id, count, price."
  @behaviour L2E.Packet.Decodable

  defstruct [:is_package, :items]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<is_package::little-32, count::little-32, rest::binary>>) do
    {:ok, %__MODULE__{is_package: is_package, items: decode_items(count, rest, [])}}
  end

  def decode(_), do: {:error, :malformed}

  defp decode_items(0, _bin, acc), do: Enum.reverse(acc)

  defp decode_items(
         n,
         <<obj_id::little-32, count::little-32, price::little-32, rest::binary>>,
         acc
       ) do
    decode_items(n - 1, rest, [%{object_id: obj_id, count: count, price: price} | acc])
  end

  defp decode_items(_, _, acc), do: Enum.reverse(acc)
end

defmodule L2E.Packet.Client.RequestPrivateStoreQuitSell do
  @moduledoc "0x76 Ã¢â‚¬â€ player closes their sell store."
  @behaviour L2E.Packet.Decodable

  defstruct []

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end

defmodule L2E.Packet.Client.SetPrivateStoreMsgSell do
  @moduledoc "0x77 Ã¢â‚¬â€ player sets the title message for their sell store."
  @behaviour L2E.Packet.Decodable

  defstruct [:title]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(body) do
    # UTF-16LE null-terminated string
    case body do
      <<>> ->
        {:ok, %__MODULE__{title: ""}}

      bin ->
        title = decode_utf16_string(bin)
        {:ok, %__MODULE__{title: title}}
    end
  end

  defp decode_utf16_string(bin) do
    chars = for <<a::8, b::8 <- bin>>, into: [], do: <<a::8, b::8>>

    chars
    |> Enum.take_while(&(&1 != <<0, 0>>))
    |> Enum.map(fn <<a, b>> -> :unicode.characters_to_binary(<<a, b>>, {:utf16, :little}) end)
    |> Enum.join()
  end
end

defmodule L2E.Packet.Client.RequestPrivateStoreBuy do
  @moduledoc "0x79 Ã¢â‚¬â€ buyer purchases items from a player sell store. Each item: object_id, count, price."
  @behaviour L2E.Packet.Decodable

  defstruct [:seller_id, :items]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<seller_id::little-32, count::little-32, rest::binary>>) do
    {:ok, %__MODULE__{seller_id: seller_id, items: decode_items(count, rest, [])}}
  end

  def decode(_), do: {:error, :malformed}

  defp decode_items(0, _bin, acc), do: Enum.reverse(acc)

  defp decode_items(
         n,
         <<obj_id::little-32, count::little-32, price::little-32, rest::binary>>,
         acc
       ) do
    decode_items(n - 1, rest, [%{object_id: obj_id, count: count, price: price} | acc])
  end

  defp decode_items(_, _, acc), do: Enum.reverse(acc)
end

# M43 Ã¢â‚¬â€ Private store buy
defmodule L2E.Packet.Client.RequestPrivateStoreManageBuy do
  @moduledoc """
  Opcode 0x90 Ã¢â‚¬â€ player opens the buy store management interface.

  Body (RequestPrivateStoreManageBuy.java): empty Ã¢â‚¬â€ no readImpl body.

  Reference: ClientPackets.REQUEST_PRIVATE_STORE_MANAGE_BUY(0x90)
  """
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end

defmodule L2E.Packet.Client.SetPrivateStoreListBuy do
  @moduledoc """
  Opcode 0x91 Ã¢â‚¬â€ player confirms their buy-store wish list.

  Body (SetPrivateStoreListBuy.java):
    count(32)
    per item (16 bytes each):
      item_id(32)  enchant(16)  unk(16)  count(32)  price(32)

  Reference: ClientPackets.SET_PRIVATE_STORE_LIST_BUY(0x91)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:items]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<count::little-32, rest::binary>>) do
    {:ok, %__MODULE__{items: decode_items(count, rest, [])}}
  end

  def decode(_), do: {:error, :malformed}

  defp decode_items(0, _bin, acc), do: Enum.reverse(acc)

  defp decode_items(
         n,
         <<item_id::little-32, enchant::little-16, _unk::little-16, count::little-32,
           price::little-32, rest::binary>>,
         acc
       ) do
    decode_items(n - 1, rest, [
      %{item_id: item_id, enchant: enchant, count: count, price: price} | acc
    ])
  end

  defp decode_items(_, _, acc), do: Enum.reverse(acc)
end

defmodule L2E.Packet.Client.RequestPrivateStoreSell do
  @moduledoc """
  Opcode 0x96 Ã¢â‚¬â€ a player sells items to a buy-store owner.

  Body (RequestPrivateStoreSell.java):
    store_player_id(32)  count(32)
    per item (20 bytes each):
      object_id(32)  item_id(32)  unk1(16)  unk2(16)  count(32)  price(32)

  Reference: ClientPackets.REQUEST_PRIVATE_STORE_SELL(0x96)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:owner_obj_id, :items]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(<<owner_obj_id::little-32, count::little-32, rest::binary>>) do
    {:ok, %__MODULE__{owner_obj_id: owner_obj_id, items: decode_items(count, rest, [])}}
  end

  def decode(_), do: {:error, :malformed}

  defp decode_items(0, _bin, acc), do: Enum.reverse(acc)

  defp decode_items(
         n,
         <<object_id::little-32, item_id::little-32, _unk1::little-16, _unk2::little-16,
           count::little-32, price::little-32, rest::binary>>,
         acc
       ) do
    decode_items(n - 1, rest, [
      %{object_id: object_id, item_id: item_id, count: count, price: price} | acc
    ])
  end

  defp decode_items(_, _, acc), do: Enum.reverse(acc)
end

defmodule L2E.Packet.Client.RequestPrivateStoreQuitBuy do
  @moduledoc """
  Opcode 0x8D â€” player closes their buy store.

  Body (RequestPrivateStoreQuitBuy.java): empty.

  Reference: ClientPackets.REQUEST_PRIVATE_STORE_QUIT_BUY(0x8D)
  """
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end

# M44 Ã¢â‚¬â€ Skill tree + learn
defmodule L2E.Packet.Client.RequestAcquireSkillInfo do
  @moduledoc """
  Opcode 0x6B Ã¢â‚¬â€ player hovers over a skill in the skill tree UI (tooltip request).

  Body (RequestAcquireSkillInfo.java):
    skill_id(32)  skill_level(32)  acquire_type(32)

  acquire_type ordinal: 0=CLASS, 1=FISHING, 2=PLEDGE

  Reference: ClientPackets.REQUEST_ACQUIRE_SKILL_INFO(0x6B)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:skill_id, :skill_level, :acquire_type]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(
        <<skill_id::little-32, skill_level::little-32, acquire_type::little-32, _rest::binary>>
      ) do
    {:ok, %__MODULE__{skill_id: skill_id, skill_level: skill_level, acquire_type: acquire_type}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.RequestAcquireSkill do
  @moduledoc """
  Opcode 0x6C Ã¢â‚¬â€ player clicks to learn a skill.

  Body (RequestAcquireSkill.java):
    skill_id(32)  skill_level(32)  acquire_type(32)

  acquire_type ordinal: 0=CLASS, 1=FISHING, 2=PLEDGE

  Reference: ClientPackets.REQUEST_ACQUIRE_SKILL(0x6C)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:skill_id, :skill_level, :acquire_type]
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(
        <<skill_id::little-32, skill_level::little-32, acquire_type::little-32, _rest::binary>>
      ) do
    {:ok, %__MODULE__{skill_id: skill_id, skill_level: skill_level, acquire_type: acquire_type}}
  end

  def decode(_), do: {:error, :malformed}
end

defmodule L2E.Packet.Client.RequestGotoLobby do
  @moduledoc """
  Opcode 0xBA -- player requests to return to character selection screen.

  Body: empty (no payload).

  Reference: ClientPackets.REQUEST_GOTO_LOBBY(0xBA)
  """
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end
