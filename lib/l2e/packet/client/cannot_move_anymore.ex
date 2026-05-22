defmodule L2E.Packet.Client.CannotMoveAnymore do
  @moduledoc """
  Opcode 0x36 — sent by client when it is blocked and cannot move further.
  Carries the player's current position and heading so the server can
  correct any desync.

  Body (CannotMoveAnymore.java):
    x        LE-32-signed   current X
    y        LE-32-signed   current Y
    z        LE-32-signed   current Z
    heading  LE-32          character heading (0–65535)

  Reference: CannotMoveAnymore.java — CANNOT_MOVE_ANYMORE(0x36, ...)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:x, :y, :z, :heading]

  @type t :: %__MODULE__{
          x: integer(),
          y: integer(),
          z: integer(),
          heading: non_neg_integer()
        }

  @impl L2E.Packet.Decodable
  def decode(
        <<x::little-32-signed, y::little-32-signed, z::little-32-signed, heading::little-32,
          _rest::binary>>
      ) do
    {:ok, %__MODULE__{x: x, y: y, z: z, heading: heading}}
  end

  def decode(_), do: {:error, :malformed}
end
