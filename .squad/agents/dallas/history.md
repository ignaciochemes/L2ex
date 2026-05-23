# Dallas — Learnings & Project Knowledge

## Project

- **Project:** L2E — Lineage II Interlude rebuilt in Elixir/OTP
- **Owner:** Ignacio Gonzalez Chemes
- **Repo:** github.com/ignaciochemes/L2Ex
- **Workspace:** `c:\Users\Ignacio\Desktop\l2e\`
- **OS:** Windows — PowerShell only. Never `Add-Content`. Always `replace_string_in_file`.

## Stack

- Elixir ~> 1.16 / OTP 27
- ThousandIsland ~> 1.3 (TCP acceptors)
- Phoenix.PubSub (AOI zone broadcasting)
- ETS (NPC templates, skill definitions, item templates, config read-only data)

## Key Game System Files

- `lib/l2e/zone/region.ex` — Region GenServer (entity ownership, AOI, local broadcast)
- `lib/l2e/zone/zone_table.ex` — Zone/region registry
- `lib/l2e/npc/spawn_table.ex` — NPC spawn registry with admin_spawn/4
- `lib/l2e/combat/` — Combat resolver modules
- `lib/l2e/skills/` — Skill table, effect system
- `lib/l2e/session/player_session.ex` — Player state, handles movement/combat packets

## Current Status

- **Fase A (M1–M42):** Complete
  - M37: Karma item drop on PK death
  - M38: Ground item decay and corpse decay timers
  - M39: Soulshot/Spiritshot activation and auto-use
- **Next game systems:** M43 Private Store buy side, M44 Siege mechanics, M45 Quest system, M46 Geodata integration

## Architecture Principles (Game Systems)

- NPC AI: event-driven `handle_info/2` only — NEVER ai_loop/polling
- Timers: `Process.send_after/3` for respawn, buff expiry, leash
- Region owns entity list; AOI scoped to region PubSub topic
- Cross-region handoff: supervised transfer between region GenServers
- Java source in `L2J_Mobius_CT_0_Interlude/` is behavior reference ONLY

## Learnings

### M55-B — Zone Effects & Events (2026-05-23)
- Zone type parsing lives in `L2E.Zone.classify_type/1` (zone.ex), NOT in zone_table.ex — `to_zone/1` in zone_table.ex delegates to it. Extended there, not in zone_table.
- `@priority` in zone_table.ex controls which zone type wins when a point is in multiple zones. Updated to `[:peace, :no_pvp, :siege, :boss, :pvp, :damage, :swamp, :water, :other]`.
- `handle_zone_change/2` uses two-clause pattern match: first clause catches no-op (same zone), second handles real transitions. Avoids unnecessary PubSub broadcasts.
- `StatusUpdate` struct uses `:object_id` and `:attributes` fields — NOT `:obj_id`/`:updates`. Use the `Server.StatusUpdate.hp_mp/3` helper function for HP-only updates, matching all other call sites in player_session.ex.
- No `send_packet/2` helper exists in player_session.ex — always use `send(state.conn_pid, {:send_packet, pkt})`.
- Zone damage timer cancellation on zone exit: guard `state.zone_type in [:damage, :swamp]` prevents calling `Process.cancel_timer(nil)` when entering from a non-damage zone.
- `in_water` flag set inline in `handle_zone_change` return: `%{state | zone_type: new_zone, in_water: new_zone == :water}`.
- Zero compile errors after all edits; only pre-existing warnings unrelated to M55-B.

### M49-B — Skill Effects Phase 2 (2026-05-23)
- Added 10 new pure functions to `L2E.Skill.Effect`: `slow_factor/1`, `check_silence_lands?/2`, `apply_mana_burn/2`, `stat_modifier/3`, `apply_stat_mods/3`, `dot_tick_mp/2`, `apply_resurrection/2`, `cancel_count/1`.
- New state fields in PlayerSession: `slowed`, `slow_timer`, `silenced`, `silence_timer`, `stat_mods` — added after `toggle_skills` in the initial state map.
- Silence guard clause for `RequestMagicSkillUse` added before the peace-zone guard; pattern matches `%{silenced: true}`.
- Effect dispatch handlers added inside `case template.effect_type do` for `:slow`, `:silence`, `:mana_burn`, `:cancel` — all return the new state map to match the existing `new_state = case...` pattern (NOT `{:noreply, ...}` inline).
- `:mana_burn` uses `burned_mp = max(0.0, new_mp - mp_damage)` to avoid shadowing the outer `new_mp` binding (already has mp_cost deducted).
- `handle_info({:slow_expired})` and `handle_info({:silence_expired})` added before the catch-all `handle_info(msg, state)`.
- Zero compile errors after all edits.

### M45 — Class Advancement (2026-05-22)
- `~s(...)` sigil breaks if the interpolated string contains literal `()` — used `~s[...]` instead.
- ETS-backed tables (like ClassAdvancementTable) follow the exact same GenServer pattern as SkillLearnTable: `:ets.new` in `init/1`, `:public read_concurrency: true`, named via `name: __MODULE__`.
- Class change bypass dispatches via `handle_bypass/2` cond block; new clauses go before the `true ->` catch-all.
- `broadcast_user_info/1` already builds and sends UserInfo from state; no need for a separate helper — just call it with the updated state after class change.
- `SocialAction` struct uses `:object_id` (not `:obj_id`) — check packet defstruct carefully before use.
- Starting skills for a new class are fetched with `SkillLearnTable.get_learnable_skills(class_id, 1)` (min_level 1 = granted at class change).

### M47 — Quest State in PlayerSession (2026-05-22)

- **Always include `defp handle_packet(` prefix** when adding new packet handler clauses. Missing `defp` (writing just the pattern match inline) causes a compilation syntax error that can be subtle to locate.
- **Quest in-memory map** keyed by `quest_id` integer matches DB schema — no transformation needed between DB load and runtime state.

### M64 — MultiSell + M67 QuestList (2026-05-22)

- **Inventory API uses instance_id, not template_id** for removal. When removing by item_id (template), always add a new `remove_item_by_template/3` public API backed by `Enum.find` on `state.items`; do not call `remove_item/3` directly from the session with item_id.
- **`count_item/2`** is not built into Inventory — add it as a GenServer call that sums `inst.count || 1` over items matching `item_id`. Pattern mirrors `get_adena_count` in the same module.
- **`ItemList` defstruct has no `show_window` field** — the window-open byte is hardcoded `0::8` inside `encode/1`. Never pass `show_window:` as a struct key.
- **QuestList send placement:** insert after `ShortcutInit` in the EnterWorld handler, using the locally-bound `quests` variable (already loaded by `load_char_quests/1` earlier in the same handler). Filter `q.state == 1` for in-progress quests.
- **MultisellTable ETS key** is `list_id` integer; value is the full list map. Same `:named_table, :public, read_concurrency: true` pattern as all other data tables.
- **`load_char_quests/1`** should be called during `handle_continue(:load_character, ...)` alongside `load_char_skills` — not in a separate init step.
- **Quest bypass stub** using `NpcHtmlMessage{npc_object_id: 0, html: "..."}` is sufficient for MVP; actual quest engine (triggers, conditions, rewards) is a separate milestone.
- **`handle_cast({:quest_progress, ...}, state)` and `handle_cast({:quest_complete, ...}, state)`** are the correct cast shapes for external quest engine calls into player session — keeps quest logic out of the session process itself.

### M50 — Quest Engine DSL (2026-05-22)

- **New files created:**
  - `lib/l2e/quest/engine.ex` — Behaviour/macro `use L2E.Quest.Engine`; quest scripts implement `on_first_talk/2`, `on_talk/3`, `on_kill/3`, `on_complete/2`
  - `lib/l2e/quest/registry.ex` — ETS-backed `GenServer` (`@table :quest_registry`) mapping `{:by_quest_id, quest_id}` → module; `modules_for_kill/1` and `modules_for_npc/1` scan the table by NPC id
  - `lib/l2e/quest/handler.ex` — Pure dispatcher: `dispatch_kill/3` and `dispatch_talk/4` route events to registered quest modules, return updated quest maps
- **Files modified:**
  - `lib/l2e/application.ex` — Added `L2E.Quest.Registry` after `L2E.Data.OptionTable`, before `L2E.Geodata`
  - `lib/l2e/session/player_session.ex` — Replaced stub `Quest` cond branch in `handle_bypass/2` with `Quest.Handler.dispatch_talk/4` call; added `handle_cast({:npc_killed_for_quest, npc_template_id}, ...)` with DB persistence diff-check; added `handle_cast({:npc_killed_for_quest, _}, state)` fallback
- **ETS key format:** `{{:by_quest_id, quest_id}, module}` — two-element tuple key to allow multiple quests; lookup via `:ets.lookup(@table, {:by_quest_id, quest_id})`
- **Existing `Quest ` bypass was a cond branch** (not a separate function clause) — replaced in-place rather than adding a new pattern-matched head
- **Quest module list in `load_quests/0` is explicit** — no dynamic beam scanning; add modules manually as quest scripts are created

## FASE 4 — Complete (2026-05-23)

Commit 3c07e5f. Delivered M49-B (Skill Effects Phase 2): 8 new pure functions in `effect.ex`, silence guard + expiry handlers in `player_session.ex`, new state fields `slowed`/`slow_timer`/`silenced`/`silence_timer`/`stat_mods`. QA: 9/10 PASS.
