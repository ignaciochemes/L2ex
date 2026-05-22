defmodule L2E.Packet.Client.MoveWithDelta do
  @moduledoc """
  Opcode 0x41 — sent by client with delta-movement (relative coordinates).

  Body (MoveWithDelta.java):
    dx  LE-32   delta X
    dy  LE-32   delta Y
    dz  LE-32   delta Z

  Reference: MoveWithDelta.java — MOVE_WITH_DELTA(0x41, ...)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:dx, :dy, :dz]

  @type t :: %__MODULE__{
          dx: integer(),
          dy: integer(),
          dz: integer()
        }

  @impl L2E.Packet.Decodable
  def decode(<<dx::little-32-signed, dy::little-32-signed, dz::little-32-signed, _rest::binary>>) do
    {:ok, %__MODULE__{dx: dx, dy: dy, dz: dz}}
  end

  def decode(_), do: {:error, :malformed}
end
