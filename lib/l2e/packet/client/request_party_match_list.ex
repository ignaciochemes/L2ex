defmodule L2E.Packet.Client.RequestPartyMatchList do
  @moduledoc """
  Opcode 0x70 — RequestPartyMatchList.

  Sent when the client creates or updates a Party Match Room listing.

  Wire order (RequestPartyMatchList.java):
    _roomid     = readInt()     Room id (0 = new room)
    _membersmax = readInt()     Max members (up to 9)
    _minLevel   = readInt()     Minimum level requirement
    _maxLevel   = readInt()     Maximum level requirement
    _loot       = readInt()     Loot type (0=by_turn 1=random 2=spoil 3=item_order)
    _roomtitle  = readString()  Room title (null-terminated UTF-16LE)
  """
  @behaviour L2E.Packet.Decodable

  defstruct [:room_id, :members_max, :min_level, :max_level, :loot, :room_title]

  @type t :: %__MODULE__{
          room_id: integer(),
          members_max: integer(),
          min_level: integer(),
          max_level: integer(),
          loot: integer(),
          room_title: String.t()
        }

  @impl L2E.Packet.Decodable
  def decode(
        <<room_id::little-32, members_max::little-32, min_level::little-32, max_level::little-32,
          loot::little-32, rest::binary>>
      ) do
    case decode_utf16le(rest) do
      {title, _} ->
        {:ok,
         %__MODULE__{
           room_id: room_id,
           members_max: members_max,
           min_level: min_level,
           max_level: max_level,
           loot: loot,
           room_title: title
         }}

      _ ->
        {:error, :malformed}
    end
  end

  def decode(_), do: {:error, :malformed}

  defp decode_utf16le(bin), do: do_utf16(bin, [])

  defp do_utf16(<<0, 0, rest::binary>>, acc) do
    str = acc |> Enum.reverse() |> IO.iodata_to_binary()
    {str, rest}
  end

  defp do_utf16(<<a, b, rest::binary>>, acc) do
    char = <<a, b>>
    decoded = :unicode.characters_to_binary(char, {:utf16, :little}, :utf8)
    do_utf16(rest, [decoded | acc])
  end

  defp do_utf16(<<>>, acc) do
    str = acc |> Enum.reverse() |> IO.iodata_to_binary()
    {str, <<>>}
  end
end
