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

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
