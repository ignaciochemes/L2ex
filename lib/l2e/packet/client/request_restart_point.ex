defmodule L2E.Packet.Client.RequestRestartPoint do
  @moduledoc """
  Opcode 0x6D — sent by client to select a restart point (e.g. village, castle, siegeHQ).

  Body (RequestRestartPoint.java):
    type  LE-32   restart point type
            1 = nearest village
            2 = town
            3 = castle outer door
            4 = siege HQ
            27 = castle banish door

  Reference: RequestRestartPoint.java — REQUEST_RESTART_POINT(0x6D, ...)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:type]

  @type t :: %__MODULE__{
          type: non_neg_integer()
        }

  @impl L2E.Packet.Decodable
  def decode(<<type::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{type: type}}
  end

  def decode(_), do: {:error, :malformed}
end
