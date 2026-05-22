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

### M43/M44 Fix + M45/M48 Packets (2026-05-22)

- **Duplicate block removal**: `client/packets.ex` had a 153-line duplicate block — identified by opcode collision; removed via `replace_string_in_file` with full surrounding module context for uniqueness.
- **`RequestPrivateStoreSell` field fix**: `store_player_id` → `owner_obj_id` — always confirm field names against Java source `RequestSellItem.java` before referencing downstream.
- **`RequestPrivateStoreQuitBuy` (0x8D)**: empty-body decode pattern `def decode(_body), do: {:ok, %__MODULE__{}}` works for all zero-field client packets.
- **`RequestGotoLobby` (0xBA)**: same empty-body pattern. Comment placement in decoder (`# M45: Class advancement`) is used as context anchor for `replace_string_in_file`.
- **DoorInfo (0x31) layout**: `show_hp` and `is_attackable` are hardcoded to 0 in Interlude — do not expose as fields that callers must set.
- **Always grep before adding**: `SocialAction` at 0x5F was already at line 723 of `server/packets.ex`; adding it again would have caused a compile error.
