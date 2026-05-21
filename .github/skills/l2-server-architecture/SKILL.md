---
name: l2-server-architecture
description: 'Lineage II Elixir server architecture knowledge. Use when designing subsystems, proposing OTP process trees, analyzing L2J Mobius Java reference code, planning combat/AI/movement/zone systems, or deciding how to model game entities as Elixir processes. Covers: Login Server, Game Server, Packet Protocol, Character State, Combat, Skills, Movement, Geodata, Pathfinding, AI, Clans, Parties, Inventory, Quests, Olympiad, Siege, Zones, AOI, regions.'
argument-hint: 'subsystem or topic to design (e.g., "combat engine", "NPC AI", "region handoff")'
---

# L2 Server Architecture Knowledge

## When to Use

- Designing or reviewing any server subsystem from scratch
- Analyzing `L2J_Mobius_CT_0_Interlude/` Java code to propose an Elixir equivalent
- Choosing the right OTP primitive for a game entity
- Debugging architectural decisions (shared state, bottlenecks, broadcast scope)
- Planning supervision trees, Registry keys, or ETS schema

---

## Core Domains

See [domains reference](./references/domains.md) for per-domain design rules.

| Domain | Key Challenge |
|--------|--------------|
| Login Server | Session auth, game server handoff |
| Game Server | Central OTP app root |
| Packet Protocol | Typed struct decode → handler dispatch |
| Character State | Per-player isolated GenServer |
| Combat Engine | Event-driven, no global tick |
| Skill Engine | Cooldown timers, effect resolution |
| Movement Engine | Position sync, geodata checks |
| Geodata | Read-heavy, ETS or NIF-backed |
| Pathfinding | CPU-heavy → Rust NIF / C binding |
| AI System | Event-driven GenServer, sleeps when idle |
| Clan System | GenServer + PubSub membership events |
| Party System | GenServer + PubSub member updates |
| Inventory | Sub-state inside player GenServer or separate |
| Quest Engine | State machine per player |
| Olympiad | Isolated supervised subtree per match |
| Siege System | Supervised subtree per active siege |
| Zone Engine | GenServer per zone, AOI-scoped events |

---

## Architecture Procedure

When asked to design or analyze any subsystem, follow these steps:

### 1. Identify the Gameplay Behavior
What does this system do from the player's perspective?  
State the observable behavior clearly before any design decision.

### 2. Identify the Java Limitations
What does L2J Mobius do that we must NOT replicate?  
- Singleton managers with synchronized state
- Polling loops / global ticks
- Thread-per-connection or blocking I/O
- Inheritance hierarchies for entity behavior

### 3. Map to OTP Primitives
Use the entity → primitive table from the [domains reference](./references/domains.md).  
Always justify the choice: why GenServer and not Agent? Why ETS and not a process?

### 4. Design the Process Tree
Draw or describe the supervision hierarchy:
- Which supervisor owns this process?
- `one_for_one` vs `rest_for_one` strategy?
- What happens when a child crashes?

### 5. Define Message Contracts
List the `call` / `cast` / `info` messages the process handles.  
Use typed structs for all message payloads.

### 6. Scope Broadcasts with AOI
Any state change that must reach other players:
- Is it scoped to a region? Use `Phoenix.PubSub` with region topics
- Is it global? Almost certainly wrong — reconsider

### 7. Identify Performance Risks
- CPU-heavy? → consider `Task.Supervisor` or a NIF
- Memory-heavy? → consider ETS with `:compressed`
- Hot path? → avoid synchronous `GenServer.call`; prefer `cast` + async reply

---

## Key Design Rules

### AOI (Area of Interest)
- Players only receive updates for entities in their visibility radius
- Never broadcast globally; always scope to region topic
- Region GenServers maintain entity lists and manage AOI subscriptions

### Region Ownership
Each region GenServer owns:
- Entity pids in that area
- Visibility tracking
- Local PubSub topic
- Combat coordination within the region
- Cross-region movement triggers supervised handoff

### Player Processes
```
PlayerSupervisor (DynamicSupervisor)
└── PlayerSession (GenServer)
      ├── state: position, hp, stats, flags
      ├── inventory: item list or sub-GenServer
      ├── cooldowns: map of skill_id → expiry
      └── session: socket pid, encryption state
```

### NPC Processes
- Start under the region's DynamicSupervisor
- React to `:target_entered`, `:attacked`, `:target_left` messages
- Use `Process.send_after/3` for walk delays, re-aggro checks
- Hibernate with `:hibernate` return when idle

### Combat Flow
```
Player casts attack
  → message to target PlayerSession or NpcProcess
  → damage resolved in target process
  → hp update broadcast via PubSub region topic
  → AOI-scoped notify to nearby players
```
No shared combat state. No global tick.

### Packet Pipeline
```
TCP bytes
  → ThousandIsland / Ranch handler
  → NewCrypt.decrypt/2 (process-local key)
  → PacketDecoder.decode/1 → typed struct
  → PacketRouter.dispatch/2 → handler module
  → handler sends message to PlayerSession
```

### Pathfinding
- A* or Dijkstra is CPU-heavy; do not run in a GenServer
- Options in priority order:
  1. Rust NIF via `Rustler` (best latency)
  2. C Port / NIF
  3. `Task.Supervisor` worker pool (acceptable for low traffic)
- Cache frequent routes in ETS

---

## OTP Quick Reference

| Need | Use |
|------|-----|
| Stateful entity (player, NPC, region) | `GenServer` |
| Dynamic entity pool | `DynamicSupervisor` + `Registry` |
| Read-heavy shared data (item templates, configs) | `:ets` table, owned by a dedicated GenServer |
| Fan-out broadcast (AOI, zone events) | `Phoenix.PubSub` |
| CPU-heavy one-off work | `Task.Supervisor` |
| Isolated dungeon / siege / olympiad | Supervised subtree with its own root supervisor |
| Scheduled recurring work | `Process.send_after/3` inside GenServer |
| Avoid | Global Agent, Registry as a mutable store, `:global` |
