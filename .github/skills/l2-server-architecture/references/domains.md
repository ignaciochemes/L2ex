# Domain-Specific Design Rules

## Login Server

**Behavior**: Authenticate credentials, issue session keys, redirect to game server.

**OTP Design**:
```
LoginServer.Application
├── Ranch/ThousandIsland acceptor pool
├── LoginController (GenServer) — session key registry
├── GameServerRegistry (GenServer) — connected game servers
└── FloodProtector (ETS) — IP-based rate limiting
```
- Session keys stored in ETS (short TTL)
- Each login connection is an isolated handler process
- No shared mutable state between connections

---

## Game Server

**Behavior**: Root OTP application. Boots all subsystems.

```
GameServer.Application
├── WorldSupervisor
│   ├── RegionRegistry (Registry)
│   └── RegionSupervisor (DynamicSupervisor)
├── PlayerSupervisor (DynamicSupervisor)
├── NpcSupervisor (DynamicSupervisor)
├── DataTables (ETS owners)
│   ├── ItemTemplates
│   ├── NpcTemplates
│   └── SkillDefinitions
└── Phoenix.PubSub
```

---

## Packet Protocol Layer

**Behavior**: Decode raw TCP bytes into typed Elixir structs; route to handlers.

**Rules**:
- One decoder module per packet opcode
- Decoders are pure functions: `decode(binary) :: {:ok, struct} | {:error, reason}`
- Router is a plain function dispatch, not a GenServer (no state)
- Avoid giant `case opcode do` — use a map of `opcode => module`

**Example struct**:
```elixir
defmodule L2E.Packet.RequestAttack do
  defstruct [:target_id, :origin_x, :origin_y, :origin_z, :shift]
end
```

---

## Character State

**Behavior**: Stores all per-player data: position, hp/mp, stats, buffs, cooldowns, flags.

**OTP Design**: Single `GenServer` per online player.

- Registered in `Registry` by character id
- Inventory may be a sub-module (same process state) or a separate GenServer for large inventories
- Stats are derived/cached in process state; recomputed on equip/buff changes
- All mutations go through the player GenServer — no external writes

---

## Combat Engine

**Behavior**: Handle attack requests, resolve damage, apply effects, broadcast results.

**Rules**:
- No global combat tick
- Attack flow: attacker sends message → target GenServer resolves → PubSub broadcast
- Auto-attack: `Process.send_after(self(), :auto_attack, interval)` inside player GenServer
- Critical hits, miss calculations: pure functions in `L2E.Combat.Calculator`
- Death: player GenServer transitions to `:dead` state; sends respawn timer

---

## Skill Engine

**Behavior**: Cast skills with cast times, reuse timers, effects (buff/debuff/damage).

**Rules**:
- Skill definitions loaded from ETS at boot
- Each active buff is a `{skill_id, expiry_at}` entry in player state
- Cooldown: `Process.send_after(self(), {:cooldown_expired, skill_id}, ms)`
- AoE skills: player GenServer queries region for nearby pids, sends damage message to each

---

## Movement Engine

**Behavior**: Players and NPCs move; positions sync to nearby players.

**Rules**:
- Movement validation (geodata check) is a pure function call
- Position stored in entity's GenServer state
- On move: update region membership if cell boundary crossed (region handoff)
- Broadcast `:move` event to AOI via PubSub region topic

---

## Geodata

**Behavior**: Block/allow movement between cells. Check line-of-sight.

**Rules**:
- Loaded from binary files at boot into ETS (read-only after boot)
- Lookup is a pure function: `Geodata.can_move?(from, to) :: boolean`
- For very large worlds, consider a NIF-backed lookup table

---

## Pathfinding

**Behavior**: Compute walkable paths for NPCs (and player-assisted movement).

**Rules**:
- Never run A* inside a GenServer synchronously
- Preferred: Rust NIF via `Rustler` for sub-millisecond paths
- Acceptable: `Task.async/await` with timeout for non-critical paths
- Cache frequent NPC patrol paths in ETS

---

## AI System

**Behavior**: NPCs react to players entering range, being attacked, losing targets.

**Rules**:
- Each NPC GenServer IS its own AI controller (no separate AI process needed)
- State machine: `:idle | :walking | :chasing | :attacking | :returning`
- Transitions triggered by messages from region process or combat system
- Hibernate idle NPCs: `{:noreply, state, :hibernate}`
- No AI polling loop; no `ai_tick` message broadcast

---

## Clan System

**Behavior**: Clan membership, ranks, skills, wars.

**OTP Design**:
```
ClanServer (GenServer, registered by clan_id)
  state: members map, rank map, skills, war list
```
- Membership changes broadcast via `Phoenix.PubSub` on `"clan:#{clan_id}"`
- Clan data persisted to DB asynchronously; in-memory state is source of truth while online

---

## Party System

**Behavior**: Group of players sharing XP, seeing each other's HP bars.

**OTP Design**: `GenServer` per active party, registered by party id.
- Members subscribe to `"party:#{party_id}"` PubSub topic
- HP/MP updates sent to topic (not to each member individually)
- Party disbands → supervisor terminates GenServer

---

## Inventory

**Behavior**: Player holds items; equip/unequip affects stats.

**Rules**:
- For most players: inventory is a map inside the player GenServer state
- For extreme cases (10k+ items): separate GenServer under the player's supervisor
- Item templates fetched from ETS, never stored per-player
- Equip triggers stat recalculation (pure function) in the player GenServer

---

## Quest Engine

**Behavior**: Players accept, progress, and complete quests with state tracking.

**Rules**:
- Quest state stored inside the player GenServer: `%{quest_id => quest_state}`
- Quest logic modules are pure functions: `QuestHandler.on_kill(quest_state, npc_id) :: new_state`
- No quest manager process; quest handlers are plain modules

---

## Olympiad

**Behavior**: 1v1 or team PvP tournament with matchmaking and isolated arenas.

**OTP Design**:
```
OlympiadSupervisor
├── MatchmakingServer (GenServer) — queue and pairing
└── MatchSupervisor (DynamicSupervisor)
    └── MatchInstance (GenServer, one per active match)
```
- Each match is fully isolated; crash does not affect other matches
- Match result written to DB; supervisor terminates instance after

---

## Siege System

**Behavior**: Castle sieges with attacker/defender factions, control points.

**OTP Design**:
```
SiegeSupervisor
└── SiegeInstance (GenServer, one per active siege)
      ├── owns: castle state, control point states, participant lists
      └── publishes to: "siege:#{castle_id}" PubSub topic
```
- Scheduled via `Process.send_after` for siege start/end phases
- Isolated subtree: a crash in one siege does not affect others

---

## Zone Engine

**Behavior**: Zones apply effects (peace zone, combat zone, PvP zone, poison zone).

**OTP Design**:
- Zone definitions loaded at boot into ETS
- Region GenServer checks zone membership on entity enter
- Zone effects applied as messages to entity GenServer (e.g., `:entered_poison_zone`)
- No per-zone process unless zone has mutable state (e.g., dynamic event zone)
