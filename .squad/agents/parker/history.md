# Parker — Learnings & Project Knowledge

## Project

- **Project:** L2E — Lineage II Interlude rebuilt in Elixir/OTP
- **Owner:** Ignacio Gonzalez Chemes
- **Repo:** github.com/ignaciochemes/L2Ex
- **Workspace:** `c:\Users\Ignacio\Desktop\l2e\`
- **OS:** Windows — PowerShell only. Never `Add-Content`. Always `replace_string_in_file`.

## Stack

- Ecto ~> 3.11 / PostgreSQL
- pbkdf2_elixir for password hashing (bcrypt FORBIDDEN on Windows)
- Migrations at `priv/repo/migrations/`
- Schemas at `lib/l2e/db/`

## Current DB Schema (Applied Migrations)

| Table | Key Columns |
|-------|-------------|
| accounts | id, username, password_hash, access_level (int, default 0) |
| characters | id, account_id, name, level, hp, mp, x, y, z, karma (int), access_level |
| character_items | id, character_id, item_id, count, enchant_level, location |
| warehouse_items | id, character_id, item_id, count, enchant_level |
| clan_warehouse_items | id, clan_id, item_id, count, enchant_level |
| clans | id, name, leader_id, level |

## Applied Migrations

1. `20260522000001_add_karma_to_characters.exs` — adds `karma :integer, default: 0`
2. `20260522000002_add_access_level_to_accounts.exs` — adds `access_level :integer, default: 0`
3. `20260522000003_create_clan_warehouse_items.exs` — creates `clan_warehouse_items` with index on `clan_id`

## Key Schema Files

- `lib/l2e/db/account.ex` — Account schema (username, password_hash, access_level)
- `lib/l2e/db/character.ex` — Character schema (stats, position, karma)
- `lib/l2e/db/item.ex` — Item schema
- `lib/l2e/db/clan_warehouse_item.ex` — ClanWarehouseItem schema (clan_id, item_id, count, enchant_level)

## Architecture Principles (Persistence)

- pbkdf2_elixir ONLY for passwords — never bcrypt_elixir
- Migrations always have `down` blocks
- Index every FK column and every `where` column
- Changesets validate at DB boundary, not at game logic layer

## M44 — Character Skills DB Schema (2026-05-22)

- Created `lib/l2e/db/character_skill.ex` — `L2E.DB.CharacterSkill` schema with `belongs_to :character`, `skill_id`, `skill_level` (default 1), changeset with FK + unique constraints, `load_for_character/1`, `upsert_skill/3`
- Created `priv/repo/migrations/20260522000004_create_character_skills.exs` — `character_skills` table; index on `character_id`; unique index on `[:character_id, :skill_id]`
- Updated `lib/l2e/db/character.ex` — added `has_many :skills, L2E.DB.CharacterSkill`

## M47 — Quest Infrastructure DB Layer (2026-05-22)

- Created `priv/repo/migrations/20260522000005_create_character_quests.exs` — `character_quests` table; columns: `character_id`, `quest_id`, `state` (default 0), `cond` (default 0), `count` (default 0), `reward_taken` (bool, default false); index on `character_id`; unique index on `[:character_id, :quest_id]`; explicit `down` block drops the table
- Created `lib/l2e/db/character_quest.ex` — `L2E.DB.CharacterQuest` schema with `belongs_to :character`, `quest_id`, `state`, `cond`, `count`, `reward_taken`; changeset validates state inclusion in `[0,1,2]` and non-negative `cond`/`count`; implements `load_for_character/1`, `get_quest/2`, `set_quest_state/5` (upsert via `on_conflict: :replace_all`), `complete_quest/2`
- Updated `lib/l2e/db/character.ex` — added `has_many :quests, L2E.DB.CharacterQuest` after `has_many :skills`

## M50 — Quest Scripts (2026-05-22)

- Created `lib/l2e/quest/scripts/new_adventurer.ex` — `L2E.Quest.Scripts.NewAdventurer`; quest_id 255; NPC 30008 (Newbie Guide); no kill req; level gate 5 for reward; rewards 3000 adena + 5 Scroll of Escape
- Created `lib/l2e/quest/scripts/exploration_of_giants_cave.ex` — `L2E.Quest.Scripts.ExplorationOfGiantsCave`; quest_id 213; NPC 30516 (Researcher Lorain); kill 10 Cave Servants (NPC 20678); rewards 50000 adena + 1 Enchant Scroll Weapon D
- Created `lib/l2e/quest/scripts/path_of_warrior.ex` — `L2E.Quest.Scripts.PathOfWarrior`; quest_id 211; NPC 30017 (Master Auron); class change pre-quest for Human Fighter (class_id 0); level gate 19; reward Mark of Warrior (item_id 1665)
- All scripts `use L2E.Quest.Engine` (Dallas's DSL); no wiring into application.ex or player_session.ex

## Learnings

### M44 — Character Skills DB (2026-05-22)
- `upsert_skill/3` with `on_conflict: :replace_all` and `conflict_target: [:character_id, :skill_id]` is the correct Ecto upsert shape for uniquely-keyed rows.
- `has_many` associations in character schema must be added AFTER the schema fields block, before the closing `end` — ordering matters for Ecto schema macro expansion.

### M47 — Quest Infrastructure DB (2026-05-22)
- `cond` is a reserved word in Elixir pattern matching but is safe as an Ecto schema field atom — Ecto accesses it via struct fields, never via pattern matching.
- `on_conflict: :replace_all` is appropriate for `set_quest_state` (full row replacement is idempotent); for `complete_quest`, use `on_conflict: [set: [state: 2, reward_taken: true]]` to preserve `cond`/`count` counters set by game logic.
- Migration number `20260522000005` follows the existing sequential convention — check the last migration number in `priv/repo/migrations/` before creating a new one.
- `state` integer (0/1/2) is the L2J convention; do NOT introduce an Ecto enum — packet serialization downstream expects integers.

### M55 — Data Tables: Henna, Recipes, Augmentation (2026-05-22)
- Created `lib/l2e/data/henna_table.ex` — ETS `:henna_table`; 8 hardcoded L2 Interlude hennas; `get/1`, `get_all/0`, `get_dye_for_item/1`
- Created `lib/l2e/data/recipe_table.ex` — ETS `:recipe_table`; 6 hardcoded recipes (4 from spec + 2 extras); `get/1`, `get_for_item/1`, `get_common_recipes/0`
- Created `lib/l2e/data/option_table.ex` — ETS `:option_table`; 8 hardcoded augmentation options; `get/1`, `get_random_option/1` (grade → id range)
- Modified `lib/l2e/application.ex` — added `L2E.Data.HennaTable`, `L2E.Data.RecipeTable`, `L2E.Data.OptionTable` after `ClassAdvancementTable`
- Pattern: no XML loading, no Ecto, no DB tables — pure ETS with hardcoded seed data, same as SkillLearnTable

## M52 — SpawnData Loader (2026-05-22)

- `lib/l2e/npc/spawn_table.ex` already existed and loaded from XML — not replaced, only enhanced
- Added hardcoded Talking Island fallback to `NPC.SpawnTable.load_spawn_defs/0` — used only when XML spawn files resolve to zero entries
- Added `spawn_npc/5` (positional convenience function) to `lib/l2e/npc/supervisor.ex` — does template lookup + auto-generates object_id via `:erlang.unique_integer([:positive, :monotonic]) + 100_000`; existing `spawn_npc/1` opts variant preserved

## M57 — ExperienceData + PlayerTemplateData (2026-05-22)

- Created `lib/l2e/data/experience_table.ex` — pure compile-time module (no GenServer); 85-level XP table built into `@xp_map` at compile time; `get_xp_for_level/1` and `max_level/0`
- Modified `lib/l2e/game/stats.ex`:
  - `max_hp/2` and `max_mp/2` now use non-linear polynomial growth via private `max_hp_at_level/2` and `max_mp_at_level/2` helpers; `hp_per_level` / `mp_per_level` template fields no longer needed by these functions
  - `xp_to_next_level/1` now delegates to `ExperienceTable.get_xp_for_level/1` diff instead of the old cubic approximation
- `application.ex` unchanged — ExperienceTable is a pure module, no supervision needed
