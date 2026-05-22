defmodule L2E.Packet.Client.RequestFriendDel do
  @moduledoc "Opcode 0x61 — remove a friend by name. Reference: RequestFriendDel.java"
  @behaviour L2E.Packet.Decodable

  defstruct [:name]

  @type t :: %__MODULE__{name: String.t()}

  @impl L2E.Packet.Decodable
  def decode(body) do
    case decode_utf16le(body) do
      {name, _} -> {:ok, %__MODULE__{name: name}}
      _ -> {:error, :malformed}
    end
  end

  def decode(_), do: {:error, :malformed}

  defp decode_utf16le(bin), do: do_utf16(bin, [])

  defp do_utf16(<<0, 0, rest::binary>>, acc),
    do: {acc |> Enum.reverse() |> Enum.map_join(&<<&1::utf8>>), rest}

  defp do_utf16(<<cp::little-16, rest::binary>>, acc), do: do_utf16(rest, [cp | acc])
  defp do_utf16(_, _), do: :error
end
