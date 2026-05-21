---
name: anti-java-porting
description: 'Enforce anti-Java-porting rules for Elixir/OTP code. Use when reviewing Elixir code for Java smell, auditing a proposed design for ported patterns, or checking if a class translation is idiomatic. Catches: singleton managers, inheritance trees, synchronized state, thread pools, polling loops, giant World/Combat managers, global mutable registries. Ensures Elixir code feels native to OTP.'
argument-hint: 'code, module, or design to audit (e.g., "PlayerManager GenServer", "this combat loop")'
---

# Anti Java Porting Rules

## When to Use

- Reviewing a proposed Elixir module that originated from a Java class
- Auditing a design for ported Java patterns before implementation
- Checking if a GenServer, module, or supervision tree smells like a Java object
- Enforcing OTP-native design across the codebase

---

## Procedure

### 1. Identify the Java Origin
What Java class or pattern is this derived from?  
Name the original (e.g., `WorldManager.java`, `CombatEngine.java`).  
State what it did from a **behavioral** perspective only — not its structure.

### 2. Run the Anti-Pattern Checklist

Check for every item below. Flag any that apply.

#### Structure Anti-Patterns
- [ ] Is this a direct translation of a Java class → Elixir module?
- [ ] Does it replicate an inheritance hierarchy (using `use` or `defmacro` to mimic `extends`)?
- [ ] Is it a singleton GenServer that holds all state for a domain (e.g., `PlayerManager`, `ItemManager`)?
- [ ] Does it use a global `Registry` as a mutable store (not just for PID lookup)?

#### State Anti-Patterns
- [ ] Is there shared mutable state accessed by multiple processes without message passing?
- [ ] Are there ETS tables written to by many processes concurrently (no single owner)?
- [ ] Does it replicate `synchronized` blocks using `Agent` or a lock-like GenServer?

#### Behavior Anti-Patterns
- [ ] Is there a polling loop (`receive` loop, recurring `:tick` cast with no external trigger)?
- [ ] Is there a centralized combat/AI engine that manages all entities from one process?
- [ ] Is pathfinding or heavy computation running inside a GenServer's `handle_call`?
- [ ] Are giant `case`/`cond` blocks dispatching behavior that should be in separate modules?

#### Networking Anti-Patterns
- [ ] Is there a thread-pool model recreated with a fixed-size pool of GenServers?
- [ ] Is encryption/decryption state shared across connections?

---

### 3. Propose the Idiomatic Replacement

For each flagged anti-pattern, provide the OTP-native alternative:

| Java Pattern | Elixir/OTP Replacement |
|---|---|
| Singleton Manager | `DynamicSupervisor` + per-entity `GenServer` |
| `synchronized` state | Owned exclusively by one `GenServer`; all access via message |
| `extends` / inheritance | Behaviours (`@behaviour`) + composition |
| Polling loop / tick | `Process.send_after/3` triggered by events |
| Global mutable registry | `Registry` for PID lookup only; state lives in processes |
| Thread pool model | `Task.Supervisor` or `ThousandIsland` acceptors |
| Centralized combat engine | Per-entity message passing; no central coordinator |
| Shared ETS writes | ETS owned and written by one GenServer; others read-only |

---

### 4. Validate the Replacement

Before accepting a redesign, confirm:

- **Fault isolation**: Can one process crash without affecting others?
- **No shared locks**: Is all state mutation owned by exactly one process?
- **AOI-scoped broadcasts**: Are broadcasts scoped to region/PubSub topics, not global?
- **Hibernation**: Do idle processes (NPCs, empty regions) hibernate?
- **No blocking calls in hot paths**: Are `GenServer.call` uses justified? Could they be `cast`?

---

### 5. Final Verdict

Output one of:
- **PASS** — No Java porting smell detected. Code is OTP-native.
- **WARN** — Minor smell; suggest refactor but not blocking.
- **FAIL** — Java porting detected; redesign required before proceeding.

---

## Hard Rules (Never Violate)

1. **No singleton domain managers.** `WorldManager`, `CharManager`, `ItemManager` do not exist as single GenServers.
2. **No mutable shared state.** Every piece of mutable state is owned by exactly one process.
3. **No polling loops.** Recurring behavior is triggered by events or `send_after`, never a tight loop.
4. **No centralized combat/AI.** Each entity manages its own combat and AI state.
5. **No inheritance trees.** Use behaviours and composition.
6. **No global broadcast.** Always scope to region, party, clan, or zone PubSub topic.
