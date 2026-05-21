defmodule L2E.Packet.Encoder do
  @moduledoc """
  Pure function dispatch: server packet struct → binary payload.

  All encoders are side-effect free.
  The payload is the raw bytes WITHOUT the 2-byte length header.
  Framing is applied by ConnectionHandler.
  """

  @type encode_result :: {:ok, binary()} | {:error, :unknown_packet}

  @spec encode(struct()) :: encode_result()
  def encode(%module{} = packet) do
    if function_exported?(module, :encode, 1) do
      {:ok, module.encode(packet)}
    else
      {:error, :unknown_packet}
    end
  end
end
