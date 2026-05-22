defmodule L2E.Packet.Client.RequestActionUse do
  @moduledoc """
  Opcode 0x45 — client activates a slot on the action bar.

  Body (RequestActionUse.java):
    action_id    LE-32
    ctrl_pressed LE-32  (1 = ctrl held)
    shift_byte   8-bit  (1 = shift held)

  Action IDs (relevant subset):
    0  = Attack
    2  = Sit/Stand toggle
    10 = Pickup nearest item
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:action_id, :ctrl_pressed]

  @type t :: %__MODULE__{
          action_id: non_neg_integer(),
          ctrl_pressed: boolean()
        }

  @impl L2E.Packet.Decodable
  def decode(<<action_id::little-32, ctrl::little-32, _::binary>>) do
    {:ok, %__MODULE__{action_id: action_id, ctrl_pressed: ctrl == 1}}
  end

  def decode(_), do: {:error, :malformed}
end
