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
  # M27: Trade
  def decode(0x15, body), do: Client.TradeRequest.decode(body)
  def decode(0x16, body), do: Client.AddTradeItem.decode(body)
  def decode(0x17, body), do: Client.TradeDone.decode(body)
  def decode(0x44, body), do: Client.AnswerTradeRequest.decode(body)
  def decode(0x19, body), do: Client.UseItem.decode(body)
  # M16: NPC interaction
  def decode(0x1E, body), do: Client.RequestSellItem.decode(body)
  def decode(0x1F, body), do: Client.RequestBuyItem.decode(body)
  def decode(0x21, body), do: Client.RequestBypassToServer.decode(body)
  # M22: Clans
  def decode(0x24, body), do: Client.RequestJoinPledge.decode(body)
  def decode(0x25, body), do: Client.RequestAnswerJoinPledge.decode(body)
  def decode(0x26, body), do: Client.RequestWithdrawalPledge.decode(body)
  def decode(0x27, body), do: Client.RequestOustPledgeMember.decode(body)
  # M21: Party
  def decode(0x29, body), do: Client.RequestJoinParty.decode(body)
  def decode(0x2A, body), do: Client.RequestAnswerJoinParty.decode(body)
  def decode(0x2B, body), do: Client.RequestWithDrawalParty.decode(body)
  def decode(0x2C, body), do: Client.RequestOustPartyMember.decode(body)
  def decode(0x2F, body), do: Client.RequestMagicSkillUse.decode(body)
  def decode(0x32, body), do: Client.RequestWarehouseWithdraw.decode(body)
  def decode(0x33, body), do: Client.RequestWarehouseDeposit.decode(body)
  def decode(0x37, body), do: Client.RequestTargetCanceld.decode(body)
  # M17: Chat
  def decode(0x38, body), do: Client.Say2.decode(body)
  def decode(0x3F, body), do: Client.RequestSkillList.decode(body)
  def decode(0x48, body), do: Client.ValidatePosition.decode(body)

  # M28: Enchant
  def decode(0x58, body), do: Client.RequestEnchantItem.decode(body)

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
