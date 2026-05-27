defmodule L2E.Packet.Client.RequestSetPledgeCrest do
  @moduledoc """
  Sent by clan leader to upload a new clan crest image.

  Binary layout (after opcode byte):
    - length  :: little-int32  — byte length of crest data (0 = delete crest; max 256)
    - data    :: binary-size(length)

  Source: RequestSetPledgeCrest.java (readInt → readBytes)
  """
  defstruct data: <<>>

  @max_crest_size 256

  @doc "Decodes the packet body (opcode already stripped)."
  def decode(<<len::little-32, data::binary-size(len), _::binary>>) when len <= @max_crest_size do
    %__MODULE__{data: data}
  end

  def decode(<<_len::little-32, _rest::binary>>) do
    # length > 256 or truncated — treat as empty (server will reject in handler)
    %__MODULE__{}
  end

  def decode(_), do: %__MODULE__{}
end
