# Bishop — Project History

## Project Context

**Project:** L2E — Lineage II Interlude rebuilt in Elixir/OTP  
**Owner:** Ignacio Gonzalez Chemes  
**Stack:** Elixir ~> 1.16 / OTP 27, ThousandIsland ~> 1.3, Ecto/PostgreSQL ~> 3.11, Phoenix.PubSub, ETS  
**OS:** Windows — PowerShell only. Never `Add-Content`. Always `replace_string_in_file`.  
**Constraint:** bcrypt FORBIDDEN → always `pbkdf2_elixir`.  

## Current State (as of 2026-05-22)

- M1–M63 complete: Login server, player sessions, combat, skills, inventory, quests, clans, parties, NPC AI, movement, henna/recipe/aug, shortcuts, enchant, private stores, XP loss, session lifecycle, movement completeness
- Client packets: ~67/213 (31%), Server packets: ~76/274 (28%)
- Sub-classes, Duel, Olympiad, Siege, Pets, Grand Bosses, SSQ: NOT YET STARTED

## Assigned Focus

I handle endgame systems. Priority order:
1. Sub-class system (M68) — foundational for Olympiad
2. Duel system (M69) — prerequisite for Olympiad
3. Olympiad (M70) — depends on M68+M69
4. Pets & Summons (M72) — needed for Summoner/Bishop classes
5. Siege (M71) — largest system, tackle last

## Learnings

- Day 1: Hired as Endgame Systems Engineer. Team uses Alien universe casting.
- 2026-05-22: FASE 3 OTP module foundations created (M68-M72). All compile clean. Key lesson: remove unused module attributes (@siege_duration_ms) — Elixir warns on them. `restart: :temporary` on Session GenServers is correct for ephemeral game sessions (Duel, Pet). ETS `:match_delete` with pattern `{{:player, :_}, duel_id}` works cleanly for reverse-lookup cleanup. `L2E.Duel.Registry` is just a named atom module — the actual Registry process is started via `{Registry, keys: :unique, name: L2E.Duel.Registry}` in application.ex (Dallas's job).
- 2026-05-23: M61-A (GrandBoss.Manager + GrandBoss.Supervisor) and M73-B (World.DayNightManager) created and wired into application.ex. Compile clean. Key lesson: L2J CT0 Interlude has a duplicate NPC ID issue — Antharas=29022, Zaken=29026 (NOT 29022). Always cross-check boss IDs before hardcoding. ETS `:grand_boss_states` table uses `{boss_id, state, respawn_at}` tuples; `read_concurrency: true` is appropriate since `get_state/1` is called from many player-facing code paths but writes are rare (boss deaths). DayNightManager is intentionally a plain GenServer (no Supervisor wrapper) since it has no children — supervised directly under the application root.

## FASE 4 — Complete (2026-05-23)

Commit 3c07e5f. Delivered M61-A (Grand Boss Manager, 9 bosses, ETS state machine, respawn timers) and M73-B (Day/Night Manager, 2h cycle, PubSub broadcast). Both modules wired into application.ex supervision tree. QA: 9/10 PASS.

## FASE 5 — M61-B: Seven Signs System Foundation (2026-05-23)

Delivered Seven Signs Quest (SSQ) foundation layer. Files created:
- `priv/repo/migrations/20260523000002_create_seven_signs.exs` — two tables: `seven_signs_players` (per-character participation) and `seven_signs_state` (server-wide cycle/seal state)
- `lib/l2e/db/seven_signs_player.ex` — Ecto schema with changeset validation
- `lib/l2e/sevensigns/manager.ex` — GenServer state machine; configurable period timer (`ssq_period_ms`, default 1h); PubSub broadcasts on period change and cabal registration
- `lib/l2e/sevensigns/supervisor.ex` — one_for_one Supervisor wrapping Manager
- `lib/l2e/packet/client/packets.ex` — `RequestSSQStatus` struct (opcode 0xC7, 1-byte page)
- `lib/l2e/packet/decoder.ex` — decoder entry for 0xC7
- `lib/l2e/session/player_session.ex` — stub handler for RequestSSQStatus (SSQStatus server packet pending M61-C)
- `lib/l2e/application.ex` — wired `L2E.SevenSigns.Supervisor` after DayNightManager

Compile: clean (no new errors or warnings).

Key lessons:
- SSQ cabal registration in Interlude is bypass-driven (NPC dialog), NOT a dedicated client packet. `RequestSSQStatus` (0xC7) is the only SSQ client packet.
- `award_seals/1` had a subtle bug in the original spec: after Seal Validation ends it was reading `state.current_cycle + 1` but at that point `state` had already been piped — fixed by binding `next_cycle = state.current_cycle + 1` before the struct update to avoid double-increment.
- `update_stones/4` returns an updated struct; `add_score` cast must use `new_state.dawn_score`/`new_state.dusk_score` (not `state.*`) after stones update — fixed.
- Migration uses `:bigint` for score fields (correct for Ecto + Postgres); `accumulated_adena` in the Ecto schema uses `:integer` (sufficient for Interlude adena caps).

## FASE 5 complete (2026-05-23)
