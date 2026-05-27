defmodule L2E.Packet.Client.RequestStartPledgeWar do
  @moduledoc """
  Opcode 0x88 — RequestStartPledgeWar.
  Client requests to declare war on a clan by name.
  """

  defstruct [:target_clan_name]

  def decode(body) do
    target = decode_string(body)
    {:ok, %__MODULE__{target_clan_name: target}}
  end

  defp decode_string(<<>>), do: ""

  defp decode_string(data) do
    # UTF-16LE null-terminated — strip every other null byte for basic ASCII names
    data
    |> :binary.bin_to_list()
    |> Enum.take_while(&(&1 != 0))
    |> Enum.filter(fn b -> b != 0 end)
    |> List.to_string()
  end
end
