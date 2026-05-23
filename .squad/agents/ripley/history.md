# Ripley — Learnings & Project Knowledge

## Project

- **Project:** L2E — Lineage II Interlude rebuilt in Elixir/OTP
- **Owner:** Ignacio Gonzalez Chemes
- **Repo:** github.com/ignaciochemes/L2Ex
- **Workspace:** `c:\Users\Ignacio\Desktop\l2e\`
- **OS:** Windows — PowerShell only. Never `Add-Content`. Always `replace_string_in_file`.

## Stack

- Elixir ~> 1.16 / OTP 27
- ThousandIsland ~> 1.3 (TCP acceptors — `use ThousandIsland.Handler`)
- Ecto / PostgreSQL ~> 3.11
- Phoenix.PubSub (AOI broadcasting)
- ETS (item/skill/npc templates, configs)
- pbkdf2_elixir for password hashing (bcrypt FORBIDDEN on Windows)

## ThousandIsland State Shape

- `handle_info/2` → state is `{socket, state_map}`
- `handle_data/3` and `handle_connection/2` → state is plain `state_map`

## Current Status

- **Fase A (M1–M42):** Complete and pushed to main (commit c5d213c)
- **Next (Fase B):** M43 Private Store buy, M44 Siege, M45 Quests, M46 Geodata, M47 Augmentation, M48 Distributed nodes

## Key Files

- `lib/l2e/network/connection_handler.ex` — TCP connection GenServer, cipher, dispatch
- `lib/l2e/session/player_session.ex` — player state machine, packet handlers
- `lib/l2e/npc/spawn_table.ex` — NPC spawn registry
- `lib/l2e/zone/region.ex` — region GenServer, entity ownership, AOI
- `lib/l2e/warehouse/clan_warehouse.ex` — clan warehouse GenServer
- `lib/l2e/admin/command_handler.ex` — admin bypass command parser
- `lib/l2e/data/htm_cache.ex` — Agent-based HTML template cache

## Architecture Principles

- Every major entity is a supervised process (player, NPC, region, clan, party)
- No singleton managers, no global mutable state, no polling loops
- ETS for read-heavy shared data only
- Phoenix.PubSub for AOI/zone broadcasts
- Message passing for all cross-entity communication

## Gap Analysis Sessions

### 2026-05-22 — Full gap analysis (Fase B complete, M1–M48)

Requested by Ignacio. Deep inventory of L2E vs L2J Mobius CT0 Interlude.

**Findings summary:**
- L2E is ~42% coverage of L2J reference overall (honest assessment)
- Packet coverage: 86/215 client (~40%), 66/279 server (~24%)
- Skill effects: only 3/40 effect types implemented — biggest quality gap in the core loop
- Quests: 0 actual scripts; DB infrastructure only
- Endgame (Olympiad proper, Siege, Grand Bosses, SSQ, Clan Hall): ~0%
- Core gameplay loop (login → move → fight → level): ~90% solid

**Top 3 priorities identified:**
1. Skill effects (40 types, only 3 done) — blocks correct combat for all classes
2. Quests (500+ scripts, 0 done) — major content gap
3. Real geodata (stub) + Olympiad proper — endgame / competitive play

**Recommended M49–M55 scope documented in decision file.**

---

## Learnings

### 2026-05-23: Completed L2E vs L2J gap analysis. Key findings: L2E has 82/214 client packets decoded (38%), ~80/274 server packets encoded (~29%). Skill effects at 5/40+ types — biggest quality blocker. Quest content at 3/500+ scripts. Geodata is a permissive stub (always passable). 42 L2J manager singletons; L2E has OTP-native equivalents for ~7. 30 L2J zone types; L2E maps ~6. Missing entirely: Grand Bosses, Seven Signs, Manor system, Fishing, Dimensional Rift, Clan Hall Siege, Alliance. Top 3 priorities: Real Geodata (M55), Skill Effects expansion, Quest content batch.

### 2026-05-22 — Second Full Gap Analysis (M1–M42 confirmed baseline)

- **Actual packet count from code:** 51 client modules, 64 server modules — not 86/66 as estimated in previous session. The difference is ~35 packets that exist in plans but not yet in the file system.
- **Geodata remains the single highest architectural risk.** `can_see?/2` always returns `true`. Every AOI scoping decision, every aggro check, every ranged attack is running on false assumptions. Fixing this requires parsing `.l2j` binary format into ETS blocks — no shortcuts.
- **Data tables are at 10/43 (~23%).** The missing high-impact ones are: ExperienceData (XP curve at each level), PlayerTemplateData per level (stat tables), MultisellData (multisell NPC dialogs), MapRegionData (town identification), SpawnData (mass NPC population). Without SpawnData, the world is empty except for manual spawn calls.
- **Zone types: 5 concept-mappings out of 30 L2J types.** Missing RespawnZone (rebirth points), DamageZone (swamp/poison ground), FishingZone, JailZone, TownZone (for proper town rules), OlympiadStadiumZone.
- **Henna/Recipe/Augmentation: data tables loaded, UI flow 0%.** Three systems are "data-ready" but have no packet handlers for the actual player interaction (equip/remove/craft/augment). These are quick wins — 1-2 days each to complete.
- **Quest engine DSL is correct OTP.** 3 scripts vs 500+ in L2J. The blocker is content, not architecture. Need to prioritize populating quests in parallel with other work.
- **NPC AI hate list is single `target_pid`.** L2J uses a ranked `Map<Creature, Integer>` (hate values). Without this, NPCs always attack whoever last hit them, ignore taunts, and can't switch targets correctly. Hate list is M43 and should be considered a prerequisite for any content testing.
- **Overall honest coverage: ~38%** — functional for basic gameplay loop (login → move → fight → trade → level up) but missing all endgame systems, most content, and many quality-of-life features.

### 2026-05-22 — M46 Geodata stub + M48 Instance Zones
- `L2E.Config` does not exist in this codebase — use `Application.get_env(:l2e, key, default)` for runtime config values.
- Existing `do_teleport/2` private helper in `player_session.ex` handles region handoff correctly — reuse it for instance eject rather than duplicating teleport logic.
- `L2E.Instance.Supervisor` (DynamicSupervisor) must be started BEFORE `L2E.Instance.Manager` in the supervision tree because Manager calls Supervisor on init.
- Geodata stub: `priv_dir(:l2e)` gives the correct path at runtime; check with `File.dir?/1` to detect stub mode cleanly without crashing.
- `mix compile | Select-String "error"` producing no output = clean compile on Windows PowerShell.

### 2026-05-22 — M48 Instance Zone Architecture (detail)

- **`DynamicSupervisor` child spec for `Instance.Zone`**: use `{L2E.Instance.Zone, args}` where args is a keyword list; Zone's `start_link/1` must accept a keyword list and extract fields.
- **ETS registry in Manager**: table name `:instance_registry`, type `:set`, `:public`, `:named_table`. Two index directions: `{:party, party_id} => pid` and `{:instance, pid} => template_id`. Both needed for O(1) lookup in each direction.
- **Instance TTL**: `Process.send_after(self(), :instance_expired, ttl_ms)` in `Zone.init/1`. `handle_info(:instance_expired, state)` broadcasts `:instance_ejected` to all monitored player pids, then calls `DynamicSupervisor.terminate_child`.
- **Player monitor in Zone**: `Process.monitor(player_pid)` on join; `handle_info({:DOWN, ref, :process, pid, _}, state)` removes from player list. If list becomes empty after expiry grace, Zone can self-terminate.
- **Manager monitor on Zone pid**: `Process.monitor(instance_pid)` in Manager; `handle_info({:DOWN, ...})` removes both ETS entries for the crashed instance.
- **Supervision order is critical**: `Instance.Supervisor` must be a child BEFORE `Instance.Manager` in `application.ex` — Manager's `init/1` may call Supervisor immediately.
