defmodule L2E.Packet.Client.ChangeWaitType2 do
  @moduledoc """
  Opcode 0x1D — sent by client when the player changes their wait/idle state
  (sit, stand, fake death).

  Body (ChangeWaitType2.java):
    move_type  LE-32   0 = sitting, 1 = standing, 2 = start fake death,
                        3 = stop fake death

  Reference: ChangeWaitType2.java — CHANGE_WAIT_TYPE2(0x1D, ...)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:move_type]

  @type t :: %__MODULE__{
          move_type: 0 | 1 | 2 | 3
        }

  @impl L2E.Packet.Decodable
  def decode(<<move_type::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{move_type: move_type}}
  end

  def decode(_), do: {:error, :malformed}
end
