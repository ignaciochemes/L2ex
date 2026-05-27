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
  def decode(0x12, body), do: Client.RequestDropItem.decode(body)
  def decode(0x15, body), do: Client.TradeRequest.decode(body)
  def decode(0x16, body), do: Client.AddTradeItem.decode(body)
  def decode(0x17, body), do: Client.TradeDone.decode(body)
  def decode(0x44, body), do: Client.AnswerTradeRequest.decode(body)
  # M59: RequestActionUse
  def decode(0x45, body), do: Client.RequestActionUse.decode(body)
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
  # M82: Party loot mode
  def decode(0x5B, body), do: Client.RequestPartyLootModify.decode(body)
  def decode(0x2F, body), do: Client.RequestMagicSkillUse.decode(body)
  # M54: Shortcut bar
  def decode(0x31, body), do: Client.RequestWarehouseDeposit.decode(body)
  def decode(0x32, body), do: Client.RequestWarehouseWithdraw.decode(body)
  def decode(0x33, body), do: Client.RequestShortcutReg.decode(body)
  def decode(0x35, body), do: Client.RequestShortcutDel.decode(body)
  def decode(0x37, body), do: Client.RequestTargetCanceld.decode(body)
  # M17: Chat
  def decode(0x38, body), do: Client.Say2.decode(body)
  def decode(0x3F, body), do: Client.RequestSkillList.decode(body)
  def decode(0x48, body), do: Client.ValidatePosition.decode(body)

  # M28: Enchant
  def decode(0x58, body), do: Client.RequestEnchantItem.decode(body)
  # M33: Destroy item
  def decode(0x59, body), do: Client.RequestDestroyItem.decode(body)
  # M80: Dialog answer
  def decode(0x5C, body), do: Client.RequestDlgAnswer.decode(body)

  # M35: Private store — sell
  def decode(0x73, body), do: Client.RequestPrivateStoreManageSell.decode(body)
  def decode(0x74, body), do: Client.SetPrivateStoreListSell.decode(body)
  def decode(0x76, body), do: Client.RequestPrivateStoreQuitSell.decode(body)
  def decode(0x77, body), do: Client.SetPrivateStoreMsgSell.decode(body)
  def decode(0x79, body), do: Client.RequestPrivateStoreBuy.decode(body)

  # M44: Skill tree + learn
  def decode(0x6B, body), do: Client.RequestAcquireSkillInfo.decode(body)
  def decode(0x6C, body), do: Client.RequestAcquireSkill.decode(body)

  # M43: Private store — buy
  def decode(0x90, body), do: Client.RequestPrivateStoreManageBuy.decode(body)
  def decode(0x91, body), do: Client.SetPrivateStoreListBuy.decode(body)
  def decode(0x96, body), do: Client.RequestPrivateStoreSell.decode(body)
  def decode(0x93, body), do: Client.RequestPrivateStoreQuitBuy.decode(body)
  # M75-A: buy store title message
  def decode(0x94, body), do: Client.SetPrivateStoreMsgBuy.decode(body)

  # M60: Session lifecycle
  def decode(0x09, body), do: Client.Logout.decode(body)
  def decode(0x30, body), do: Client.Appearing.decode(body)
  def decode(0x46, body), do: Client.RequestRestart.decode(body)
  def decode(0x6D, body), do: Client.RequestRestartPoint.decode(body)

  # M77: Spoil / Sweep
  def decode(0x42, body), do: Client.RequestSweep.decode(body)

  # M61: Movement
  def decode(0x41, body), do: Client.MoveWithDelta.decode(body)
  def decode(0x36, body), do: Client.CannotMoveAnymore.decode(body)
  def decode(0x1B, body), do: Client.RequestSocialAction.decode(body)
  def decode(0x1C, body), do: Client.ChangeMoveType2.decode(body)
  def decode(0x1D, body), do: Client.ChangeWaitType2.decode(body)

  # M62: Inventory actions
  def decode(0x11, body), do: Client.RequestUnequipItem.decode(body)
  def decode(0x72, body), do: Client.RequestCrystallizeItem.decode(body)
  def decode(0x0F, body), do: Client.RequestItemList.decode(body)

  # M64: MultiSell
  def decode(0x64, body), do: Client.MultiSellChoose.decode(body)
  # M81: Block list
  def decode(0x65, body), do: Client.RequestBlock.decode(body)

  # M45: Class advancement
  def decode(0xBA, body), do: Client.RequestGotoLobby.decode(body)

  # M56: Henna / Recipe / Augmentation
  def decode(0xAF, body), do: Client.RequestRecipeItemMakeSelf.decode(body)
  def decode(0xBC, body), do: Client.RequestHennaEquip.decode(body)
  def decode(0xBF, body), do: Client.RequestHennaRemove.decode(body)

  # M66: Friend system
  def decode(0x5E, body), do: Client.RequestFriendInvite.decode(body)
  # M74-A: Macro + Alliance
  def decode(0xC1, body), do: Client.RequestMakeMacro.decode(body)
  def decode(0xC2, body), do: Client.RequestDeleteMacro.decode(body)
  def decode(0x82, body), do: Client.RequestJoinAlly.decode(body)
  def decode(0x83, body), do: Client.RequestAnswerJoinAlly.decode(body)
  def decode(0x86, body), do: Client.RequestDismissAlly.decode(body)
  def decode(0x84, body), do: Client.AllyLeave.decode(body)
  def decode(0x5F, body), do: Client.RequestAnswerFriendInvite.decode(body)
  def decode(0x60, body), do: Client.RequestFriendList.decode(body)
  def decode(0x61, body), do: Client.RequestFriendDel.decode(body)
  def decode(0xCC, body), do: Client.RequestSendFriendMsg.decode(body)

  # M71: Siege
  def decode(0x47, body), do: Client.RequestSiegeInfo.decode(body)
  def decode(0xB2, body), do: Client.RequestJoinSiege.decode(body)
  # M100: Siege attacker/defender lists
  def decode(0xBD, body), do: Client.RequestSiegeAttackerList.decode(body)
  def decode(0xBE, body), do: Client.RequestSiegeDefenderList.decode(body)

  # M72: Pet
  def decode(0x8A, body), do: Client.RequestPetUseItem.decode(body)
  def decode(0x8E, body), do: Client.RequestPetItemList.decode(body)
  def decode(0x8F, body), do: Client.RequestPetGetItem.decode(body)

  # M86: Fishing
  def decode(0x89, body), do: Client.RequestFishing.decode(body)

  # M61-B: Seven Signs Quest
  def decode(0xC7, body), do: Client.RequestSSQStatus.decode(body)

  # M89: Community Board (BBS)
  def decode(0xAB, body), do: Client.RequestShowBoard.decode(body)

  # M94: Clan Wars
  # 0x88 = RequestStartPledgeWar (declare war)
  # 0x8B = RequestStopPledgeWar (surrender/stop war)
  # NOTE: 0x89 (ReplyStart) and 0x8A (ReplySurrender) conflict with Fishing/Pet opcodes
  def decode(0x88, body), do: Client.RequestStartPledgeWar.decode(body)
  def decode(0x8B, body), do: Client.RequestStopPledgeWar.decode(body)

  # ── Extended two-byte opcode space (0xD0 prefix) ────────────────────────────
  # Body starts with a little-endian 16-bit sub-opcode, then the real payload.

  def decode(0xD0, <<sub::little-16, body::binary>>), do: decode_ext(sub, body)
  def decode(0xD0, _), do: {:error, :malformed}

  # ── Catch-all ───────────────────────────────────────────────────────────────

  def decode(_, _), do: {:error, :unknown_opcode}

  # ── Extended opcode dispatch ─────────────────────────────────────────────────
  # Add clauses here as new 0xD0-prefixed packets are implemented.

  # M39: Auto soulshot/spiritshot toggle
  defp decode_ext(0x05, body), do: Client.RequestAutoSoulShot.decode(body)

  # M56: Augmentation — confirm life stone selection + perform augment
  defp decode_ext(0x2A, body), do: Client.RequestConfirmRefinerItem.decode(body)
  defp decode_ext(0x2C, body), do: Client.RequestRefine.decode(body)

  # M69: Duel (extended)
  defp decode_ext(0x27, body), do: Client.RequestDuelStart.decode(body)
  defp decode_ext(0x28, body), do: Client.RequestDuelAnswerStart.decode(body)
  defp decode_ext(0x30, body), do: Client.RequestDuelSurrender.decode(body)

  # M70: Olympiad (extended)
  defp decode_ext(0x13, body), do: Client.RequestOlympiadMatchList.decode(body)
  defp decode_ext(0x29, body), do: Client.RequestJoinOlympiad.decode(body)

  # M68-B: Sub-class switching (extended)
  defp decode_ext(0x31, body), do: Client.RequestSubclassInfo.decode(body)
  defp decode_ext(0x32, body), do: Client.RequestSubclassChange.decode(body)
  defp decode_ext(0x33, body), do: Client.RequestExAddSubclass.decode(body)

  # M107: Skill Enchant (extended)
  defp decode_ext(0x34, body), do: Client.RequestExEnchantSkillList.decode(body)
  defp decode_ext(0x35, body), do: Client.RequestExEnchantSkillInfo.decode(body)
  defp decode_ext(0x36, body), do: Client.RequestExEnchantSkill.decode(body)

  defp decode_ext(_sub, _body), do: {:error, :unknown_opcode}
end
