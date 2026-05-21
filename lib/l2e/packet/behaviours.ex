defmodule L2E.Packet.Decodable do
  @moduledoc """
  Behaviour for client → server packet modules.

  Every inbound packet module MUST implement this callback.
  Implementors must be pure functions — no side effects, no GenServer calls,
  no ETS reads. The decoder is called in the ConnectionHandler process
  on the hot receive path; allocations here affect every connected client.

  ## Contract

  - `decode/1` receives the packet body AFTER the opcode byte has been stripped.
  - On success, return `{:ok, struct}` — the struct is the packet's typed payload.
  - On malformed input, return `{:error, :malformed}` — the connection will be closed.
  - Ignore trailing bytes in the binary (use `_rest::binary` in patterns) so the
    server is resilient to minor protocol version differences.
  """

  @callback decode(body :: binary()) :: {:ok, struct()} | {:error, :malformed}
end

defmodule L2E.Packet.Encodable do
  @moduledoc """
  Behaviour for server → client packet modules.

  Every outbound packet module MUST implement this callback.
  Implementors must be pure functions.

  ## Contract

  - `encode/1` receives the typed packet struct and returns raw payload bytes.
  - The opcode byte MUST be the first byte of the returned binary.
  - The 2-byte length header is NOT included — ConnectionHandler adds the frame.
  """

  @callback encode(packet :: struct()) :: binary()
end
