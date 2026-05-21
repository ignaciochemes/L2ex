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
  Opcode 0x08 — sent by the game client after connecting to confirm the
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
  @moduledoc "Opcode 0x03 — client confirms character selection and requests world entry."
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end

defmodule L2E.Packet.Client.CharacterSelect do
  @moduledoc "Opcode 0x0D — client selects a character slot on the character screen."
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
  @moduledoc "Opcode 0x0E — client requests the character template list for the creation screen."
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end

defmodule L2E.Packet.Client.CharacterCreate do
  @moduledoc """
  Opcode 0x0B — client submits a new character creation request.

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
  @moduledoc "Opcode 0x0C — client requests deletion of a character in the given slot."
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
  Opcode 0x04 — player clicks on an object.

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
  Opcode 0x0A — direct attack request on a target.

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
  @moduledoc "Opcode 0x37 — player cancels their current target."
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end

defmodule L2E.Packet.Client.UseItem do
  @moduledoc """
  Opcode 0x19 — player activates an item (equip weapon/armor, consume potion).

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
  Opcode 0x16 — player attempts to pick up a ground item.

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
  Opcode 0x2F — player activates a skill from their skill bar.

  Body (RequestMagicSkillUse.java):
    skill_id     LE-32  — the skill to cast
    ctrl_pressed LE-32  — non-zero if Ctrl was held (force-attack in peace zones)
    shift_key    byte   — non-zero if Shift was held (cast without movement)

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
  Opcode 0x3F — client requests a refresh of the skill list window.

  Body: empty.

  Reference: ClientPackets.java REQUEST_SKILL_LIST(0x3F)
  """
  @behaviour L2E.Packet.Decodable

  defstruct []
  @type t :: %__MODULE__{}

  @impl L2E.Packet.Decodable
  def decode(_body), do: {:ok, %__MODULE__{}}
end
