defmodule L2E.Packet.Client.ChangeMoveType2 do
  @moduledoc """
  Opcode 0x1C — sent by client when the player toggles walk/run mode.

  Body (ChangeMoveType2.java):
    move_type  LE-32   0 = walk, 1 = run

  Reference: ChangeMoveType2.java — CHANGE_MOVE_TYPE2(0x1C, ...)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:move_type]

  @type t :: %__MODULE__{
          move_type: 0 | 1
        }

  @impl L2E.Packet.Decodable
  def decode(<<move_type::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{move_type: move_type}}
  end

  def decode(_), do: {:error, :malformed}
end
