# Squad Decisions

## Active Decisions

### [2026-05-22] M45 Class Advancement — Design Choices (Dallas)

**D1 — ClassAdvancementTable as standalone ETS GenServer**
`L2E.Data.ClassAdvancementTable` is a standalone ETS GenServer (`name: __MODULE__`), matching the SkillLearnTable pattern. Rejected: embedding transitions in ClassTemplates or SkillLearnTable. Reason: separation of concerns; crash-isolated; ETS cheap reads; easy to extend with XML loading.

**D2 — ClassList bypass sends NpcHtmlMessage with bypass links**
`ClassList` bypass sends `NpcHtmlMessage{npc_object_id: 0, html: ...}` with `<a action="bypass ClassChange N">` links. Rejected: SystemMessages or CreatureSay lines. Reason: NpcHtmlMessage renders as proper in-game dialog with clickable buttons.

**D3 — Class change failure uses CreatureSay (chat_type: 2 = TELL)**
On failed `can_advance?`, send `CreatureSay{chat_type: 2, char_name: "System", message: "..."}`. Rejected: SystemMessage (predefined IDs don't map cleanly). Reason: chat_type 2 displays as private system message without a registered message ID.

**D4 — Starting skills at class change = skills with min_level 1**
`SkillLearnTable.get_learnable_skills(target_class_id, 1)` fetches skills the new class grants. Reason: conservative correct MVP behavior; later task can separate "granted on change" vs "learnable from NPC."

---

### [2026-05-22] M45/M48 Packet Implementation (Lambert)

**D1 — `RequestGotoLobby` (0xBA) empty body**
`def decode(_body), do: {:ok, %__MODULE__{}}`. No fields needed. Decoder entry added before the extended 0xD0 block under `# M45: Class advancement` comment.

**D2 — `DoorInfo` (0x31) uses simplified Interlude layout**
`opcode(8) door_id(32LE) show_hp(8=0) is_open(8) is_attackable(8=0) max_hp(32LE) current_hp(32LE) x(32LE) y(32LE) z(32LE)`. Fields with defaults use `|| 0` guards in encode.

**D3 — `DoorStatusUpdate` (0x2C) minimal broadcast**
`door_id(32LE) is_open(8)`. Server-side 0x2C does not conflict with client-side 0x2C (`RequestOustPartyMember`) — opcodes are directional.

**D4 — No new client packets for M48 instance zones**
Instance entry is triggered by server-side teleport; the client sends no specific "enter instance" packet in Interlude.

---

### [2026-05-22] M47 Quest Infrastructure DB Layer (Parker)

**D1 — `on_conflict: :replace_all` in `set_quest_state`**
Full-row replacement is safe here; `complete_quest` uses `on_conflict: [set: [...]]` to update only relevant fields without overwriting progress counters.

**D2 — `cond` as field name**
Kept to mirror L2 protocol terminology. Ecto handles reserved-word atoms safely as schema field names.

**D3 — State as integer (0/1/2)**
Mirrors L2J source to simplify packet serialization downstream; enum mapping lives in game logic, not in the DB schema.

**D4 — No FK constraint in migration**
Follows project convention (see `character_skills`); FK enforced at changeset level via `foreign_key_constraint/2`.

---

### [2026-05-22] M46 Geodata Stub + M48 Instance Zones / Doors (Ripley)

**D1 — `L2E.Geodata` as named GenServer with ETS state (stub)**
Public API (`can_move_to?/6`, `can_see_target?/6`, `get_height/3`) matches final interface; impl is stub (always passable). Callers use real API today; swapping in NSWE block parsing later requires zero changes at call sites.

**D2 — Instance hierarchy: DynamicSupervisor + Zone GenServer + Manager GenServer**
`L2E.Instance.Supervisor` (DynamicSupervisor) → `L2E.Instance.Zone` (one per active instance); `L2E.Instance.Manager` (ETS registry). Instance crash isolation: one crash does not affect others or the world. Door state lives inside Zone state — no shared locks.

**D3 — TTL expiry via `Process.send_after(self(), :instance_expired, ttl)`**
No polling, fully OTP-native. Player crash cleanup via `Process.monitor` in Zone; instance crash cleanup via `Process.monitor` in Manager.

**D4 — Instance eject delegates to existing `do_teleport/2`**
Uses Giran spawn coordinates from `Application.get_env/3`. `L2E.Config` does not exist — use `Application.get_env` with defaults throughout codebase.

**D5 — `Instance.Supervisor` started BEFORE `Instance.Manager`**
Manager calls Supervisor on `create_instance`; supervision order enforces correct startup.

---

---

### [2026-05-22] Ripley — Gap Analysis (Fase B Complete, M1–M48)

**Coverage estimate: ~42% of L2J Mobius CT0 Interlude**

| Domain | L2E Coverage |
|--------|-------------|
| Networking / Auth | ~100% |
| Core gameplay loop | ~90% |
| Inventory / Equip | ~85% |
| NPC system | ~60% |
| Combat / Skills | ~50% |
| Social | ~70% |
| Zones / World | ~45% |
| Quests | ~3% |
| Endgame | ~5% |
| Economy | ~50% |

Packet coverage: 86/215 client (~40%), 66/279 server (~24%).

**P1 — Skill Effects System (M49):** L2J has 40+ `EffectType` variants; L2E implements 3. Expand `skill/effect.ex`. Blocks PvP quality, Olympiad, class differentiation.

**P2 — Quest Engine + Scripts (M50):** 0 of 500+ scripts exist. DB infrastructure (M47) done. DSL + event hooks (`on_kill`, `on_talk`) + starter quests needed.

**P3 — Real Geodata (M51):** Stub always passable. NPCs walk through walls. Module interface already designed (M46); binary `.l2j` parser is the implementation work.

**Recommended M49–M55 roadmap:**

| Milestone | System |
|-----------|--------|
| M49 | Skill effects expansion (stun, root, speed, power charge, toggle) |
| M50 | Quest DSL + 10 critical quests |
| M51 | Real geodata (binary parser + NSWE passability) |
| M52 | Olympiad proper |
| M53 | Siege system |
| M54 | Pets & Summons |
| M55 | Augmentation + Henna + Crafting bundle |

---

### [2026-05-22] Ripley — Gap Analysis Priority Decisions

**D1 — Geodata (M44) must precede AI improvement (M43)**
NPC hate list has near-zero gameplay value while geodata is a stub (NPCs aggro through walls). Real `.l2j` binary parser is prerequisite for correct AI, ranged combat, AOI scoping, and pathfinding.

**D2 — SpawnData XML loader is highest-ROI next data table**
World is empty except for manual spawns. `Data.SpawnData` ETS loader from reference XML fills the world with monsters and enables all combat/drop/XP testing at scale.

**D3 — Henna + Recipes + Augmentation as batch (M46/M47/M49)**
Data tables already in ETS. Remaining work is packet handler plumbing — 1-3 days each. Batch as single sprint for maximum gameplay depth gain.

**D4 — Quest content must be parallel, not serial**
Quest engine DSL is solid; 3 scripts exist out of 500+. Dedicate a parallel effort to quest scripts; prioritize L1-20 quests for new-player retention.

**D5 — Define "Playable Demo" milestone before endgame (M52+)**
Criteria: world populated, geodata working for 3+ zones, shortcut bar functional, 10+ L1-20 quests, hate list AI working. Avoids building endgame on broken mid-game foundation.

---

### [2026-05-22] M50 Quest Engine DSL (Dallas)

**D1 — Registry: ETS + explicit module list**
`L2E.Quest.Registry` is a GenServer with a named ETS table (`:quest_registry`). Quest modules registered explicitly in `load_quests/0` — no beam scanning. Keeps startup deterministic.

**D2 — Event routing: pure functions, no GenServer roundtrip**
`L2E.Quest.Handler` contains only pure functions (`dispatch_kill/3`, `dispatch_talk/4`). Scan ETS and call quest module callbacks directly — no message passing on hot path.

**D3 — Kill hook: new cast on PlayerSession**
`handle_cast({:npc_killed_for_quest, npc_template_id}, state)` added to PlayerSession. NPC sends cast on death; session owns quest state and persists DB only when state changed.

**D4 — Talk hook replaces stub in handle_bypass/2**
`Quest ` cond branch was a no-op stub; replaced with full `dispatch_talk/4`. Bypass command format: `"Quest <npc_template_id>"`.

---

### [2026-05-22] M50 Quest Scripts — 3 Starter Scripts (Parker)

**D1 — Scripts in `lib/l2e/quest/scripts/`, use Quest.Engine DSL**
No changes to `application.ex` or `player_session.ex` from Parker's side — registration/dispatch belong to Dallas.

**D2 — Scripts created:**
- `NewAdventurer` (quest_id 255): starter quest, NPC 30008, no kills, rewards at level 5
- `ExplorationOfGiantsCave` (quest_id 213): kill 10x Cave Servant (NPC 20678), `on_kill` guards on state+cond
- `PathOfWarrior` (quest_id 211): class-gate quest (class_id 0, level ≥ 19), `on_first_talk` validates

**D3 — `on_talk/3` cond threading**
All `on_talk` clauses return explicit `new_state` maps; no implicit mutation. Level check in `on_first_talk` gates entry; `on_talk` gates reward.

---

### [2026-05-22] M52 SpawnData Loader + M57 ExperienceData / Stats (Parker)

**D1 — SpawnTable enhanced with Talking Island fallback**
`L2E.NPC.SpawnTable` already existed; XML-loading enhanced with hardcoded TI fallback when XML resolves to zero entries. `spawn_npc/5` positional convenience added to `L2E.NPC.Supervisor`; existing `spawn_npc/1` preserved.

**D2 — ExperienceData: pure compile-time module, no GenServer**
85-level L2 Interlude XP table compiled into a map at startup. `Stats.xp_to_next_level/1` delegates to this table, replacing old cubic approximation.

**D3 — Stats: polynomial HP/MP curves**
`Stats.max_hp/2` and `Stats.max_mp/2` use `base * (1 + level*0.07 + level^1.5 * 0.01)` and `base * (1 + level*0.08)` — better Interlude match than linear formulas, without per-level XML tables.

---

### [2026-05-22] M53 NPC Hate List / AggroInfo (Lambert)

**D1 — `hate_map: %{pid => integer}` replaces single `target_pid`**
`target_pid` now derived from top entry via `select_top_hated/2`. NPCs always pursue most-hated attacker and re-target automatically when a player leaves. `player_session.ex` seeds 1 point of initial hate when auto-attack starts; hate accumulates from damage, initial aggro detection (100), and future `add_hate/3` skill taunts.

---

### [2026-05-22] M55 Data Tables — Henna, Recipes, Augmentation (Parker)

**D1 — All three tables: ETS-backed GenServer, no DB, no XML**
Pattern follows existing `SkillLearnTable` / `ClassAdvancementTable` (hardcoded seed data). Each table: `:named_table, :set, :public, read_concurrency: true`.

**D2 — HennaTable (`lib/l2e/data/henna_table.ex`)**
8 Henna templates (Lion, Dragon, Ogre, Cat, Star, Rabbit, Frog, Princess). API: `get/1`, `get_all/0`, `get_dye_for_item/1`.

**D3 — RecipeTable (`lib/l2e/data/recipe_table.ex`)**
6 crafting recipes (Iron Ingot, Charcoal, Synthetic Cokes, Silver Nugget, Steel, Mithril Alloy). API: `get/1`, `get_for_item/1`, `get_common_recipes/0`.

**D4 — OptionTable (`lib/l2e/data/option_table.ex`)**
8 augmentation options (stat bonuses, active/passive skills, special proc). `get_random_option/1` uses `Enum.random/1` on grade-keyed pool ranges (low=1-3, mid=1-5, top=1-7, ancient=1-8).

**D5 — Added to supervision tree after `ClassAdvancementTable`**
`HennaTable`, `RecipeTable`, `OptionTable` all added to `application.ex`.

---

### [2026-05-22] FASE 3 OTP Module Foundation (Bishop)

**What:** Created OTP trees for M69 (Duel.Manager + Duel.Session + Duel.Supervisor), M70 (Olympiad.Manager + Olympiad.Supervisor), M72 (Pet.Session + Pet.Supervisor), M71 (Siege.Manager + Siege.Supervisor + Siege.Castle). Also M68 SubclassData. All event-driven, no polling.
**Why:** FASE 3 endgame system foundations. Dallas integrates into player_session.ex + application.ex.

**Modules added to supervision tree:**
- `{Registry, keys: :unique, name: L2E.Duel.Registry}`
- `L2E.Duel.Manager`
- `L2E.Duel.Supervisor`
- `L2E.Olympiad.Supervisor` (contains Olympiad.Manager)
- `L2E.Pet.Supervisor`
- `L2E.Siege.Supervisor` (contains Siege.Manager)
- `L2E.Data.SubclassData`

---

### [2026-05-22] FASE 3 Server Packets Added to packets.ex (Lambert)

**What:** Added 11 new server packet modules to `lib/l2e/packet/server/packets.ex`.

| Module | Opcode | Java Source |
|--------|--------|-------------|
| `L2E.Packet.Server.FriendList` | 0xFA | `FriendList.java` |
| `L2E.Packet.Server.L2Friend` | 0xFB | `FriendPacket.java` |
| `L2E.Packet.Server.FriendStatusPacket` | 0xFC | `FriendStatusPacket.java` |
| `L2E.Packet.Server.FriendRecvMsg` | 0xFD | `L2FriendSay.java` |
| `L2E.Packet.Server.PetInfo` | 0xB1 | `PetInfo.java` |
| `L2E.Packet.Server.SiegeInfo` | 0xC9 | `SiegeInfo.java` |
| `L2E.Packet.Server.ExDuelAskStart` | 0xFE/0x4B | `ExDuelAskStart.java` |
| `L2E.Packet.Server.ExDuelReady` | 0xFE/0x4C | `ExDuelReady.java` |
| `L2E.Packet.Server.ExDuelStart` | 0xFE/0x4D | `ExDuelStart.java` |
| `L2E.Packet.Server.ExDuelEnd` | 0xFE/0x4E | `ExDuelEnd.java` |
| `L2E.Packet.Server.ExOlympiadMode` | 0xFE/0x2B | `ExOlympiadMode.java` |

**D1 — `L2Friend` opcode is 0xFB, not 0xFA**
`FriendPacket.java` calls `ServerPackets.FRIEND_LIST.writeId` (0xFA) but `ServerPackets.java` enum has a distinct `L2_FRIEND(0xFB)`. 0xFB is correct for add/remove notification.

**D2 — PetInfo fly speeds written twice (wire protocol quirk)**
`PetInfo.java` writes `_flyRunSpd` and `_flyWalkSpd` twice in sequence. Reproduced exactly to match the wire protocol.

**D3 — ExDuelReady / ExDuelStart / ExDuelEnd encode one int**
All three Java classes write exactly one int (`_partyDuel` cast to int). Field `party_duel` accepts boolean or integer; truthy → 1.

**D4 — ExOlympiadMode encodes mode as single byte (::8)**
Java uses `writeByte`, not `writeInt`.

---

### [2026-05-22] M68 Sub-class DB Schema (Parker)

**What:** Created `character_subclasses` table. `class_index` 1-3 for sub-classes; base class (0) not stored — base `class_id` lives on the character row. `exp`/`sp` stored as bigint. save/load/add/remove functions on `L2E.DB.CharacterSubclass`.
**Why:** M68 milestone — sub-class system foundation.

---

### [2026-05-22] M60 + M61 + RelationChanged Server Packets (Lambert)

**D1 — Four server packet modules added after `ExVariationResult`**

| Module | Opcode | Purpose |
|--------|--------|---------|
| `RestartResponse` | `0x5F` | Confirms RequestRestart → character select |
| `ChangeMoveType` | `0x30` | Broadcasts run/walk mode |
| `ChangeWaitType` | `0x31` | Broadcasts sit/stand/fakedeath state |
| `RelationChanged` | `0x60` | Broadcasts relation bitmask |

**D2 — `SocialAction` (0x5F) already existed at line 723 — not re-added**

**D3 — `RelationChanged` bitmask (Interlude values)**
`0x01` party member, `0x02` party leader, `0x04` auto attackable, `0x08` PvP mode, `0x10` dead, `0x40` in combat.

---

### [2026-05-22] M63 ExperienceLossData + Death XP Penalty (Parker)

**D1 — Static module (compile-time multi-clause functions), not XML-driven**
Three tier breakpoints (levels 7, 40, 76) are constants in L2J XML; hardcoding eliminates XML I/O for immutable data.

**D2 — GenServer shell for supervision tree consistency**
`ExperienceLossData` holds no runtime state but follows the `L2E.Data.*` GenServer pattern for uniformity and future extensibility (vitality reduction).

**D3 — No level-down on death**
XP loss is floored at `ExperienceTable.get_xp_for_level(level)` — player can reach 0% progress but cannot drop to previous level. Matches confirmed Interlude mechanics.

**D4 — DB field is `exp` (not `xp`)**
`L2E.DB.Character` uses `field(:exp, :integer)`; task spec used `state.xp` — discrepancy noted; `exp` is the correct field.

**D5 — No new migration required**
`characters.exp` and `characters.level` already exist from initial schema.

---

### [2026-05-22] M64 MultiSell + M67 QuestList (Dallas)

**D1 — Inventory by-template removal (`remove_item_by_template/3`)**
Existing `remove_item/3` takes instance_id; MultiSell needs template_id removal (client doesn't know server instance IDs). New function finds first matching instance and delegates to same DB-persistence logic.

**D2 — QuestList sent after ShortcutInit on EnterWorld**
`load_char_quests/1` result is already bound; QuestList filters to `state == 1` (in-progress). No extra DB round-trip.

**D3 — MultiSellList uses extended opcode format**
`0xFE` prefix byte + `0x000B` 16-bit sub-opcode (Interlude wire format for multi-sell lists).

**D4 — Seed data: two lists**

| List ID | Name | Entries |
|---------|------|---------|
| 100 | Crystal Exchange | C→B, B→A, A→S crystals |
| 200 | Blacksmith of Mammon | 200k adena → low life stone; 2M adena → mid life stone |

---

### [2026-05-22] M65 ArmorSetData + M66 Friend List DB (Parker)

**D1 — ArmorSetData: ETS keyed by chest item_id (slot 10)**
5 Interlude sets (Dark Crystal Heavy, Dark Crystal Robe, Tallum Heavy, Tallum Robe, Dynasty Armor). `check_set_bonus/1` accepts `%{slot_id => item_id}` map; returns bonus stats or `%{}`. Slot mapping: 6=head, 7=legs, 8=gloves, 9=feet, 10=chest. Added to supervision tree after `ExperienceLossData`.

**D2 — CharacterFriend schema: directed friendships**
`character_friends` table stores one row per directed pair (char_id → friend_id). Unique constraint on `(char_id, friend_id)`. `friend_name` cached for display without joins. Symmetric friendship requires explicit dual insert at handler level.

**Open:** Armor set slot IDs (6/7/8/9/10) need validation against `L2E.Inventory` slot constants once equip handlers are wired.

---

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
