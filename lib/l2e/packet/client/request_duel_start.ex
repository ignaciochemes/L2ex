defmodule L2E.Packet.Client.RequestDuelStart do
  @moduledoc """
  Extended opcode 0xD0/0x27 — request to start a duel with a player.

  Wire order (RequestDuelStart.java):
    _player    = readString()  target player name
    _partyDuel = readInt()     0=1v1, 1=party duel
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:target_name, :party_duel]

  @type t :: %__MODULE__{target_name: String.t(), party_duel: integer()}

  @impl L2E.Packet.Decodable
  def decode(body) do
    case decode_utf16le(body) do
      {name, <<party_duel::little-32, _rest::binary>>} ->
        {:ok, %__MODULE__{target_name: name, party_duel: party_duel}}

      _ ->
        {:error, :malformed}
    end
  end

  def decode(_), do: {:error, :malformed}

  defp decode_utf16le(bin), do: do_utf16(bin, [])

  defp do_utf16(<<0, 0, rest::binary>>, acc),
    do: {acc |> Enum.reverse() |> Enum.map_join(&<<&1::utf8>>), rest}

  defp do_utf16(<<cp::little-16, rest::binary>>, acc), do: do_utf16(rest, [cp | acc])
  defp do_utf16(_, _), do: :error
end
