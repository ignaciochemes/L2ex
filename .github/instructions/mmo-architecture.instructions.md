---
description: "Use when designing, reviewing, or generating Elixir/OTP code for the L2E MMO server. Enforces OTP-native architecture: no Java porting, no singleton managers, no global state, no polling loops. Covers actor model, region ownership, AOI broadcasting, packet pipelines, fault isolation."
applyTo: ["**/*.ex", "**/*.exs"]
---

# MMO Architecture Guidelines

This project rebuilds Lineage II Interlude using idiomatic Elixir/OTP.  
`L2J_Mobius_CT_0_Interlude/` is a **gameplay and protocol reference only** — not a porting source.

## Hard Rules

**Never do:**
- Directly port Java classes to Elixir modules
- Create singleton domain managers (`PlayerManager`, `WorldManager`, `ItemManager`, etc.)
- Recreate `synchronized` blocks using `Agent` or lock-style GenServers
- Write polling loops or global tick broadcasts
- Recreate thread-pool architectures
- Use inheritance-style `use` macros to mimic `extends`
- Broadcast state changes globally (always scope to region/zone/party/clan)

**Always do:**
- Model each game entity (player, NPC, region, party, clan) as an isolated `GenServer`
- Own all mutable state in exactly one process; expose it only via message passing
- Use `DynamicSupervisor` + `Registry` for dynamic entity pools
- Store read-heavy shared data (item templates, configs, geodata) in ETS
- Scope broadcasts via `Phoenix.PubSub` region/zone topics
- Trigger timed behavior with `Process.send_after/3`, never a loop
- Let idle processes hibernate: `{:noreply, state, :hibernate}`

## Architecture Priorities (in order)

1. Scalability — thousands of concurrent players
2. Low latency — no blocking in hot paths
3. Fault isolation — one crash must not cascade
4. Predictable performance — avoid GC pressure and mailbox bloat
5. Region-based simulation — world state lives in region processes

## Core Ownership Model

| Entity | Owner | Pattern |
|--------|-------|---------|
| Player | `PlayerSession` GenServer | `DynamicSupervisor` + `Registry` |
| NPC | `NpcProcess` GenServer | Region's `DynamicSupervisor` |
| Region/Zone | `Region` GenServer | `WorldSupervisor` |
| Item templates, skills | ETS table | Owned by a dedicated GenServer |
| Broadcast | `Phoenix.PubSub` | Scoped to region/party/clan topic |

## Packet Pipeline

Packets must flow:  
`TCP bytes → decrypt (process-local) → decode → typed struct → router → handler → PlayerSession message`

- Decoders are **pure functions** — no side effects, no GenServer calls
- Router is a **plain dispatch map** — not a GenServer
- Each connection owns its own cipher state — no shared encryption

## AOI (Area of Interest)

- Players receive updates only for entities within their visibility radius
- Region GenServers maintain entity lists and manage AOI subscriptions
- Cross-region movement triggers supervised handoff — never a global lookup

## When Writing or Reviewing Code, Always Explain

- What gameplay behavior this implements
- Who owns the state and why
- What happens if this process crashes (fault isolation)
- How broadcasts are scoped (AOI / PubSub topic)
- Whether any `GenServer.call` in a hot path should be a `cast`

## Module Design

- One concern per module — no monolithic `GameEngine` or `WorldServer` modules
- Pure logic (damage formulas, packet decoding, path calculations) in plain modules, not GenServers
- GenServers hold state and coordinate; they delegate computation to pure modules
