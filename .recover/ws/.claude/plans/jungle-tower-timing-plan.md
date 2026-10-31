# 野怪/空间之灵/传送阵 与 防御塔机制 修改计划

用户需求（原句拆分 6 项）：
1. 野怪出现时间为 30 秒；
2. 野怪周围墙在开局就需要出现（尤其是 主宰/暴君 龙坑周围的墙）；
3. 空间之灵 60 秒出现、刷新间隔只有 60 秒、4 分钟后不再刷新、10 分钟后传送阵消失、击败空间之灵全队额外平分 50 金币；
4. 防御塔被摧毁后，减速攻击范围内的所有敌方小兵（1塔 30% / 2塔 60% / 高地塔 90% 移速，持续 3 秒）；
5. 越塔保护：在敌方防御塔攻击范围内的英雄，对敌方英雄造成的伤害降低 25%（4 分钟后衰减为 10%，10 分钟后为 5%），需显示 buff 图标（与野区保护 buff 图标同款）；
6. 防御塔免疫暴击。

**AskUserQuestion 已确认的口径**：
- 越塔减伤仅对“英雄”目标生效（王者式保护被越塔的英雄），buff 图标显示在越塔者身上。
- “全队平分 50 金币” = 全队 5 人平分，每人 +10。
- river_spirit（镜像河灵 @(58,58)）**不是**空间之灵：30 秒首刷、死亡后不再刷新；不给团队金币、不开传送阵。
- 传送阵维持“击杀空间之灵才开阵”，但开出的阵持续到 10:00 才消失（不再 30 秒）；重复击杀不重复开阵（已存在则跳过）。

---

## 一、野怪出生计时（普通 30s / 空间之灵 60s / 河灵 30s 首刷）

现状：`BattleManager._create_jungle()`（`net` 线 249 / 单机 `_start_game` 275）在开局即 `add_child` 全部野怪。改为“延时物化”，但 **营地中心仍立即登记**（供开局的弧形墙 + PathFinder 用）。

- `BattleManager` 新增：
  - 常量 `JUNGLE_FIRST_SPAWN := 30.0`、`SPATIAL_FIRST_SPAWN := 60.0`；
  - 字段 `var _pending_jungle_spawns: Array = []`。
- 重构 `_spawn_jungle_group(type, config, center, count, delay := JUNGLE_FIRST_SPAWN)`：
  - 循环 `count` 次立即把 `center` 追加进 `jungle_camp_positions`（保持现状：数量与现有重复一致，墙照常生成）；
  - `delay > 0` 时把 `{type, config(config.duplicate), center, count, at: delay}` 推入 `_pending_jungle_spawns` 并 `return`（**不**在 0 秒 add_child）；
  - 新增 `_materialize_jungle_group(type, config, center, count)`：承载现有 `_spawn_jungle_group` 的实体创建体（match buff/击杀赏金 → `JungleMonster.new` → `setup` → 加活动环 → `add_child` → 记入 `jungle_monsters`）。`_create_jungle` 中空间之灵调用传 `delay = SPATIAL_FIRST_SPAWN`，其余不传（默认 30）。
  - 实体化时对 `type == "spatial_spirit"` 设 `monster.respawn_time = 60.0`（河灵 river_spirit 无需设——死亡不再刷新，见 JungleMonster）。
- 新增 `_update_pending_jungle_spawns()`：倒序遍历 `_pending_jungle_spawns`，`game_time >= at` 时物化并移除。
  - 挂到 `_physics_process` 里 `game_time += delta` 之后（~line 2335 区域）。
- 河灵 `river_spirit` 走默认 30s 首刷，但在 `JungleMonster.die` 里死亡后不再刷新（见下）。

> 不加任何“开局隐形怪在 world 里”的中间态，从源头避免 0s 可被点选/追击/击杀。

## 二、龙坑（主宰/暴君）墙体开局生成

现状：史诗龙 `_spawn_epic` 只有活动环（radius 8），**无坑墙**；`_generate_jungle_arc_walls` 只遍历 `jungle_camp_positions`（不含龙坑）。

- 新增 `BattleManager.EPIC_PIT_CENTERS := [Vector3(24,0,26), Vector3(-24,0,-26)]`（普通/暗影/风暴均刷这两个坑，见 `_spawn_epic`/`_spawn_storm_dragon`）。
- `_generate_jungle_arc_walls()` 在现有 for 之后追加：对每个坑心调用新辅助 `_add_epic_pit_walls(center)`：
  - 嘴朝地图中心（河道/中路方向）：坑→原点方向角 `a_m = atan2(-center.z, -center.x)`；墙体弧心取对侧 `a_block = a_m + 180°`；
  - `_add_arc_walls(center, a_block, 240.0, 8.6, count)`，其中 `count = maxi(8, int(8.6 * deg_to_rad(240.0) / 0.8))`（≈45，密度与现有营地弧墙一致）；
  - 仍走 `_add_wall`（自动跳过高地内部 / 草丛 1m 内），因此两处现有调用点（net 253 / 单机 282）后都会在 **PathFinder.build_navigation_map()** 之前把坑墙烤进导航。

> 现普通营地坑墙本来就是开局生成（camp center 即注册），用户强调“尤其是主宰/暴君周围”即指这两处漏网的坑。

## 三、空间之灵 + 传送阵 + 团队 50 金币

`JungleMonster.die()`（402-436）：

1. **传送阵**（现 429-432，仅 spatial_spirit、杀后开 30s 阵）：改为
   - 仍要求 `killer is Hero`；新增 `bm`（已在 408 取过）判定：
   - `bm.game_time >= 600.0` → 不开阵（10 分钟后不出现）；
   - 扫 `get_tree().get_nodes_in_group("teleport_zones")`，若有任意 zone 距本尸 < 6m → 不重复开；
   - 否则 `TeleportZone.new()`，**`zone.duration = 600.0 - bm.game_time`**（从开启起持续到 10:00 消失，而非 30 秒），再放置。
2. **团队 +50 平分**：空间之灵被击杀（`killer is Hero` 分支内）调用新 `bm.grant_team_split_reward(killer.team, 50)`。
3. **刷新规则**（`await respawn_time` 之前加分支）：
   - `spatial_spirit`：若 `bm.game_time + respawn_time > 240.0` → `queue_free(); return`（4 分钟后不再刷新；每次死后 60s 内到 4:00 的照常）；
   - `river_spirit`：`queue_free(); return`（死亡后不再刷新，30s 首刷一次性）。

`BattleManager`：
- 新增 `func grant_team_split_reward(team: int, total_gold: int)`：数 `heroes` 组里同队英雄数 `count`，`count>0` 时每名 `add_gold(int(total_gold / count))`（50/5=10，整除）。

`TeleportZone.gd` 不改：`duration` 本就外部可设（默认 30）。

> 10 分钟上限只影响 9:xx 击杀 → 阵自然到 10:00 消失；此前击杀阵会跨过 4-10 分钟继续可用（已开阵在 4 分钟后空间之灵不再刷也仍在）。

## 四、防御塔被摧毁 → 残骸减速带

- 新增 `scripts/entities/TurretWreck.gd`（`class_name TurretWreck extends Node3D`）：
  - 字段 `team`、`radius`（= 塔原攻击半径 8.9）、`slow_pct`、`tick`；
  - `_ready`：画一条灰色半透明 TorusMesh 环（半径 ≈ radius，象征已毁塔的减速残骸）；
  - `_physics_process`：`tick` 每 0.3s 触发一次——遍历 `get_tree().get_nodes_in_group("minions")`，对 `m is Minion and m.team != team and m.health > 0 and global_position.distance_to(m.global_position) <= radius` 的敌人调 `m.apply_move_pct_buff("tower_wreck", 3.0, -slow_pct, true)`（同 tag 重施加=刷新 3s，离开范围 3s 后自然消除，与现有移速 buff 体系一致）。
- `Turret.gd.die(killer)`：在 `crystal`/`high` 处理后、`super.die(killer)` 之前：
  - `display_name != "crystal"`（水晶被毁即终局，不需要减速带）时取 `bm`，`slow_pct = {"outer": 0.3, "inner": 0.6, "high": 0.9}.get(display_name, 0.9)`，调 `bm.spawn_tower_wreck(team, global_position, slow_pct)`。
- `BattleManager` 新增 `func spawn_tower_wreck(team:int, pos:Vector3, slow_pct:float)`：实例化 `TurretWreck`，赋 `team/radius(8.9)/slow_pct`，`position = pos`，`add_child`。

## 五、越塔保护（减伤 + buff 图标）

**判定/数值**（`BattleManager` 新增，供伤害与 UI 同源）：
- `func hero_under_enemy_tower(hero: GameEntity) -> bool`：扫 `turrets` 组中 `t is Turret and t.team != hero.team and t.health > 0`，且 `t.global_position.distance_to(hero.global_position) <= t.attack_range * 0.01`（塔射程 8.9m）。
- `func tower_dive_factor() -> float`：`0.75 if game_time < 240.0 else (0.9 if game_time < 600.0 else 0.95)`。

**伤害**（`GameEntity.take_damage` 592-601 野区保护块之后追加）：
```gdscript
# 越塔保护：身处敌方防御塔攻击范围内的英雄，对敌方英雄造成的伤害按阶段降低
#（前4分钟25% → 4-10分钟10% → 10分钟后5%）；buff 图标与野区保护同源（见 UI_Manager.collect_buff_rows）
if bm and source is Hero and self is Hero:
    if bm.hero_under_enemy_tower(source):
        amount *= bm.tower_dive_factor()
```
（`self is Hero` 限定目标=被越塔保护的英雄，命中“仅对敌方英雄”口径。）

**图标**（`UI_Manager.collect_buff_rows`，野区保护块 ~1900-1907 之后对称追加）：
- 复用已取的 `jg_battle`（BattleManager），若 `jg_battle.hero_under_enemy_tower(hero)`：
  - `pct = int((1.0 - jg_battle.tower_dive_factor()) * 100)`；
  - `game_time < 240`：`rem = 240.0 - game_time, tot = 240.0`；
  - `game_time < 600`：`rem = 600.0 - game_time, tot = 360.0`；
  - 否则 `steady = true, rem = tot = 0.0`；
  - `_push_icon(top_cfgs, "tower_dive", "越", Color(0.98, 0.62, 0.35), "越塔保护", <按阶段说明“对敌方英雄造成伤害降低%d%%，…秒后衰减为…”> + 提示文案, rem, tot, steady, "%d%%" % pct)`。
- 该函数是单机玩家 buff 行与主机 NetSession own.buffs（联网被接管英雄）的同一数据源，联网图标自动同步，无需改 NetSession/NetClientBattle。

## 六、防御塔免疫暴击

暴击翻倍发生在攻击方出手瞬间（`Hero.gd` 普攻主节 ~2296-2301 `dmg *= actual_crit_damage`），故在源头禁止：
```gdscript
var is_crit = randf() < actual_crit_chance
if wukong_leap:
    is_crit = true
# 防御塔免疫暴击：任何暴击判定对防御塔不生效（孙悟空强化普攻同样不暴击塔）
if target is Turret:
    is_crit = false
if is_crit:
    dmg *= actual_crit_damage
```
再于 `GameEntity.take_damage` 暴击判定段（~718-728）补受害者侧兜底：`if self is Turret: is_crit = false`（普攻以外的杂项暴击来源不会对塔显示/上报为暴击）。

---

## 验证

**四道无头门禁**（无测试套件，沿用仓库约定）：
1. parse：`godot --headless --path . --quit` 后查 `EXIT=0` 且无 `Parse Error`/`SCRIPT ERROR`（不向 stdout 打中文触发误报）；
2. 100s 浸泡：`Start-Process godot battle.tscn` 后 100s 结束，进程应 ALIVE、无 `SCRIPT ERROR`；
3. Android：`godot --headless --export-debug "Android" build/honorking.apk`（**必须 export-debug**，release 缺发布密钥库必 code=1）；
4. 集成：`pwsh -File scripts/net/net_integration_test.ps1 -Port 7817`（**绝不跑 7000**——撞用户对局）。

**并发提醒**：不触碰 `scripts/net/NetSession.gd` / `NetClientBattle.gd`（peer `attack-passive-display [6ae00f]` 在改，WIP 会阻塞集成/export parse）。若其 WIP 把门禁打红：SendMessage 通知 peer，watch net_client 编译直至净，再复跑。

**F5 人工核对清单**（交付时给中文逐项）：
- 0:00 龙坑有墙、常规营地有墙无怪；0:30 营地怪全体出现；0:60 空间之灵（河灵 0:30 首刷）。
- 击杀空间之灵：全队每人 +10 弹出、传送阵出现并**一直**在（到 10:00），再杀不叠加。
- 拆塔后：该塔范围有灰色环，敌方小兵入内明显减速（1塔30/2塔60/高地90）。
- 我方/敌方英雄越塔打人：自身出现“越塔保护”图标，面板数值随 4/10 分钟衰减；打塔不清图标（只对英雄生效）。
- 暴击装打塔：塔不掉暴击伤害/不飘暴击字。
- 4:00 后空间之灵不再刷；10:00 传送阵消失。
