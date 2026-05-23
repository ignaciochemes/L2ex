# Work Routing

How to decide who handles what.

## Routing Table

| Work Type | Route To | Examples |
|-----------|----------|----------|
| OTP architecture, supervision trees, process design | Ripley | Region GenServer ownership, entity supervision, fault isolation design |
| Code review, anti-Java-porting audit | Ripley | Review any PR, check for ported patterns, scope decisions |
| Milestone planning, "what to build next" | Ripley | Deciding M43–M48 priorities, architectural trade-offs |
| Combat systems, formulas, PvP/PK | Dallas | Attack resolution, damage calc, critical hits, miss/dodge |
| NPC AI, aggro, leash, respawn | Dallas | Event-driven AI, patrol, attack radius, AI state machine |
| Skills, buffs, debuffs, cooldowns | Dallas | SkillTable ETS, effect application, buff expiry timers |
| Movement, position, geodata | Dallas | Character movement, region handoff, geodata path checks |
| Zone/region systems, AOI | Dallas | Region GenServer, visibility lists, nearby entity queries |
| Packet codec, client/server packets | Lambert | Decoder/encoder structs, opcode dispatch, packet structs |
| TCP pipeline, connection lifecycle | Lambert | ConnectionHandler, ThousandIsland callbacks, cipher state |
| Encryption/decryption, session crypt | Lambert | BlowfishEngine port, NewCrypt key exchange, cipher in/out |
| Flood protection, rate limiting | Lambert | Per-connection packet counters, opcode strict limits |
| Ecto schemas, migrations | Parker | DB schema design, changesets, add_column migrations |
| Inventory, warehouse persistence | Parker | Item CRUD, character_items table, warehouse_items table |
| Character, account, clan DB | Parker | accounts, characters, clans tables; Repo queries |
| DB optimization, indexes | Parker | Query analysis, index design, batch operations |
| ExUnit tests, property tests | Ash | unit tests for GenServers, StreamData property tests |
| Edge case analysis, test scenarios | Ash | Find gaps in combat logic, overflow edge cases |
| Integration tests, regression | Ash | End-to-end packet flow tests, scenario verification |
| Session logging | Scribe | Automatic — never needs routing |
| Work queue, backlog monitor | Ralph | Issue scanning, PR status, keep-alive |
| Sub-class system, class switching | Bishop | Sub-class state, SubClass packet, class restrictions |
| Duel system, ExDuel* packets | Bishop | DuelManager, 1v1/party duels, match lifecycle |
| Olympiad system, hero selection | Bishop | OlympiadManager, match instancing, ExOlympiad* packets |
| Siege of castles | Bishop | SiegeManager, attacker/defender reg, siege guards, SiegeInfo packets |
| Grand Bosses (Baium, Antharas, etc.) | Bishop | Boss state persistence, boss AI, respawn timers |
| Pets & Summons, Pet AI | Bishop | Pet GenServer, follow AI, PetInfo packets |
| Seven Signs (SSQ) | Bishop | Festival cycle, seal competition, SSQStatus packet |

## Issue Routing

| Label | Action | Who |
|-------|--------|-----|
| `squad` | Triage: analyze issue, assign `squad:{member}` label | Lead |
| `squad:{name}` | Pick up issue and complete the work | Named member |

### How Issue Assignment Works

1. When a GitHub issue gets the `squad` label, the **Lead** triages it — analyzing content, assigning the right `squad:{member}` label, and commenting with triage notes.
2. When a `squad:{member}` label is applied, that member picks up the issue in their next session.
3. Members can reassign by removing their label and adding another member's label.
4. The `squad` label is the "inbox" — untriaged issues waiting for Lead review.

## Rules

1. **Eager by default** — spawn all agents who could usefully start work, including anticipatory downstream work.
2. **Scribe always runs** after substantial work, always as `mode: "background"`. Never blocks.
3. **Quick facts → coordinator answers directly.** Don't spawn an agent for "what port does the server run on?"
4. **When two agents could handle it**, pick the one whose domain is the primary concern.
5. **"Team, ..." → fan-out.** Spawn all relevant agents in parallel as `mode: "background"`.
6. **Anticipate downstream work.** If a feature is being built, spawn the tester to write test cases from requirements simultaneously.
7. **Issue-labeled work** — when a `squad:{member}` label is applied to an issue, route to that member. The Lead handles all `squad` (base label) triage.
