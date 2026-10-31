# 实现方案：新增英雄「李元芳｜王都密探」

- 定位：射手（远程，配置里归 `role: "射手"`），可走发育路 / 打野（被动对野怪额外伤害天然适配打野）。
- 数据口径：以你贴出的最终资料版为准（Q 每层额外伤害 = 基础伤害同值、攻速 +35→70% 且攻击距离 +50、CD 每级 -0.4/-3.0 等）。
- 全部改动用 GDScript，TAB 缩进，LF。改动集中在 6 个既有文件 + 0 个新场景文件；不改 UI_Manager / HUD / 血条。

---

## 0. 机制→引擎 映射总览（关键近似，均标注）

| 资料说法 | 引擎落法 | 备注 |
|---|---|---|
| 被动「探视野 1s / 同英雄 8s」 | 李元芳**任意伤害命中**时，以受害者为中心 r≈4m 暴露草丛隐身中的敌方英雄 1 秒（每个敌方英雄独立 8s CD，记在李元芳身上） | 引擎无完整迷雾，草丛=隐身；暴露走现有 `vision_expose_timer` 通道 |
| 被动「对非英雄 +5% 物理伤害」 | 伤害公式段：`source是李元芳 && 目标非英雄 && 非法术` → `actual *= 1.05` | 一处全局分支，普攻/技能通吃 |
| Q 印记「爆炸/每层」 | 爆炸总伤 = `(基础 + 0.7×额外攻击) × (1 + 已叠层数)`；施放即 0 层，普攻每层 +1，**满 4 层立即爆**、到期按当前层爆 | 口径见 §3.1 数值示例；倍率收敛为 1 个常量便于日后调整 |
| Q「+攻速 +50 攻击距离 4s」 | 攻速走现有 `apply_attack_pct_buff("as_haste", 4, 0.35+0.07×(lv-1))`；攻击距离在 `Hero` 上加 50 并 4s 后还原（用计时器还原，重施刷新） | 距离改动是真实 `attack_range` 增减（cm 风格数字） |
| W「无法被选中」 | 位移落点后 `wd_timer`（复用李白剑阵/名刀同款）置约 0.7s：期间免伤、免控、清空已有眩晕；模型短暂隐藏；并给普攻/智能施法索敌补一条「跳过 `is_untargetable_by_enemies()`」过滤 | 引擎无完整锁定链路；用「免疫 + 索敌过滤」近似，详见 §3.4 |
| W 飞轮 | 用 `create_bullet` 线性子弹打 **纯物理** 一段（命中伤害+2s 减速），由目标侧普攻命中逻辑逐层叠印记，标记由被动触发的视野在 victim 周围生效 | 燃痕见下 |
| W 燃痕 | 位移起点→终点画长条形带火视觉；每 0.25s 一次 tick，对距线段 <0.6m 敌人造成 tick 伤害并刷新减速，共 2.9s | 做成线段采样而非一格一格火坑，省节点 |
| R「撞击」 | 自施法点朝目标方向、宽 ±0.9m 的直线上命中第一个敌人结算撞击伤害 | 真实是飞轮沿途伤害；简化为一发命中，视觉仍做飞轮飞盘 |
| R「终点风暴 5.4s」 | 在施放终点放一个风暴视觉圈；每 0.5s tick 对半径 r_out 内敌人结算持续伤害 + 减速；**内圈 (r_in) 伤害×2**；命中已带暗印目标时**叠 1 层**（不会无中生有建印记） | r_out/r_in 见 §3.5 常量 |
| 伤害类型 | 全部 **物理**（`is_magic=false`，走护甲减免；系数为 额外攻击） | 与表一致 |

> 若你觉得以上任何一条近似不可接受，逐条指出，我按你口径改单点，不影响其余落点。

---

## 1. 数值录入表（新增前先想清楚，落地时照抄）

### 1.1 BattleManager `hero_configs`（位于 `scripts/core/BattleManager.gd`，字典起始约 1583，仿 狄仁杰 条目加一条）

```gdscript
"李元芳": {
    "name": "李元芳", "role": "射手",
    "max_health": 3257, "attack": 165, "attack_range": 700,
    "move_speed": 360, "max_mana": 600,
    "skills": ["liyuanfang_q", "liyuanfang_w", "liyuanfang_r"], "summoner": "flash",
    "hp_reg": 37, "mana_reg": 15
},
```

- `attack_range=700`（cm 风格：×0.01 → 7m 普攻射程，介于射手档；资料只写「远程」，700 是留出 Q +50 的距离空间）。
- `base_armor/base_magic_resist` 引擎在 `Hero.setup()` 里写死 150/75，**不需要**配（资料 150/75 正好一致）。
- 暴击率 0% / 暴击效果 185% 由射手默认（`base_crit_damage=1.85`）自动覆盖，无需配置。
- `base_as` 射手默认 1000，无需配 `attack_speed`。
- `valid_heroes` 列表（约 583 行）追加 `"李元芳"`；`roles_order`（约 1826）若按字典驱动会自动收入，落地时确认 AI 组队可选他。

### 1.2 技能成长表（写入 `SkillDatabase._init_skills()`，与现有技能定义同处函数尾部）

| 字段 | Q 谍影重重 | W 刃遁 | R 无间刃风 |
|---|---|---|---|
| id | `liyuanfang_q` | `liyuanfang_w` | `liyuanfang_r` |
| type | 0（单体锁定） | 4（位移 dash） | 3（方向/线性） |
| cooldown | 10 | 10 | 30 |
| cd_bonus（每级-） | 0.4（Lv1 10 → Lv6 8） | 0.4 | 3.0（Lv1 30 → Lv3 24） |
| mana_cost | 60 | 65 | 110 |
| power_bonus | 0 | 0 | 0 |
| cast_range | 6.5（施法可选中敌人范围） | 6.0（仅决定 dash 方向目标点） | 7.5 |
| duration | 4（印记/增益持续） | 0（瞬发） | 5.4（风暴） |
| self_displacement | — | 4.5（dash 距离，米） | — |
| damage（表盘基准，仅存档展示用） | 220 | 260 | 320/140 |
| bonus_ratio（表盘展示） | 0.7 | 0.8 | 1.0 / 0.4 |
| skill_name | `谍影重重` | `刃遁` | `无间刃风` |

**攻速/减速/数值在 `apply_skills` 里按 `hero.skill_levels[i]` 现算**（与全游戏既有风格一致），公式：
- Q：`base = 220 + 44×(lvQ-1)`；`as_pct = 0.35 + 0.07×(lvQ-1)`（→70%）
- W：`fly = 260 + 52×(lvW-1)`；`tick = 110 + 22×(lvW-1)`；`slow = -(0.15 + 0.03×(lvW-1))`（→ -30%）
- R：`hit = 320 + 160×(lvR-1)`；`dot = 140 + 70×(lvR-1)`；`slow = -(0.25 + 0.125×(lvR-1))`（→ -50%）
- 倍率：Q=0.7×额外攻击、W 飞轮 0.8×、W 燃痕 tick 0.3×、R 撞击 1.0×、R 风暴 dot 0.4×（全是物理）

---

## 2. 文件改动清单（按依赖序）

| # | 文件 | 改动性质 |
|---|---|---|
| A | `scripts/entities/GameEntity.gd` | +印记存储/结算、+take_damage 李元芳 hook、+5% 分支、mark 到期引爆（_process） |
| B | `scripts/entities/Hero.gd` | +dash 起点记录、+Q 攻击距离 buff 计时还原、+W 钻地视觉/不可选中计时、索敌过滤补 2 处 |
| C | `assets/SkillDataBase.gd` | +3 条技能定义（_init_skills）、+`apply_skills` 李元芳 match 块（Q/W/R 全部行为）、+get_skill_icon_damage / get_skill_fx 各 1 臂 |
| D | `scripts/core/BattleManager.gd` | +config 条目、+valid_heroes |
| E | `assets/ItemDatabase.gd` | +`get_recommended_items` 李元芳 三套 build |
| F | （不改）模型 | `_load_hero_model` 无李元芳 → 自动回退胶囊体并按阵营染色，无需新增美术资源 |

---

## 3. 机制实现细节

### 3.1 GameEntity：暗印印记系统（受害者身上存状态）

在 `GameEntity` 加成员（victim 可能是英雄/小兵/野怪/塔，所以放基类）：

```gdscript
var lyf_marks: Dictionary = {}   # source(李元芳Hero) -> {"stacks": int, "timer": float, "dmg1": float}
```

辅助函数（放 marker 区附近，约 326-341 行后面）：
- `lyf_stack_count(src) -> int`
- `lyf_add_mark(src)`：目标已标记→`stacks+1` 并 `timer=4`；未标记→建 `{stacks:1, timer:4}`；若 `stacks>=4` → 立刻 `lyf_detonate(src)`。
- `lyf_detonate(src)`：层数保留为 N；清印记条目；对**以自身为中心 r=1.6m 内所有敌队单位**结算爆炸（物理、`skill_id=-80`），伤害 = `(base + 0.7×src.bonus_attack) × (1 + N)`（口径见 §0，倍率集中为顶层常量，方便你把「每层+1 份」改成「每层×25%」）。

在 `GameEntity._process`（约 406 行 markers 段旁边）加：遍历 `lyf_marks`，`timer -= delta`，`<=0` 时 `lyf_detonate(src)`。

> 引爆计数口径：施放 Q 只上「0 层」印记不立刻结算；普攻（`skill_id==0`、非魔法）命中已带该源印记的目标时 `+1 层` 并刷新 4s；4 层/到期引爆。示例（Lv1、无额外攻击）：0 层爆 = 220；4 层爆 = 220×5 = 1100 —— 若你不认可这个倍率，改 §3.1 的倍率常量 2 行即可，其余不动。

### 3.2 GameEntity.take_damage 内新增李元芳分支（约 547-660 区域）

1. **AA 叠层**（放在马可波罗块前后、普攻判定段里）：
   ```gdscript
   if source is Hero and source.display_name == "李元芳" and not is_magic and skill_id == 0:
       if lyf_stack_count(source) > 0:
           lyf_add_mark(source)
   ```
2. **被动 +5% 物理对非英雄**（放在 `actual` 算完后、暴击判断附近）：
   ```gdscript
   if source is Hero and source.display_name == "李元芳" and not (self is Hero) and not is_magic:
       actual *= 1.05
   ```
3. **被动探视野**（放在「攻击暴露视野 2s」旁，约 541 行）：凡 `source 是李元芳` 且 `self.health>0` 且该目标为实体（英雄/野怪/兵），以其位置为中心 r≈4m 扫草丛敌英雄，未过 8s CD 的 → `vision_expose_timer = max(..., 1.0)`，8s CD 记在李元芳身上（`Hero` 一个 dict，键=敌方英雄）。

### 3.3 Hero：Q 的攻击距离 buff

顶部加 2 个成员 `var _lyf_range_bonus := 0.0`、`var _lyf_range_timer := 0.0`。
- `apply_skills` Q 分支调 `hero._apply_q_buff()`：先还原旧 bonus → `attack_range += 50`，记 `_lyf_range_bonus=50, _lyf_range_timer=4.0`；攻速 buff 用 `hero.apply_attack_pct_buff("as_haste", 4.0, as_pct)`。
- `Hero._physics_process`（约 1153 行，减速计时区附近）加计时还原：
  ```gdscript
  if _lyf_range_timer > 0:
      _lyf_range_timer -= delta
      if _lyf_range_timer <= 0 and _lyf_range_bonus != 0:
          attack_range -= _lyf_range_bonus
          _lyf_range_bonus = 0.0
  ```

### 3.4 W 刃遁（`apply_skills` 的 id=2 分支；skill 数据 type=4）

- **dash 起点**：`Hero._finish_casting` 的 type4 分支（约 3016-3022）在位移前记 `dash_from = global_position`（新成员 `var dash_from := Vector3.ZERO`，一行通用改动，日后英雄也能用）。
- apply 里拿 `start=hero.dash_from`、`end=hero.global_position`、`dir=(end-start).normalized()`（兜底 `Vector3.FORWARD`）。
- **飞轮命中**：朝 `start + dir×7m` 放 1 颗 `create_bullet(物理)`，命中 `fly` 伤 + `apply_move_pct_buff("ms_slow", 2.0, slow)`。子弹本体带一圈旋转飞盘视觉（MeshFactory 圆盘+自转）。
- **钻地无法选中**：设 `hero.wd_timer = max(hero.wd_timer, 0.7)`；同时置 `hero._lyf_burrow=0.7` 并**隐藏模型**，计时到 0 显示模型（在 §3.3 计时还原处一并处理；隐藏只动视觉不触发任何逻辑副作用）。wd_timer 自带免伤/免控/清眩晕（现成代码 500-504、1332 行）。
- **燃痕**：start→end 画一条扁长半透明 BoxMesh（长约 dash 距离、宽 0.6m、浮地 0.05m、橙色/红焰，2.9s 渐隐）；循环 `for 11 次：await 0.25s`，每次采样线段 ≤0.6m 的敌队单位，结算 `tick` 物理伤害 + 1s 减速。结束后释放视觉节点。

### 3.5 R 无间刃风（`apply_skills` id=3 分支）

- 方向 `dir=(pos - hero.global_position).normalized()`；`pos` 为 0 时用正前方 7.5m 兜底。
- **撞击**：start→pos 宽 ±0.9m 采样，取最近敌方单位结算 `hit` 伤害（物理，`skill_id=-82`）；顺带一个飞盘前飞的视觉。
- **终点风暴**：以 `pos`（或实际终点）为中心放 5.4s 风圈视觉（内圈实色 + 外圈半透 + 缓慢旋转的刀片/粒子）；`for (5.4/0.5=10) 次：await 0.5s` 每 tick：
  - 取 r_out=3.0m 内敌队单位；
  - `dot_eff = dot × (2.0 若 dist≤r_in=1.5m else 1.0)`，物理伤害 `skill_id=-81`；
  - `apply_move_pct_buff("ms_slow", 0.8, slowR)`；
  - 若该目标身上已有此源的暗印 → `lyf_add_mark`（叠 1 层，**不无中生有**）。
- 结束后释放风圈节点。

### 3.6 不可选中过滤（让 AI/智能施法不打钻地中的元芳）

在 `Hero._get_attack_target` 两处最优血扫描（约 1852、1885 行）各补一行，位于现有 `is_invisible_to_enemy` 判断旁：
```gdscript
if (ent as Hero).is_untargetable_by_enemies(): continue
```
（manuall 目标脱锁段约 1824 行也补同一条件——目标钻地即脱锁。）此改动同时利好李白等旧 wd 用法，范围小、无副作用。

### 3.7 SkillDatabase apply_skills 李元芳分支骨架

在 `apply_skills` 主 match（约 20 行区）里加 `match display_name`（全游戏既有结构），`match skill_id` 三臂分别调上面 §3.1-3.5 逻辑。里面统一开头取 `lv` 沿用函数首部已有的 `level` 变量对应技能槽。

- **Q(id=1)**：`_apply_q_buff()`；找目标（优先取目标点 pos 附近 ≤1.2m 的敌人，或 `hero._get_attack_target(cast_range)`），命中则调 `target.lyf_add_mark(hero)`（建 0 层印记并计时）并做标记小视觉。
- **W(id=2)**、**R(id=3)**：按 §3.4 / §3.5。
- 视觉一律用现有 `MeshFactory.create_*` / `_create_ring` 之类程序化节点，不放外部资源。

### 3.8 UI 资料联动

- `get_skill_icon_damage`（约 1859 起）：加 李元芳 臂。返回 Q=220+0.7额外攻击、W=260+0.8额外攻击（飞轮段）、R=撞击 320+1.0 额外攻击 与 风暴 140+0.4 额外攻击（沿用既有物理射手取值方式，如 孙尚香/狄仁杰 的分支）。
- `get_skill_fx`（约 2041）：按李元芳返回技能描述文案（从 `sk` 取 CD/蓝耗/等级缩放，风格同旧）。

### 3.9 ItemDatabase 推荐出装（三套）

在 `get_recommended_items`（约 647 行）加 `"李元芳": [...]`。id 需经落地前在 `ItemDatabase` 中按中文名反向校验一次（下列为已核实存在的 key + 2 个待核 key）：

- **发育/打野顺风**：`["greed_blade" 贪婪之噬, "swift_boots" 急速战靴, "infinity_edge" 无尽战刃, "dawn" 破晓(落地核名), "bloodthirster" 泣血之刃, "famous_blade" 名刀·司命(落地核名)]`
- **均势走 A/输出**：`["swift_boots", "infinity_edge", "shadow_blade" 影刃, "sage_power" 宗师之力, "bloodthirster", "breaker" 破军]`
- **逆风抗压**：`["swift_boots", "world_end" 末世, "omen" 不祥征兆, "mage_robe" 魔女斗篷, "revive" 贤者的庇护/复活甲(落地核名), "famous_blade"]`

> 落地实现时以 ItemDatabase 里实际 `name` 反查确认 `dawn`/`famous_blade`/`revive` 键名；键名与名字不一致就以名字反查到的真实键为准。

---

## 4. 新增模型 / 视觉方案（全程序化）

- 英雄本体：无专属模型 → 回退胶囊体，按团队染色（全游戏已支持）。
- Q：目标身上「暗印」浮标（小六边形/飞刀纹章，随层数变色，1→4 层递增大小）；爆炸时小范围爆闪。
- W：飞轮=自转圆盘子弹；钻地时模型隐藏、出现一道土浪/下陷残影；燃痕=橙色光带+火星。
- R：飞轮前飞→终点卷起 5.4s 旋转风刃环（内圈更亮），每 tick 命中给微闪。

全部用 MeshFactory 现有 API，不引入新美术资源、不改 scene。

---

## 5. 行为兜底 / 边界检查（实现完自查）

1. AI 元芳用 Q 打空（无目标）时只给自己上 buff，不崩溃、不加印记 → 已用 pos 判空。
2. Q 标记的小兵被 4s 前清掉 → 到期 detonate 前 `is_instance_valid` + `health>0` 双查。
3. W 施放时目标点在墙上 → dash 方向兜底、仍位移、无敌人命中不报错。
4. 印记层数上限 4：`lyf_add_mark` 内先判 `>=4` 直接 detonate。
5. R 风暴期间元芳死亡/复活：沿用全游戏 `await` 模式（王昭君 R 同款），自然随技能节点销毁，不额外处理。
6. 多目标同 tick 引爆的连环 AoE：引爆用 `skill_id=-80` 等负数不与任何 on-hit（只看 `skill_id==0`）冲突；爆炸不会再叠印记（AA 分支只认 skill_id==0）。
7. 平衡常量全部集中：Q 层数倍率、Q 距离 +50、W 钻地 0.7s/燃痕半径 0.6/2.9s、R 内外圈 1.5/3.0 —— 文件顶部一个常量块，日后好调。

---

## 6. 落地顺序与验证

落地顺序（每步可独立 parse）：
1. D：BattleManager config + valid_heroes → 能选到「李元芳」进对局（空技能也能玩，先跑通整条链路）。
2. A：GameEntity 印记系统 + 5% + 视野 + take_damage hook（此时只服务于被动与普攻）。
3. B：Hero 的 Q 距离 buff / dash_from / 钻地 / 索敌过滤。
4. C：技能定义 + apply_skills Q → W → R（每加完一个都过 parse）。
5. E：三套出装；UI 两臂（icon damage/fx）。

门禁（沿用你的无测试 gate 流程，本改动不碰网络/导入，跑前两道即可，如顺手可补 90s 对局稳定性）：
- **parse gate**：`"C:\Users\18749\Desktop\Godot_v4.5.1-stable_win64.exe" --headless --path . --quit` → 退出码 0、无 `SCRIPT ERROR`/`Parse Error`。
- **battle smoke**：headless 载入 `res://scenes/battle.tscn` 约 90-100s，预期超时退出码 124 = 稳定无崩溃（不复用 7000 端口的网络集成脚本）。
- **F5 手测清单**（你来做）：选人界面选到李元芳；打野区/清线被动 +5% 跳字；Q 标野怪 4 下普攻后连爆 5 段数字、攻速/射程 4s 变化；W 位移穿墙钻地期间被塔/英雄普攻不掉血；R 放风暴后目标持续掉血减速、内圈数字约为外圈 2 倍、对已 Q 目标逐层涨印记；三套推荐出装 B 键可一键购买成功。

## 7. 不做的事（本次范围外）

- 不做专属原画/glb 模型、不做语音、不做新版「影袭/飞镖指向指示器」精细瞄准（Q 走现成 type0 锁定、R 走现成方向施法）。
- 不改网络同步（本改动仅本地单机；NetSession 对新增英雄无感知，后续接网任务若需要再补快照字段）。
- 不新增自绘 UI 页（铭文/连招页属于资料文档，非代码）。
