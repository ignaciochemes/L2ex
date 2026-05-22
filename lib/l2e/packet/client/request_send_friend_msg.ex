defmodule L2E.Packet.Client.RequestSendFriendMsg do
  @moduledoc """
  Opcode 0xCC — send a private message to a friend.

  Wire order (RequestSendFriendMsg.java):
    _message  = readString()  (first)
    _reciever = readString()  (second)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:message, :char_name]

  @type t :: %__MODULE__{message: String.t(), char_name: String.t()}

  @impl L2E.Packet.Decodable
  def decode(body) do
    with {message, rest} <- decode_utf16le(body),
         {char_name, _} <- decode_utf16le(rest) do
      {:ok, %__MODULE__{message: message, char_name: char_name}}
    else
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
