defmodule L2E.Packet.Client.RequestStopPledgeWar do
  @moduledoc """
  Opcode 0x8B — RequestStopPledgeWar.
  Client requests to surrender or stop the war with a clan.
  """

  defstruct [:target_clan_name]

  def decode(body) do
    target = decode_string(body)
    {:ok, %__MODULE__{target_clan_name: target}}
  end

  defp decode_string(<<>>), do: ""

  defp decode_string(data) do
    data
    |> :binary.bin_to_list()
    |> Enum.take_while(&(&1 != 0))
    |> Enum.filter(fn b -> b != 0 end)
    |> List.to_string()
  end
end
