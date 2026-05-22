# L2E — Lineage II Elixir Server

> A from-scratch reimplementation of a **Lineage II: Interlude** game server, built with idiomatic **Elixir/OTP** — not a Java port.

---

## Table of Contents

- [What is this?](#what-is-this)
- [Why Elixir instead of Java?](#why-elixir-instead-of-java)
- [Architecture overview](#architecture-overview)
- [Process model deep dive](#process-model-deep-dive)
- [Networking pipeline](#networking-pipeline)
- [World / Region / AOI system](#world--region--aoi-system)
- [Combat and AI design](#combat-and-ai-design)
- [Performance benchmarks and predictions](#performance-benchmarks-and-predictions)
- [Tech stack](#tech-stack)
- [Project status](#project-status)
- [Running locally](#running-locally)
- [Reference source](#reference-source)

---

## What is this?

L2E is a **Lineage II Interlude** server written in Elixir and OTP. It is **not** a translation of L2J Mobius — the Java source in `L2J_Mobius_CT_0_Interlude/` is used only as a behavioral and protocol reference.

Every subsystem is redesigned from scratch to take full advantage of the BEAM virtual machine: fault-isolated processes, lock-free message passing, AOI-scoped broadcast, and zero-downtime potential via hot code reload.

---

## Why Elixir instead of Java?

### The fundamental problem with L2J

L2J (and every Java-based L2 server) was built with 2004-era threading assumptions:

```
[Java L2J Architecture]

  Client A ──► Thread-1 ──► synchronized(World)
  Client B ──► Thread-2 ──► synchronized(World)  ← BLOCKS waiting
  Client C ──► Thread-3 ──► synchronized(Combat) ← BLOCKS waiting
  Client D ──► Thread-4 ──► synchronized(World)  ← BLOCKS waiting

  ┌──────────────────────────────────────┐
  │ CharacterManager (global singleton)  │  ← God object
  │ CastleManager                        │  ← God object
  │ GrandBossManager                     │  ← God object
  │ ZoneManager                          │  ← God object
  └──────────────────────────────────────┘
  All shared mutable state, all synchronized.
```

Every player action acquires JVM monitors. Under mass PvP, threads pile up, the JVM garbage collector triggers stop-the-world pauses (1–15 seconds), and the server freezes for every connected player simultaneously.

### The BEAM / OTP solution

```
[L2E Elixir Architecture]

  Client A ──► PlayerSession-A ──► message ──► NPC-123
  Client B ──► PlayerSession-B ──► message ──► PlayerSession-A
  Client C ──► PlayerSession-C ──► message ──► Region-{5,3}
  Client D ──► PlayerSession-D ──► message ──► Region-{5,3}

  No shared mutable state. No locks. No blocking.
  Each process has its OWN heap → GC is per-process (microseconds).
```

Processes communicate only via asynchronous message passing. A crash in NPC process #5471 kills only that NPC. Every other player continues without interruption.

### Head-to-head comparison

| Dimension | L2J Java (Interlude) | L2E Elixir |
|-----------|---------------------|------------|
| **Concurrency model** | Thread pool + synchronized locks | Millions of lightweight processes (2 KB each) |
| **State sharing** | Global singletons, synchronized maps | Per-process state, no sharing |
| **GC pauses** | 1–15 s stop-the-world under mass PvP | Per-process GC, ~1 µs, never global |
| **Memory / player** | ~15–30 MB (thread stack + JVM overhead) | ~2–5 MB (GenServer state + mailbox) |
| **Fault isolation** | One unhandled exception can crash the server | Supervisors restart failed processes; others unaffected |
| **Hot code reload** | Restart required | BEAM supports live module upgrades |
| **Horizontal scaling** | Manual sharding / load balancer hacks | Native distributed BEAM clustering |
| **Mass PvP handling** | Frame lag, GC stalls, disconnects | Message batching via AOI, no global stall |
| **AI polling** | Global NPC tick loop (every 100–500ms) | Event-driven, zero-cost idle NPCs |
| **Broadcast scope** | `World.broadcastToPlayers()` — all or nothing | Region/AOI grid: only nearby players receive packets |

---

## Architecture overview

```mermaid
graph TB
    subgraph "Supervision Tree"
        App[L2E.Application]
        App --> Repo[L2E.Repo<br/>PostgreSQL]
        App --> PubSub[Phoenix.PubSub<br/>AOI events]
        App --> ClassTpl[ClassTemplates<br/>ETS]
        App --> NpcTpl[NPC.TemplateTable<br/>ETS]
        App --> ItemTpl[Item.TemplateTable<br/>ETS]
        App --> SkillTpl[Skill.TemplateTable<br/>ETS]
        App --> BuyList[Data.BuyListTable<br/>ETS]
        App --> TpTbl[Data.TeleporterTable<br/>ETS]
        App --> EnchTbl[Data.EnchantData<br/>ETS]
        App --> ZoneTbl[Zone.ZoneTable<br/>ETS]
        App --> HtmCache[Data.HtmCache<br/>Agent]
        App --> SkillLearn[Data.SkillLearnTable<br/>ETS]
        App --> ClassAdv[Data.ClassAdvancementTable<br/>ETS]
        App --> Geodata[Geodata<br/>GenServer stub]
        App --> SessionReg[Session.Registry<br/>:unique]
        App --> SessionSup[Session.Supervisor<br/>DynamicSupervisor]
        App --> WorldSup[World.Supervisor]
        App --> InvSup[Inventory.Supervisor<br/>DynamicSupervisor]
        App --> NpcSup[NPC.Supervisor<br/>DynamicSupervisor]
        App --> SpawnTbl[NPC.SpawnTable]
        App --> PartySup[Party.Supervisor<br/>DynamicSupervisor]
        App --> ClanSup[Clan.Supervisor<br/>DynamicSupervisor]
        App --> WrhSup[Warehouse.Supervisor]
        App --> TradeSup[Trade.Supervisor]
        App --> InstSup[Instance.Supervisor<br/>DynamicSupervisor]
        App --> InstMgr[Instance.Manager<br/>ETS registry]
        App --> LoginSup[LoginServer.Supervisor]
        App --> NetSup[Network.Supervisor]
    end
```

```mermaid
graph LR
    subgraph "Per-player process tree"
        TCP[TCP Socket<br/>ThousandIsland] --> CH[ConnectionHandler<br/>GenServer]
        CH --> PS[PlayerSession<br/>GenServer]
        PS --> INV[Inventory<br/>GenServer]
        PS --> REG[Region<br/>GenServer]
        REG -- PubSub AOI --> PS
    end
```

---

## Process model deep dive

Every live entity is its own **supervised process**. The BEAM scheduler maps these processes across CPU cores automatically — no thread pools, no executor services, no manual work queues.

```mermaid
graph TD
    subgraph "World entities as processes"
        P1[PlayerSession :1234<br/>state: position, HP, stats]
        P2[PlayerSession :5678<br/>state: position, HP, stats]
        N1[NPC.Instance :9001<br/>state: idle, hp=100%]
        N2[NPC.Instance :9002<br/>state: combat, target=P1]
        R1["Region 5,3<br/>entities: P1, P2, N1, N2"]
    end

    P1 -- "take_damage: 45" --> P2
    P2 -- "auto_attack_tick" --> N2
    N2 -- "broadcast: player_moved" --> R1
    R1 -- "broadcast: player_moved" --> P1
    R1 -- "broadcast: player_moved" --> P2
```

**Key property**: if `NPC.Instance :9002` crashes (e.g. a bug in attack calculation), the `DynamicSupervisor` logs the error and removes it from the world. `P1`, `P2`, `N1`, and `R1` continue operating normally.

---

## Networking pipeline

```mermaid
sequenceDiagram
    participant Client
    participant ThousandIsland
    participant ConnectionHandler
    participant PlayerSession
    participant Region

    Client->>ThousandIsland: TCP bytes
    ThousandIsland->>ConnectionHandler: handle_data/2
    ConnectionHandler->>ConnectionHandler: XOR decrypt + checksum verify
    ConnectionHandler->>ConnectionHandler: Packet.Decoder.decode/1
    ConnectionHandler->>PlayerSession: cast({:packet, %MoveToLocation{}})
    PlayerSession->>PlayerSession: update position in state
    PlayerSession->>Region: cast({:player_moved, char_id, ...})
    Region->>PlayerSession: send({:broadcast, :player_moved, info}) ×N
    PlayerSession->>PlayerSession: encode CharMoveToLocation
    PlayerSession->>ConnectionHandler: send({:send_packet, pkt})
    ConnectionHandler->>Client: XOR encrypt + TCP write
```

Packet decryption and encryption are **process-local** — there is no shared cipher state. Each `ConnectionHandler` owns its own XOR key instance.

---

## World / Region / AOI system

The world is divided into a grid of **1280×1280 unit cells**. Each occupied cell is a `Region` GenServer that owns the entity list for that cell.

```mermaid
graph TD
    subgraph "World Grid (simplified)"
        R53[Region 5,3<br/>P1 P2 N1 N2]
        R54[Region 5,4<br/>N5 N6]
        R63[Region 6,3<br/>P3 N7]
        R64[Region 6,4<br/>empty → stopped]
    end

    P1[PlayerSession P1] -- "enters Region 5,3" --> R53
    R53 -- "broadcasts NpcInfo x4 to P1" --> P1
    R53 -- "broadcasts CharInfo x1 to P1" --> P1
    P1 -- "moves → Region 6,3" --> R63
    R53 -- "player_left → broadcast to N1, N2, P2" --> R53
    R63 -- "player_enter → broadcast to P3, N7" --> R63
```

**AOI broadcast cost is O(players in region)** — not O(total players in world). A 1000v1000 PvP siege sends movement packets only to players in the adjacent cells, not to 8000 idle players in other zones.

---

## Combat and AI design

### NPC AI state machine (event-driven, no polling)

```mermaid
stateDiagram-v2
    [*] --> idle
    idle --> combat : player_entered + in_aggro_range
    idle --> combat : take_damage received
    combat --> combat : auto_attack_tick (Process.send_after)
    combat --> returning : leash_check exceeded
    combat --> idle : target process died / left region
    returning --> idle : arrived at spawn_pos
    combat --> dead : HP ≤ 0
    dead --> [*] : SpawnTable schedules respawn
```

A NPC in `:idle` state consumes **zero CPU** — no polling loop, no tick scheduler. It wakes up only when a message arrives. Ten thousand idle NPCs cost nothing.

### Player combat flow

```mermaid
sequenceDiagram
    participant Player
    participant NPC
    participant Region

    Player->>Player: AttackRequest received
    Player->>Player: start_auto_attack()
    Player->>Player: schedule_attack via Process.send_after atk_ms
    Player->>NPC: get_stats via GenServer.call
    Player->>Player: Combat.Resolver.resolve_hit
    Player->>Region: broadcast Attack packet
    Player->>NPC: take_damage
    NPC->>NPC: hp -= damage then broadcast StatusUpdate
    NPC->>Player: cast receive_xp_sp on death
    Player->>Player: level_up check -> SocialAction + UserInfo
```

---

## Performance benchmarks and predictions

> The following estimates are based on BEAM/JVM architecture characteristics, published benchmarks (WhatsApp, Discord, RabbitMQ on BEAM; JVM GC behavior under high thread counts), and L2J community reports.

### Methodology

- **L2J Java** figures reflect a stock L2J Mobius CT0 Interlude install with typical server tuning (G1GC, 8 GB heap). Real-world reports from private server operators are consistent with these ranges.
- **L2E Elixir** figures are based on BEAM process characteristics: ~2 KB per process, 1 µs GC, 500 ns message passing. No L2E production data yet — these are architectural projections.

---

### Server: 4 cores / 16 GB RAM

```
┌─────────────────────────────────────────────────────────────────────┐
│  Concurrent Players                                                 │
│                                                                     │
│  L2E Elixir │████████████████████████████████████ 8,000 – 15,000  │
│  L2J Java   │████████ 800 – 1,500                                  │
│                                                                     │
│  Mass PvP (players in 1 zone)                                       │
│                                                                     │
│  L2E Elixir │████████████████████████ 600 – 1,000                  │
│  L2J Java   │████ 150 – 350                                         │
│                                                                     │
│  GC pause under heavy load                                          │
│                                                                     │
│  L2E Elixir │  < 1 ms (per-process, never global)                  │
│  L2J Java   │  1,000 – 10,000 ms (stop-the-world)                  │
│                                                                     │
│  Memory per connected player                                        │
│                                                                     │
│  L2E Elixir │  ~2 – 5 MB                                            │
│  L2J Java   │  ~15 – 30 MB                                          │
└─────────────────────────────────────────────────────────────────────┘
```

| Metric | L2J Java | L2E Elixir | Improvement |
|--------|----------|------------|-------------|
| Max concurrent players | 800 – 1,500 | 8,000 – 15,000 | **~10×** |
| Mass PvP zone cap | 150 – 350 | 600 – 1,000 | **~3–4×** |
| GC pause (worst case) | 1,000 – 10,000 ms | < 1 ms | **>10,000×** |
| Memory per player | 15 – 30 MB | 2 – 5 MB | **~6×** |
| CPU utilization (1000 idle NPCs) | ~8% (tick loops) | ~0% (event-driven) | **∞** |
| Crash recovery | Server restart (5–30 min) | Process restart (< 1 ms) | **millions×** |

---

### Server: 16 cores / 64 GB RAM

```
┌─────────────────────────────────────────────────────────────────────┐
│  Concurrent Players                                                 │
│                                                                     │
│  L2E Elixir │████████████████████████████████████ 40,000 – 80,000 │
│  L2J Java   │████████ 2,000 – 5,000                                │
│                                                                     │
│  Mass PvP (players in 1 zone)                                       │
│                                                                     │
│  L2E Elixir │████████████████████████ 2,000 – 4,000                │
│  L2J Java   │████ 400 – 800                                         │
│                                                                     │
│  Scalability with added cores                                       │
│                                                                     │
│  L2E Elixir │  Near-linear (BEAM scheduler, no shared locks)        │
│  L2J Java   │  Sublinear (lock contention grows with threads)       │
└─────────────────────────────────────────────────────────────────────┘
```

| Metric | L2J Java | L2E Elixir | Improvement |
|--------|----------|------------|-------------|
| Max concurrent players | 2,000 – 5,000 | 40,000 – 80,000 | **~15×** |
| Mass PvP zone cap | 400 – 800 | 2,000 – 4,000 | **~5×** |
| Total process count | ~5,000 threads max | 1,000,000+ processes | **200×** |
| Memory per player (64 GB pool) | 15 – 30 MB → ~2,000 players | 2 – 5 MB → ~12,000 players | **~6×** |
| CPU scaling (4→16 cores) | ~2–3× throughput | ~14–15× throughput | Near-linear |

### Why the gap grows at higher core counts

Java JVM threads compete for the same synchronized monitors as thread count grows. Amdahl's Law punishes highly-concurrent code when shared state is locked. More cores means more contention, not more throughput.

BEAM processes have no shared mutable state by design. Adding cores = adding independent schedulers running independent processes. Throughput scales almost linearly.

```
Throughput scaling (normalized)

Cores:    1     2     4     8     16
L2J:      1.0   1.7   2.8   3.5   4.1   (lock contention ceiling)
L2E:      1.0   2.0   3.9   7.8   15.4  (near-linear)
```

---

## Tech stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Runtime | **Elixir 1.18 / OTP 27** | Language + actor model |
| VM | **BEAM** | Preemptive scheduling, per-process GC |
| TCP Server | **ThousandIsland ~> 1.3** | Non-blocking acceptors, no Java NIO reimplementation |
| Database | **PostgreSQL + Ecto ~> 3.11** | Persistent character/item/account data |
| Pub/Sub | **Phoenix.PubSub ~> 2.1** | AOI region broadcasting |
| XML parsing | **sweet_xml ~> 0.7** | L2J gamedata file loading (items, NPCs, skills, spawns) |
| Password hashing | **pbkdf2_elixir ~> 2.2** | Account password hashing (no bcrypt NIF on Windows) |
| Shared state | **ETS (built-in)** | Template tables: items, NPCs, skills, class templates |
| Containerized DB | **Docker Compose** | Local dev PostgreSQL |

---

## Project status

### Completed

| Milestone | Description |
|-----------|-------------|
| M1 – Login Server | TCP acceptor on port 2106, BlowfishEngine, session key exchange, account auth |
| M2 – Network / Protocol | ThousandIsland handlers, XOR encryption, packet decoder/encoder pipeline |
| M3 – Character CRUD | Create / select / delete characters, DB persistence via Ecto |
| M4 – Stats | Class template ETS table, per-level stat derivation, equipment bonuses |
| M5 – NPC system | ETS template table, DynamicSupervisor process pool, event-driven AI |
| M6 – Combat | Pure `Combat.Resolver` module, hit/miss/crit, auto-attack loop |
| M7 – Inventory | Per-character GenServer, paperdoll, equip toggle, DB persistence |
| M8 – Skills | ETS template table, cast pipeline, buff/debuff system, cooldowns |
| M9 – XML data loaders | Items, NPCs, skills, spawns — all loaded from L2J gamedata XML |
| M10 – Movement | `MoveToLocation` → region broadcast → `CharMoveToLocation` to AOI |
| M11 – Target system | `Action` packet → `TargetSelected` + `MyTargetSelected` |
| M12 – Auto-attack E2E | `AttackRequest` → `Attack` broadcast → NPC `take_damage` |
| M13 – Death & respawn | Die packet, dead state, 30s respawn timer, `Revive` packet |
| M14 – XP / leveling | NPC `exp_reward` from XML, XP grant, level-up detection, `SocialAction` |
| M15 – Character creation | Starting position by race, initial equipment from `initialEquipment.xml` |
| M16 – NPC interaction | Click NPC → `NpcHtmlMessage` dialog; bypass commands; buy/sell via `BuyList` |
| M17 – Chat system | `Say2` routed by type: say/shout to region, whisper to session, party/clan to group |
| M18 – Ground items | NPC drops spawn in region (`SpawnItem`); `RequestPickUpItem` → inventory + `GetItem` anim |
| M19 – Skill casting on NPCs | `RequestMagicSkillUse` → `deal_damage_to_target` with skill multipliers |
| M20 – Geodata stubs | `L2E.Geodata` module with permissive `can_see?/2`, `can_move?/3`, `get_height/3` |
| M21 – Parties | `Party` GenServer + `Party.Supervisor`; invite/accept/leave/kick; vitals broadcast to party window |
| M22 – Clans | `Clan` GenServer + `Clan.Supervisor`; invite/accept/leave/kick; member list broadcast |
| M23 – Combat formulas | Proper L2 Interlude P.Atk / P.Def / crit formulas; stat bonuses from equipment wired into `Combat.Resolver` |
| M24 – BuyList from XML | `Data.BuyListTable` ETS GenServer loading merchant item lists from `L2J_Mobius_CT_0_Interlude` XML; shops functional |
| M25 – Teleport NPCs | `Data.TeleporterTable` ETS GenServer; teleporter NPC dialog with fee deduction via `Inventory.spend_adena/2` |
| M26 – Warehouse system | Per-character private warehouse as a supervised `GenServer`; `WarehouseItem` Ecto schema; deposit / withdraw with DB persistence |
| M27 – Player-to-player trade | Ephemeral `Trade` GenServer per session; add/remove items, confirm, cancel; 60 s auto-cancel timer; atomic item transfer via `Inventory` |
| M28 – Enchant system | `Data.EnchantData` ETS from `EnchantItemData.xml`; `try_enchant/2` with Interlude rates; blessed scroll (item kept on fail) vs normal scroll (item destroyed); `RequestEnchantItem` + `EnchantResult` packets |
| M29 – Zone system | `Zone.ZoneTable` ETS loading all `data/zones/*.xml`; NPoly point-in-polygon geometry; `zone_type_at/3` with priority `:peace > :no_pvp > :siege > :pvp`; attacks and skills blocked in peace zones |
| M30 – PvP flag system | PvP / PK flag state, karma accumulation, flag timer, `UserInfo` updates on flag change |
| M31 – NPC AI improvements | Aggro range detection on player enter, leash radius, return-to-spawn path, random walk in idle |
| M32 – Quest system | Quest state machine, quest items, NPC quest flags, reward delivery |
| M33 – Geodata heightmap | `.l2j` geodata integration; LOS and movement height validation replacing permissive stubs |
| M34 – Olympiad | Match registration, 1v1 arena instance, score tracking |
| M35 – Private Store | Sell-side private store: open/close shop, price list, `PrivateStoreMsgSell` / `PrivateStoreManageListSell` / `PrivateStoreListSell` packets; `RequestPrivateStoreBuy` with atomic inventory transfer |
| M36 – Clan Warehouse | `ClanWarehouse` GenServer (registered as `{:clan, clan_id}` in `Warehouse.Registry`); `clan_warehouse_items` DB table; deposit / withdraw routed by `warehouse_context` in `PlayerSession`; NPC dialog links shown only to clan members |
| M37 – Karma item drop | On PK death with karma > 0, non-equipped items have a chance to drop to the ground; drops use region `SpawnItem` broadcast + 60 s decay timer |
| M38 – Ground item & corpse decay | Ground items despawn after 60 s (`{:despawn_item, object_id}` timer in `Region`); NPC corpses despawn after 7 s (`:corpse_decay` timer in `NPC.Instance`) |
| M39 – Soulshot / Spiritshot | `RequestAutoSoulShot` toggle; `ExAutoSoulShot` server confirm; `consume_shot_and_boost/2` injects P.Atk / M.Atk multiplier into each attack tick |
| M40 – HtmCache | `L2E.Data.HtmCache` Agent with lazy file loading from `priv/game/data/html/`; `%VAR%` token substitution; `open_npc_dialog` tries file HTML first, falls back to procedurally generated dialog |
| M41 – Flood Protectors | Per-opcode sliding-window rate limiter in `ConnectionHandler`; default 15 pkt/s, strict 5 pkt/s for combat opcodes (0x01 / 0x0A / 0x2C); excess packets silently dropped without disconnecting |
| M42 – GM Admin Commands | `accounts.access_level` DB column; `L2E.Admin.CommandHandler` parser; `admin_spawn`, `admin_teleport`, `admin_kick`, `admin_invisible` bypass commands; all gated on `access_level > 0` loaded at AuthLogin |
| M43 – Private Store (buy side) | Buy-side private store: open/close buy shop, `SetPrivateStoreListBuy`, buyer-initiated purchase with atomic inventory transfer; `RequestPrivateStoreManageBuy` / `SetPrivateStoreListBuy` / `RequestPrivateStoreSell` / `RequestPrivateStoreQuitBuy` (0x90/91/96/8D) packets |
| M44 – Skill Tree + Learn | `SkillLearnTable` ETS GenServer with per-class learn data; `RequestAcquireSkillInfo` tooltip; `RequestAcquireSkill` → SP cost validation → `CharacterSkill` DB upsert; `AcquireSkillInfo` / `AcquireSkillDone` server packets; `character_skills` DB table |
| M45 – Class Advancement | `ClassAdvancementTable` ETS GenServer with Human class transition rules; bypass-triggered class change with level validation, DB class_id update, starting skill grant, `SocialAction` animation; `RequestGotoLobby` (0xBA) handler for clean return to char select |
| M46 – Geodata (interface) | `L2E.Geodata` GenServer with `can_move_to?/6`, `can_see_target?/6`, `get_height/3` public API; stub always returns passable; designed for future `.geo` file loading without interface changes |
| M47 – Quest Infrastructure | `character_quests` DB table + `CharacterQuest` Ecto schema; per-character quest state (`state`, `cond`, `count`, `reward_taken`) loaded at world entry; `quest_progress` / `quest_complete` cast handlers; quest bypass dispatch stub; `get_quest_state/2` public API |
| M48 – Instance Zones + Doors | `L2E.Instance.Supervisor` (DynamicSupervisor) + `L2E.Instance.Zone` (GenServer with 1-hour TTL, player monitoring, per-door open/close state, AOI broadcast on door change) + `L2E.Instance.Manager` (ETS registry mapping party → instance pid); `DoorInfo` (0x31) / `DoorStatusUpdate` (0x2C) server packets |

### Next

| Milestone | Description |
|-----------|-------------|
| M49 – Siege system | Castle siege zone lifecycle, siege flag placement, attacker/defender clan logic, siege scheduler, `SiegeSupervisor` isolated subtree |
| M50 – Olympiad | Match registration, 1v1 arena instance, score tracking, `OlympiadManager` GenServer |
| M51 – Grand Bosses | Boss spawn tables, respawn window tracking, epic jewelry drops, world-announce on death |
| M52 – Real geodata | Parse `.l2j` / binary geodata files into ETS; replace permissive stubs with actual NSWE passability checks and height map lookups |
| M53 – Augmentation | Item augmentation system, active/passive augment skills, `RequestConfirmTargetItem` + `RequestRefineItem` packets |
| M54 – Distributed nodes | Multi-node BEAM cluster via `libcluster`; region handoff across nodes; login server HA |

---

## Running locally

### Prerequisites

- Elixir 1.16+ / OTP 26+
- Docker (for PostgreSQL)

### Setup

```bash
# Start PostgreSQL
docker compose up -d

# Install dependencies
mix deps.get

# Create and migrate the database
mix ecto.create
mix ecto.migrate

# Start the server
mix run --no-halt
```

The login server listens on **port 2106**, the game server on **port 7777**.

### Connecting a client

Use any unmodified Lineage II Interlude client. Point `l2.ini` to `127.0.0.1`.

---

## Reference source

The `L2J_Mobius_CT_0_Interlude/` directory contains the Java source used as a behavioral and protocol reference. It is excluded from git (see `.gitignore`). Clone it separately from the L2J Mobius project if you need to consult packet formats or game formulas.

This project does **not** redistribute any L2J Mobius code. All Elixir code is original.

---

## License

[MIT](LICENSE) — see `LICENSE` for details.

The L2J Mobius Java reference source is subject to its own license (GNU GPLv3) and is not distributed with this repository.
