defmodule L2E.Packet.Decoder do
  @moduledoc """
  Pure function dispatch: (opcode, body) → typed packet struct.

  ## Design

  Dispatch uses function clause pattern matching on literal integer opcodes.
  The BEAM compiler emits a `select_val` instruction for this pattern, which
  is equivalent to a jump table — O(1) with zero map allocation per call.

  This is strictly cheaper than a runtime `Map.fetch/2` on the hot receive path.

  ## Two-byte extended opcodes

  L2 Interlude uses opcode 0xD0 as a prefix for an extended opcode space.
  When the first byte is 0xD0, the next two bytes (little-endian) form the
  real opcode. Add new extended packets in `decode_ext/2`.

  ## Adding a new packet

  1. Create `lib/l2e/packet/client/<name>.ex` implementing `L2E.Packet.Decodable`.
  2. Add a `decode(0xNN, body)` clause here.
  3. Add a handler clause in `L2E.Session.PlayerSession`.

  Opcodes: verify against L2J_Mobius_CT_0_Interlude gameserver IncomingPackets enum.
  """

  alias L2E.Packet.Client

  @type result :: {:ok, struct()} | {:error, :unknown_opcode} | {:error, :malformed}

  @spec decode(byte(), binary()) :: result()

  # ── Standard single-byte opcodes ────────────────────────────────────────────
  # TODO: verify each opcode against L2J Mobius IncomingPackets

  def decode(0x00, body), do: Client.ProtocolVersion.decode(body)
  def decode(0x01, body), do: Client.MoveToLocation.decode(body)
  def decode(0x03, body), do: Client.EnterWorld.decode(body)
  def decode(0x04, body), do: Client.Action.decode(body)
  def decode(0x08, body), do: Client.AuthLogin.decode(body)
  def decode(0x0A, body), do: Client.AttackRequest.decode(body)
  def decode(0x0B, body), do: Client.CharacterCreate.decode(body)
  def decode(0x0C, body), do: Client.CharacterDelete.decode(body)
  def decode(0x0D, body), do: Client.CharacterSelect.decode(body)
  def decode(0x0E, body), do: Client.NewCharacter.decode(body)
  def decode(0x16, body), do: Client.RequestPickUpItem.decode(body)
  def decode(0x19, body), do: Client.UseItem.decode(body)
  def decode(0x2F, body), do: Client.RequestMagicSkillUse.decode(body)
  def decode(0x37, body), do: Client.RequestTargetCanceld.decode(body)
  def decode(0x3F, body), do: Client.RequestSkillList.decode(body)
  def decode(0x48, body), do: Client.ValidatePosition.decode(body)

  # ── Extended two-byte opcode space (0xD0 prefix) ────────────────────────────
  # Body starts with a little-endian 16-bit sub-opcode, then the real payload.

  def decode(0xD0, <<sub::little-16, body::binary>>), do: decode_ext(sub, body)
  def decode(0xD0, _), do: {:error, :malformed}

  # ── Catch-all ───────────────────────────────────────────────────────────────

  def decode(_, _), do: {:error, :unknown_opcode}

  # ── Extended opcode dispatch ─────────────────────────────────────────────────
  # Add clauses here as new 0xD0-prefixed packets are implemented.

  defp decode_ext(_sub, _body), do: {:error, :unknown_opcode}
end
