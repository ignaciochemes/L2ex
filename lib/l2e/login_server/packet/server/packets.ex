defmodule L2E.LoginServer.Packet.Server.Init do
  @moduledoc """
  Very first packet sent to a connecting client — UNENCRYPTED.
  Opcode 0x00 (login server).

  Binary layout (175 bytes body after the 2-byte LE length frame):
  ```
  0x00                       1 byte  opcode
  session_id                 4 bytes LE-32
  protocol_version           4 bytes LE-32  (0x0000C621)
  scrambled_rsa_modulus    128 bytes
  unk1                       4 bytes LE-32  (0x29DD954E)
  unk2                       4 bytes LE-32  (0x77C39CFC)
  unk3                       4 bytes LE-32  (0x97ADB620)
  unk4                       4 bytes LE-32  (0x07BDE0F7)
  blowfish_key              16 bytes
  0x00                       1 byte
  ```

  Reference: `Init.java`
  """
  @behaviour L2E.Packet.Encodable

  @protocol_version 0x0000C621
  @unk1 0x29DD954E
  @unk2 0x77C39CFC
  @unk3 0x97ADB620
  @unk4 0x07BDE0F7

  defstruct [:session_id, :scrambled_modulus, :blowfish_key]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{session_id: sid, scrambled_modulus: mod, blowfish_key: bf_key}) do
    <<
      0x00,
      sid::little-32,
      @protocol_version::little-32,
      mod::binary-size(128),
      @unk1::little-32,
      @unk2::little-32,
      @unk3::little-32,
      @unk4::little-32,
      bf_key::binary-size(16),
      0x00
    >>
  end
end

defmodule L2E.LoginServer.Packet.Server.LoginFail do
  @moduledoc """
  Opcode 0x01 — sent when authentication fails.
  Reason codes from `LoginFailReason.java`.
  Reference: `LoginFail.java`
  """
  @behaviour L2E.Packet.Encodable

  # Reason codes (subset)
  @reason_system_error 0x00
  @reason_invalid_password 0x02
  @reason_access_failed 0x04

  def reason_system_error, do: @reason_system_error
  def reason_invalid_password, do: @reason_invalid_password
  def reason_access_failed, do: @reason_access_failed

  defstruct [:reason]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{reason: reason}) do
    <<0x01, reason::8>>
  end
end

defmodule L2E.LoginServer.Packet.Server.LoginOk do
  @moduledoc """
  Opcode 0x03 — sent after successful RSA credential verification.
  Encrypted with STATIC Blowfish key + XOR-pass.
  Reference: `LoginOk.java`
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:login_ok1, :login_ok2]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{login_ok1: l1, login_ok2: l2}) do
    <<
      0x03,
      l1::little-32,
      l2::little-32,
      0::32,
      0::32,
      0x000003EA::little-32,
      0::32,
      0::32,
      0::32,
      0::128
    >>
  end
end

defmodule L2E.LoginServer.Packet.Server.ServerList do
  @moduledoc """
  Opcode 0x04 — list of available game servers.
  Encrypted with SESSION Blowfish key.
  Reference: `ServerList.java`

  For Milestone 2 we hardcode a single local server entry.
  """
  @behaviour L2E.Packet.Encodable

  # Single-server definition for M2
  @m2_servers [
    %{
      id: 1,
      ip: {127, 0, 0, 1},
      port: 7777,
      age_limit: 0,
      is_pvp: 1,
      online: 0,
      max_online: 100,
      is_up: 1,
      server_type: 0,
      show_brackets: 0
    }
  ]

  defstruct servers: @m2_servers, last_server: 1

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{servers: servers, last_server: last}) do
    header = <<0x04, length(servers)::8, last::8>>
    server_data = Enum.map_join(servers, &encode_server/1)
    header <> server_data
  end

  defp encode_server(%{
         id: id,
         ip: {a, b, c, d},
         port: port,
         age_limit: age,
         is_pvp: pvp,
         online: online,
         max_online: max,
         is_up: up,
         server_type: type,
         show_brackets: brackets
       }) do
    <<
      id::8,
      a::8,
      b::8,
      c::8,
      d::8,
      port::little-32,
      age::8,
      pvp::8,
      online::little-16,
      max::little-16,
      up::8,
      type::little-32,
      brackets::8
    >>
  end
end

defmodule L2E.LoginServer.Packet.Server.GGAuth do
  @moduledoc """
  Opcode 0x0B — server response to the client's `AuthGameGuard` (0x07).
  Echoes back the session ID. Encrypted with SESSION Blowfish key.
  Reference: `GGAuth.java`
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:session_id]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{session_id: sid}) do
    <<0x0B, sid::little-32, 0::32, 0::32, 0::32, 0::32>>
  end
end

defmodule L2E.LoginServer.Packet.Server.PlayOk do
  @moduledoc """
  Opcode 0x07 — grants access to the selected game server.
  Client forwards the play-ok pair to the game server in `AuthLogin`.
  Encrypted with SESSION Blowfish key.
  Reference: `PlayOk.java`
  """
  @behaviour L2E.Packet.Encodable

  defstruct [:play_ok1, :play_ok2]

  @impl L2E.Packet.Encodable
  def encode(%__MODULE__{play_ok1: p1, play_ok2: p2}) do
    <<0x07, p1::little-32, p2::little-32>>
  end
end
