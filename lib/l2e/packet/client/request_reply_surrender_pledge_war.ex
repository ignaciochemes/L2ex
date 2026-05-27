defmodule L2E.Packet.Client.RequestReplySurrenderPledgeWar do
  @moduledoc """
  RequestReplySurrenderPledgeWar — defender accepts/rejects surrender offer.
  NOTE: Opcode 0x8A conflicts with RequestPetUseItem in the current decoder;
  the handler is wired but the opcode binding is intentionally omitted.
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
