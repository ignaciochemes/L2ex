defmodule L2E.Packet.Client.RequestRecipeBookOpen do
  @moduledoc """
  Opcode 0xAC — player opens their recipe book.

  Body (RequestRecipeBookOpen.java):
    isDwarvenCraft  LE-32  — 0 = Dwarven craft book, 1 = Common craft book

  Note: Java reads `readInt() == 0` to determine isDwarvenCraft, so
  the field is 0 for Dwarven and non-zero (1) for Common.
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:is_dwarven]
  @type t :: %__MODULE__{is_dwarven: boolean()}

  @impl L2E.Packet.Decodable
  def decode(<<flag::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{is_dwarven: flag == 0}}
  end

  def decode(_), do: {:error, :malformed}
end
