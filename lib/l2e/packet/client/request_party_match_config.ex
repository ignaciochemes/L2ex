defmodule L2E.Packet.Client.RequestPartyMatchConfig do
  @moduledoc """
  Opcode 0x6F — RequestPartyMatchConfig.

  Sent when the client opens the Party Match window.

  Wire order (RequestPartyMatchConfig.java):
    _auto  = readInt()   1 = auto-recruit, 0 = manual
    _loc   = readInt()   Location code
    _level = readInt()   Player's current level
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:auto_flag, :loc_val, :level]

  @type t :: %__MODULE__{
          auto_flag: integer(),
          loc_val: integer(),
          level: integer()
        }

  @impl L2E.Packet.Decodable
  def decode(<<auto::little-32, loc::little-32, level::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{auto_flag: auto, loc_val: loc, level: level}}
  end

  def decode(_), do: {:error, :malformed}
end
