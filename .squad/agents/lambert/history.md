# Lambert — Learnings & Project Knowledge

## Project

- **Project:** L2E — Lineage II Interlude rebuilt in Elixir/OTP
- **Owner:** Ignacio Gonzalez Chemes
- **Repo:** github.com/ignaciochemes/L2Ex
- **Workspace:** `c:\Users\Ignacio\Desktop\l2e\`
- **OS:** Windows — PowerShell only. Never `Add-Content`. Always `replace_string_in_file`.

## Stack

- Elixir ~> 1.16 / OTP 27
- ThousandIsland ~> 1.3 (`use ThousandIsland.Handler`)
- pbkdf2_elixir (bcrypt FORBIDDEN on Windows)

## ThousandIsland State Shape (CRITICAL)

- `handle_info(msg, {socket, state_map})` → state is `{socket, state_map}`
- `handle_data(data, _addr, state_map)` → state is plain `state_map`
- `handle_connection(socket, state_map)` → state is plain `state_map`

## Key Network Files

- `lib/l2e/network/connection_handler.ex` — main TCP handler (cipher, flood protection, dispatch)
- `lib/l2e/network/decoder.ex` — client packet decoding
- `lib/l2e/network/encoder.ex` — server packet encoding
- `lib/l2e/network/packets/` — packet struct definitions
- `lib/l2e/crypt/` — BlowfishEngine, NewCrypt, SessionCrypt

## Current Status

- **Fase A (M1–M42):** Complete
  - M41: Flood protection implemented in ConnectionHandler
    - `@flood_limit 15`, `@strict_flood_limit 5`, `@strict_opcodes [0x01, 0x0A, 0x2C]`
    - 1-second sliding window, resets counters, `check_flood/2` returns `{:allow/:drop, state}`

## Architecture Principles (Network)

- Cipher state is process-local — never shared across connections
- Decryption before dispatch, encryption before send — no shared cipher
- Each connection is an isolated `ConnectionHandler` GenServer
- Java source in `L2J_Mobius_CT_0_Interlude/` provides exact byte layouts for packets

## Learnings

### M45/M48 — Class Advancement + Instance Zone/Door Packets (2026-05-22)

- **`client/packets.ex` and `server/packets.ex` are flat files** — no outer wrapping `defmodule`. Every packet is its own top-level `defmodule`. Append new modules after the final `end` of the last module.
- **`replace_string_in_file` fails on repeated patterns** — files like `packets.ex` have hundreds of `def decode(_), do: {:error, :malformed}\nend` closings; any short context will multi-match. Must include the entire last module (including `defmodule` line) for uniqueness.
- **`Set-Content -Encoding UTF8` writes a BOM** on Windows PowerShell 5.1. Use `[System.IO.File]::WriteAllText(path, content, New-Object System.Text.UTF8Encoding($false))` for BOM-free UTF-8 output. `Add-Content` also writes BOM on Windows — avoid for Elixir source.
- **Preferred append pattern on Windows**: use `[System.IO.File]::AppendAllText(path, text, New-Object System.Text.UTF8Encoding($false))` to avoid BOM.
- **`SocialAction` (0x5F) already existed** at line 723 of `server/packets.ex` — always grep before adding.
- **Decoder `0x2C`** is already used by `RequestOustPartyMember` on the client side; `DoorStatusUpdate` (server-only 0x2C) does not conflict — server opcodes are in a separate namespace.

### M60/M61/RelationChanged — RestartResponse, ChangeMoveType, ChangeWaitType, RelationChanged (2026-05-22)

- **`SocialAction` at line 723 confirmed** — always grep before adding; task spec correctly flagged it.
- **File is 1848 physical lines but Select-String reports line 2323** — Windows line endings cause discrepancy between `Get-Content` line count and regex match line numbers. Always use `Get-Content | Select-Object -Last N` to get actual last lines for anchor text.
- **`replace_string_in_file` anchor must be unique** — used the entire last `encode/1` body of `ExVariationResult` (4 lines) which is unique in the file. Appended all four new modules in one replacement call.

### M53 — NPC Hate List / AggroInfo (2026-05-22)

**Files modified:**
- `lib/l2e/npc/instance.ex` — added `hate_map: %{}` to state type and init; added `add_hate/3` public API; replaced monolithic `take_damage` handler with hate-aware version that derives `target_pid` from `select_top_hated/2`; added `{:add_hate, ...}` cast handler; seeded hate_map=100 on aggressive aggro detection from `player_entered`; rewrote `player_left` to remove from hate_map and re-target top-hated instead of always dropping combat; `drop_target/1` and `handle_death/1` now both clear `hate_map: %{}`; added `select_top_hated/2` private helper (filters dead pids via `Process.alive?`); added backward-compat `{:take_damage, damage}` 2-arity clause.
- `lib/l2e/session/player_session.ex` — added `L2E.NPC.Instance.add_hate(npc_pid, self(), 1)` in `start_auto_attack/1` for initial aggro on attack start (before first hit lands, in case of miss).

**Approach:**
- `hate_map` is a `%{pid => integer}` owned entirely by the NPC process — no shared state.
- `target_pid` is a derived cache recomputed on every hate change via `select_top_hated/2`.
- NPC stays in combat as long as any living player has nonzero hate; only drops to `:idle` when hate_map is empty.
- `player_session.ex` `deal_damage_to_target` already called `take_damage/3` with `self()` from M49 — no change needed there.

### FASE 3 — Friend/Pet/Siege/Duel/Olympiad server packets (2026-05-22)

- **`ServerPackets.java` enum is the canonical opcode source** — always grep it (FRIEND_LIST, L2_FRIEND, FRIEND_STATUS, FRIEND_RECV_MSG, PET_INFO, SIEGE_INFO, EX_DUEL_*, EX_OLYMPIAD_MODE) before trusting comments in Java packet files. FriendPacket.java erroneously called `ServerPackets.FRIEND_LIST.writeId` but maps to L2_FRIEND (0xFB) in the enum.
- **PetInfo has fly_run/fly_walk written twice** — the Java `writeImpl` emits fly_run and fly_walk as both `_flyRunSpd`/`_flyWalkSpd` and again (same values) one more time. Mirror this exactly.
- **Extended packet format (0xFE sub)**: `<<0xFE::8, sub::little-16, ...>>` — sub-opcode is 16-bit little-endian. ExDuelReady/Start/End/OlympiadMode all follow this pattern.
- **Unused `utf16le_string` private functions** — only include `defp utf16le_string` in modules that actually call it; omit from ExDuelReady/Start/End/OlympiadMode to avoid unused-function compiler warnings.
- **SiegeInfo conditional branching** — Java branches on castle vs. clan hall but output fields are identical; encode as flat struct with all fields; caller sets `siege_times` list for time-selection mode (empty list = fixed time, `siege_time` > 0).
- **Inline `||` in binary construction is valid Elixir** — `(p.x || 0)::little-32` compiles fine in binary construction (not matching). Useful for struct fields with nil defaults.

### M43/M44 Fix + M45/M48 Packets (2026-05-22)

- **Duplicate block removal**: `client/packets.ex` had a 153-line duplicate block — identified by opcode collision; removed via `replace_string_in_file` with full surrounding module context for uniqueness.
- **`RequestPrivateStoreSell` field fix**: `store_player_id` → `owner_obj_id` — always confirm field names against Java source `RequestSellItem.java` before referencing downstream.
- **`RequestPrivateStoreQuitBuy` (0x8D)**: empty-body decode pattern `def decode(_body), do: {:ok, %__MODULE__{}}` works for all zero-field client packets.
- **`RequestGotoLobby` (0xBA)**: same empty-body pattern. Comment placement in decoder (`# M45: Class advancement`) is used as context anchor for `replace_string_in_file`.
- **DoorInfo (0x31) layout**: `show_hp` and `is_attackable` are hardcoded to 0 in Interlude — do not expose as fields that callers must set.
- **Always grep before adding**: `SocialAction` at 0x5F was already at line 723 of `server/packets.ex`; adding it again would have caused a compile error.
- **M74-A opcode correction**: Task spec gave wrong opcodes (0xA2/0x68/0x72-0x75 for macros+alliance). Real Interlude values per `ClientPackets.java`: `RequestMakeMacro`=0xC1, `RequestDeleteMacro`=0xC2, `RequestJoinAlly`=0x82, `RequestAnswerJoinAlly`=0x83, `AllyLeave`=0x84, `RequestDismissAlly`=0x86. Always verify against `ClientPackets.java` before wiring decoder entries.
- **`SendMacroList` (0xCB)**: No `@behaviour L2E.Packet.Encodable` — uses a bare `def encode/1` with self-contained `encode_utf16le/1` helper. Length prefix is `byte_size(payload) + 2` (includes the 2-byte length field itself).
- **`macros` state field**: Added to player session state init; loaded from DB in EnterWorld and sent as `SendMacroList{revision: 0}` before `Logger.info`. Macro changes resend `revision: 1`.

## FASE 4 — Complete (2026-05-23)

Commit 3c07e5f. Delivered M74-A (macro system: migration, schema, 2 client packets, SendMacroList, EnterWorld load, CRUD handlers) and M73-A (4 alliance client packets, decoder entries, stub handlers). Corrected 6 opcodes from Java reference (`ClientPackets.java`). QA: PARTIAL on M73-A (opcode correction applied); all modules compile clean.

## M75-A — Private Store System Gap-Fill (2026-05-23)

Task audit found: the private store system was largely implemented in prior milestones (M35, M43) but had two gaps:

**Gaps identified:**
- `SetPrivateStoreMsgBuy` (0x94) — client packet module entirely missing from `client/packets.ex`; decoder entry missing; session handler missing.
- `RequestPrivateStoreQuitBuy` decoder opcode was 0x8D but Java `ClientPackets.java` says 0x93.

**Files modified:**
- `lib/l2e/packet/client/packets.ex` — appended `SetPrivateStoreMsgBuy` module (same UTF-16LE decoder pattern as `SetPrivateStoreMsgSell`).
- `lib/l2e/packet/decoder.ex` — fixed `RequestPrivateStoreQuitBuy` from 0x8D → 0x93; added `0x94 → SetPrivateStoreMsgBuy`.
- `lib/l2e/session/player_session.ex` — added `SetPrivateStoreMsgBuy` handler setting `private_store_title` (same as sell variant).

**No new server packets needed** — `PrivateStoreMsgBuy`, `PrivateStoreManageListBuy`, `PrivateStoreListBuy` already existed in `server/packets.ex`.

**Learnings:**
- Always audit ALL related opcodes in `ClientPackets.java` before declaring a feature "done" — the buy-side title message (0x94) was consistently skipped in earlier passes.
- `RequestPrivateStoreQuitBuy` had wrong opcode because task spec gave approximate values; Java is canonical.
- Compile passed with no new errors after changes.

## FASE 5 complete (2026-05-23)
