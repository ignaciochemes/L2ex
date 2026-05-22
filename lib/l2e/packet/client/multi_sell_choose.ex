defmodule L2E.Packet.Client.MultiSellChoose do
  @moduledoc "Player selects an entry in a multisell list to execute."

  @behaviour L2E.Packet.Decodable

  defstruct [:list_id, :entry_id, :count]

  @impl L2E.Packet.Decodable
  def decode(<<list_id::little-32, entry_id::little-32, count::little-32, _rest::binary>>) do
    {:ok, %__MODULE__{list_id: list_id, entry_id: entry_id, count: count}}
  end

  def decode(_), do: {:error, :malformed}
end
