# Ash — Learnings & Project Knowledge

## Project

- **Project:** L2E — Lineage II Interlude rebuilt in Elixir/OTP
- **Owner:** Ignacio Gonzalez Chemes
- **Repo:** github.com/ignaciochemes/L2Ex
- **Workspace:** `c:\Users\Ignacio\Desktop\l2e\`
- **OS:** Windows — PowerShell only. Never `Add-Content`. Always `replace_string_in_file`.

## Stack

- Elixir ~> 1.16 / OTP 27
- ExUnit (built-in)
- StreamData (property-based testing)
- Test DB: separate PostgreSQL DB for tests, rollback on teardown

## Key Test Areas

| System | What to Test | Edge Cases |
|--------|-------------|------------|
| Combat resolver | Damage output is non-negative, attacker/target state after combat | Integer overflow in level-scaled formulas |
| Warehouse | Deposit/withdraw atomicity, count never goes negative | Concurrent access from two sessions |
| Region handoff | Entity appears in exactly one region during cross-region move | Race between two simultaneous movers |
| Packet decode | No crash on any byte sequence, unknown opcodes return :ignore | Truncated packets, oversized packets |
| Flood protection | Strict opcodes blocked after limit, counter resets after 1 second | Exactly at limit, one over limit |
| Clan warehouse | Deposit/withdraw require clan_id match, count consistency | clan_id 0 (no clan) should error |

## Current Status

- **Test coverage:** Not formally measured yet — Fase A focused on implementation
- **Priority for Fase B:** Add tests for M43–M48 systems as they're implemented

## Test Conventions

- `start_supervised/1` for GenServer isolation in unit tests
- `Ecto.Adapters.SQL.Sandbox` for DB tests
- StreamData for combat formulas and packet parsing
- Test files at `test/l2e/` mirroring `lib/l2e/` structure

## Learnings
