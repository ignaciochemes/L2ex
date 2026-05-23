# Orchestration Log — Lambert — FASE 5 (2026-05-23)

**Agent:** Lambert (Network & Protocol Engineer)
**Milestone:** M75-A — Private Store Gap-Fill (Missing Packet + Opcode Fix)
**Status:** COMPLETED

---

## Task Summary

Audited private store packet coverage. Found and resolved two gaps: missing `SetPrivateStoreMsgBuy` packet and wrong opcode for `RequestPrivateStoreQuitBuy`.

## Gaps Found and Resolved

| Gap | Before | After |
|-----|--------|-------|
| `SetPrivateStoreMsgBuy` client packet | Missing | Added (0x94) |
| `SetPrivateStoreMsgBuy` decoder entry | Missing (0x94 unrouted) | Added |
| `SetPrivateStoreMsgBuy` session handler | Missing | Added (2 clauses) |
| `RequestPrivateStoreQuitBuy` opcode | 0x8D (wrong) | 0x93 (correct, Java-verified) |

## Files Modified

| File | Change |
|------|--------|
| `lib/l2e/packet/client/packets.ex` | Added `SetPrivateStoreMsgBuy` module with UTF-16LE string decoder |
| `lib/l2e/packet/decoder.ex` | Fixed 0x8D → 0x93 for `RequestPrivateStoreQuitBuy`; added 0x94 for `SetPrivateStoreMsgBuy` |
| `lib/l2e/session/player_session.ex` | Added `SetPrivateStoreMsgBuy` handler (2 clauses: one updating type + title, one for title-only update) |

## Decisions Made

- D1: `decode_utf16_string/1` duplicated in new module (mirrors sell variant pattern, no cross-module coupling)
- D2: `private_store_title` shared field reused (single active store invariant)
- D3: 0x93 authoritative from `ClientPackets.java`
- D4: No new server packets needed

## Outcome

`mix compile` passes with zero new errors. All 10 private store opcodes correctly wired end-to-end.

## Notes

Opcode 0x8D conflict with another handler was a latent bug: only triggered for clients that send the quit-buy packet. Low player-visible impact but correctness-critical for buy store lifecycle management.
