# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working Principles (user-mandated, 最高优先级)

用户时间与预算有限，**每个任务都必须为省时间/省 token 服务**：

- **最短路径**：只为当前任务做最小必要改动；不顺手重构、不新增无关文件、不写长篇注释或文档。
- **省 token 的读法**：先用 grep/glob 定位，再带 offset/limit 定点读；禁止重复整文件读取或整文件回显；改动优先用 edit，不要重写大文件。
- **少开 agent**：默认由 Lead 单独完成。只有当任务可拆成互不依赖的大块、且并行确实更快时才用 teammates；subagent 的上下文同样是成本。
- **验证从简**：本项目无测试套件，只做必要的最小验证（如 GDScript 语法/加载检查），不跑完整试玩流程，除非任务明确要求。
- **输出精简**：结论先行，只列改动点与验证结果，不复述代码。
- **任务完成必须弹 Windows 通知**：每次交付结束前执行
  `pwsh -NoProfile -File scripts\dev\notify.ps1 -Title "HonorKing · <任务名>" -Message "<一句话结果>"`
  （脚本已就绪，失败会静默降级，不阻断交付）。

## Project Overview

HonorKing — a 3D MOBA game built with **Godot 4.5** (Forward Plus renderer). All game logic is written in **GDScript**. The game simulates a 5v5 Honor of Kings-style match: one player-controlled hero plus 4 AI teammates versus 5 AI enemies across a three-lane map with jungle, turrets, and epic monsters.

## Development Commands

- **Run the game**: Open `project.godot` in the Godot 4.5 editor and press F5, or run `godot --path .` from the project root.
- **No tests, no build step**: There is no test suite or CI. The only way to verify changes is to run the game in the Godot editor.

## Architecture

### Autoloads (Globals)

Defined in `project.godot` → `[autoload]`. These singletons are available everywhere without `load()`:

| Autoload | Path | Purpose |
|---|---|---|
| `Config` | `scripts/core/Config.gd` | Constants: `MAP_SIZE=120`, `Team` enum (`PLAYER=0, ENEMY=1, NEUTRAL=2`) |
| `ItemDatabase` | `assets/ItemDatabase.gd` | All item definitions, synthesis trees, recommended build paths, `get_item()`, `can_build()`, `get_synthesis_cost()` |
| `SkillDatabase` | `assets/SkillDataBase.gd` | All skill definitions (hero skills + summoner spells), `get_skill()` |
| `GameManager` | `scripts/core/GameManager.gd` | Stub — currently empty (`_ready` and `_process` are no-ops) |
| `UiManager` | `scripts/ui/UI_Manager.gd` | Comprehensive UI: skill icons, shop, kill feed, hero detail panel (C key), target info, death recap, buff panel, damage/gold/heal popups |
| `CollisionSystem` | `scripts/core/CollisionSystem.gd` | Per-frame entity pushback to prevent overlapping (heroes ← → turrets, minions ← → turrets excluded) |

### Core Scripts (`scripts/core/`)

- **`BattleManager.gd`** — The central game controller (`class_name BattleManager`). Handles:
  - Map creation (ground planes, lane planes, river, high-ground circles)
  - Hero select UI → game start flow
  - Player hero + AI hero creation (one of each role: assassin/mage/marksman/warrior/support)
  - Turret, jungle camp, wall/bush placement
  - Minion wave spawning (3 lanes × 2 teams, with growth tables, siege/super/dragon minion variants)
  - Epic monster timers (Tyrant at 4min, Dragon at 4min)
  - Economy systems: kill/assist gold, tower gold, lane gold sharing, natural gold/exp, jungle item rules, support item rules
  - Input handling: left-click attack order, right-click move, raycasting for ground/target selection
  - Camera: follows player hero, minimap drag/jump override
  - Win condition: crystal destruction → game-over screen
  - Hero configs: `hero_configs` dictionary with base stats for all 17 heroes

- **`EntityDatabase.gd`** — Stub (empty `_ready`/`_process`).

- **`CameraController.gd`** — Standalone camera script (attached to a Camera3D), follows a `@export var target`. Currently unused — BattleManager controls the camera directly.

- **`MapGenerator.gd`** — Alternative map generator (creates a simpler 60×60 grass + river). Not used in the main game; BattleManager has its own `_create_map()`.

- **`CollisionSystem.gd`** — See Autoloads above.

### Entity Hierarchy (`scripts/entities/`)

All entities inherit from **`GameEntity`** (`class_name GameEntity extends CharacterBody3D`):

```
GameEntity
├── Hero (player & AI champions)
├── Turret (defensive structures)
├── Minion (lane creeps)
├── JungleMonster (neutral camps + epic monsters)
├── Bullet (projectile for ranged attacks and skill shots)
├── LinearBullet (directional projectile variant)
├── Wall (terrain obstacle)
├── Bush (stealth zone)
├── HealthPack (regen pickup)
├── TeleportZone (teleport pad)
└── prw (unidentified entity)
```

**`GameEntity`** provides:
- Base stats: `health`, `max_health`, `attack`, `armor`, `magic_resist`, `move_speed`, `attack_range`, `attack_speed`, `body_radius`, `level`
- State effects: slow, stun, knockup, freeze, suppress, silence, grievous wounds
- Shield system (`shield_remaining`/`shield_timer`)
- Marker system for stacking passives (e.g., Zhen Ji freeze, Angela burn, Marco Polo stacks)
- Damage calculation: `take_damage()` with armor/MR reduction formula (`resistance / (resistance + 602)`), penetration, crit detection
- Hunt DoT system (jungle item burn)
- Lifesteal application (physical and magical, with grievous wounds reduction)
- Death handling: `die(killer)` → signals, gold/exp distribution, buff transfer
- Kill assist detection (nearest enemy hero within 12 units)

**`Hero`** (`scripts/entities/Hero.gd`, ~2150 lines) — The largest and most complex class:
- **Stats**: base stats + role-based growth per level (tank/warrior/assassin/marksman/mage/support)
- **Equipment**: 6-slot inventory, `buy_equipment()` with component synthesis, `_apply_equipment_bonuses()` recalculates all stats from items, 100+ unique item passive/active effects
- **Skills**: 3 hero skills + summoner spell + recover, each with cooldowns, mana costs, charge/restore system, upgrade via Ctrl+key or auto-level
- **Hero-specific logic**: Each hero has hardcoded special behavior in `_physics_process()` (Arthur passive heal + W shield rotation, Donghuang orbs, Li Bai sword auras, Zhang Fei transformation + mana, Lanling stealth, Taiyi Q channeling)
- **Combat**: auto-attack with bullet spawning (ranged) or instant (melee), crit, on-hit effects from 20+ items
- **Input**: WASD movement, right-click move orders, left-click attack orders, skill hotkeys 1-3, summoner spell key, item actives (keys 6-0, V, =, -)
- **Post-game stats**: `damage_dealt_to_heroes`, `damage_taken_from_heroes`, `healing_done`, `cc_duration_dealt`, `turret_damage`, `jungle_gold`, `last_hits`, `gold_history`

**Other entity notes**:
- `Bullet.gd` / `LinearBullet.gd` — Projectiles with speed, damage, pierce, slow, red buff burn, team affiliation
- `Turret.gd` — Auto-attacks nearby enemies, has outer/inner/high/crystal tiers with different stats
- `Minion.gd` — Follows waypoints along lanes, attacks enemies in range
- `JungleMonster.gd` — Has `activity_radius` (leash range), `buff_type` for red/blue buff
- `Wall.gd` / `Bush.gd` — Static collision/stealth volumes
- `HeroAI.gd` — AI controller for bot heroes (attached as child of Hero)

### Asset Scripts (`assets/`)

- **`ItemDatabase.gd`** — Massive dictionary of all equipment items with: name, tier (1-4), cost, stat bonuses, `requires` (synthesis components), `passive`/`active` descriptions, category tags. Key functions: `get_item(id)`, `can_build(id, owned)`, `get_synthesis_cost()`, `get_synthesis_tree()`, `get_recommended_items(role)`.
- **`SkillDataBase.gd`** — Dictionary of all skills (hero abilities + summoner spells). Each skill defines: `type` (0=targeted, 1=AoE, 3=linear, 4=dash, 6=shield), `cooldown`, `mana_cost`, `cast_range`, `damage`, `radius`, `duration`, etc.
- **`Skill.gd`** — Skill resource class (`class_name Skill extends Resource`). Properties: `skill_name`, `type`, `cooldown`, `cd_bonus`, `mana_cost`, `power_bonus`, `cast_range`, `cast_time`, `damage`, `radius`, `duration`, `self_displacement`, `shield_amount`, `is_channeling`, `charge`, `restore`, `restore_bonus`.

### UI System (`scripts/ui/`)

**`UI_Manager.gd`** (~1600 lines) handles all in-game UI:
- Skill bar with 8 icon slots (4 skills + summoner + 2 active equipment)
- Shop system (O key): categorized grid (物理/法术/防御/靴子/打野/游走/保命), detail panel, buy/sell, component synthesis display
- Recommended equipment (B key to quick-buy)
- Kill feed (multi-kill announcements, tower/epic monster kills)
- Hero detail panel (C key): team stats, all hero cards with stats/skills/equipment/KDA
- Death recap (auto-shows on death): damage source breakdown with stacked bar charts
- Target detail panel (shows selected target's stats)
- Buff/debuff display panel
- Damage/heal/gold floating numbers (world-space → screen projection)
- Respawn widgets (hero icons with HP rings and respawn timers)

Internal classes: `SkillIcon` (draws cooldown overlay, upgrade indicator), `RespawnWidget` (HP ring + death timer), `DamageChart`.

### Key Mechanics to Understand

1. **Damage formula**: `actual_damage = raw_damage × (1 - resistance / (resistance + 602))` where resistance already accounts for flat and percentage penetration.
2. **Attack speed**: Uses a threshold table (Model A from Honor of Kings) — panel AS% maps to discrete attack interval tiers.
3. **Economy sharing**: Multiple heroes near a minion kill split gold (100%/80%/55%/43%/37% for 1-5 players). Jungle/support items modify this.
4. **Minion growth**: Minion stats interpolate from growth tables at `game_time / 60` minutes, with melee/ranged/siege/super/dragon variants.
5. **Item synthesis**: Buying a high-tier item that requires owned components only costs the difference. Selling refunds 70%.
6. **Buff system**: Active buffs are stored as dictionaries with timers, processed each frame in `_calculate_buff()`. Red/blue buffs transfer on kill.
7. **Hero-specific code**: Each hero has unique mechanics hardcoded with `if display_name == "..."` checks in `_physics_process()`, `_perform_attack()`, and `_finish_casting()`. Adding a new hero requires touching Hero.gd in multiple places plus adding skill definitions to SkillDatabase.

### Assets Not Tracked in Scripts

- `icon.svg` — Game icon
- `.godot/` — Engine cache (shader cache, editor state, import files)
- `scenes/battle.tscn` — The single main scene (binary .tscn format)
- 3D models, textures, and audio are created programmatically (PlaneMesh, CapsuleMesh, TorusMesh, StandardMaterial3D) — there are no imported art assets.
