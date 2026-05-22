defmodule L2E.Packet.Client.RequestSocialAction do
  @moduledoc """
  Opcode 0x1B — sent by client to trigger a social/emote animation.

  Body (RequestSocialAction.java):
    action_id  LE-32   social action ID (e.g. 1=wave, 2=victory, etc.)

  Reference: RequestSocialAction.java — REQUEST_SOCIAL_ACTION(0x1B, ...)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:action_id]

  @type t :: %__MODULE__{
          action_id: non_neg_integer()
        }

  @impl L2E.Packet.Decodable
  def decode(<<action_id::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{action_id: action_id}}
  end

  def decode(_), do: {:error, :malformed}
end
