defmodule L2E.Packet.Client.RequestFishing do
  @moduledoc "Opcode 0x89 — Client requests to start or stop fishing."
  @behaviour L2E.Packet.Decodable

  defstruct [:x, :y, :z]

  @type t :: %__MODULE__{x: integer(), y: integer(), z: integer()}

  @impl L2E.Packet.Decodable
  def decode(<<x::little-32-signed, y::little-32-signed, z::little-32-signed, _rest::binary>>) do
    {:ok, %__MODULE__{x: x, y: y, z: z}}
  end

  def decode(_), do: {:error, :invalid_packet}
end
