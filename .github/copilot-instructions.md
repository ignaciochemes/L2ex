# L2E — Lineage II Elixir Server

## Project Purpose

This is **not** a Java-to-Elixir translation of L2J Mobius Interlude.  
We are rebuilding a Lineage II server using idiomatic Elixir/OTP.  
The Java source in `L2J_Mobius_CT_0_Interlude/` is a **behavioral and protocol reference only**.

---

## Architecture Principles

### DO use
- `GenServer` for stateful game entities (player sessions, NPCs, combat)
- `DynamicSupervisor` + `Registry` for managing dynamic process pools
- `ETS` for shared read-heavy data (item templates, skill definitions, configs)
- `Phoenix.PubSub` for broadcasting events (AOI visibility, zone events)
- Message passing for all cross-entity communication
- Region/zone processes that own nearby entities and local state
- AOI (Area of Interest) for spatial partitioning and broadcast scoping

### DO NOT replicate from Java
- Monolithic manager singletons (`CharacterManager`, `ItemManager`, etc.)
- Global mutable state or synchronized locking patterns
- Thread pool–driven game loops
- Java inheritance hierarchies → prefer Elixir behaviours and composition
- Polling-based AI loops or tick-heavy architectures

---

## Game Entity Design

Each major entity must be a supervised process:

| Entity | OTP Primitive |
|--------|--------------|
| Player session | `GenServer` under `DynamicSupervisor` |
| NPC | `GenServer` under region supervisor |
| Region/Zone | `GenServer` owning entity lists and local state |
| AI controller | Event-driven `GenServer`, no polling |
| Combat system | Message-driven, no shared locks |
| Clan / Party | `GenServer` with PubSub for membership events |
| Instance (dungeon) | Isolated supervised subtree |

---

## Networking

- Use `Ranch` or `ThousandIsland` for TCP acceptors — do not recreate Java selector/thread models
- Packets decode into Elixir structs
- Packet pipelines dispatch into actor systems via message passing
- Encryption/decryption is process-local (no shared cipher state)

---

## NPC AI Design

- AI must be event-driven, not loop/tick driven
- Use `handle_info/2` callbacks reacting to game events
- Timers via `Process.send_after/3` for delayed behavior
- Avoid giant `ai_loop` constructs

---

## World / Region Design

- Divide world into grid-based region processes
- Each region `GenServer` owns: nearby entities, visibility state, local broadcast scope, combat coordination
- Use AOI aggressively to limit broadcast scope
- Cross-region movement triggers supervised handoff between region processes

---

## When Analyzing L2J Mobius Source Code

Always follow this structure:

1. **Gameplay behavior** — what does this do from the player's perspective?
2. **Java limitations** — what architectural constraints or bottlenecks exist in the original?
3. **Elixir alternative** — idiomatic OTP-based design that achieves the same behavior
4. **Scalability notes** — how does the Elixir design handle high concurrency or failures?
5. **Avoid direct translation** unless it is pure protocol/packet encoding logic

---

## Performance Goals

The architecture must support:

- Thousands of concurrent players
- Mass PvP without server stalls or GC pauses
- Isolated failures (one crashed process must not affect others)
- Efficient packet broadcasting scoped by AOI
- Horizontal scalability across nodes
