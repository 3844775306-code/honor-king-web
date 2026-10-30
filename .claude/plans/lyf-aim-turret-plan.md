# 李元芳：目标型技能锁定 / 1技能点塔 / bonus_attack_range / 暗印层数+黄血预告

（已确认范围：**离线 + 联机一起**；桌面目标型技能按「按住技能键进入瞄准、以拖动轮盘/鼠标的角度与目标相对角度计算锁定、松开施放」实现。）

## 一、需求拆解

1. 目标型技能（type 0，如李元芳 1「谍影重重」）可像精准普攻轮盘一样：
   拖动/瞄准方向 → 按「该方向与英雄的相对角度」吸附锁定目标（含塔/兵/野/英雄）。
   现在引擎里拖动吸附已被 `_start_casting` 清空 pending 目标而失效（见下），桌面按下即放无瞄准。
2. 李元芳 1 技能可对**防御塔**使用（挂暗印、AA 叠层、到期爆炸推塔）。
   只允许李元芳 1 技能锁定塔，其他英雄/技能保持不可点塔（维持 HoK 规则，避免亚瑟Q 等跳塔)。
3. 1 技能的 +50 攻击距离改由 **bonus_attack_range buff 计算**（进属性管线，`active_buffs` 聚合，到期自动还原），不再直接改 `attack_range`/手写计时回滚。
4. 暗印命中后在目标身上显示**马可波罗式层数文字**（世界血条 + 英雄头顶血条）。
5. 暗印爆炸前，把将造成的实际伤害对应的目标血条段涂**黄**（预告 = 按 take_damage 同款减伤公式预估，护盾先吸收）。

---

## 二、属性管线：`bonus_attack_range`（先做，供 Q 复用）

现状：`attack_range` 是原始可变字段（GameEntity 初始化 config），recalc 不写它；被 3 处「逐日弓 `attack_range *= 1.25`」（永久、疑似 bug 但维持语义）与旧 Q +50 直接改。

做法（保留逐日既有数值语义，但归一到「底值 ×」以免 recalc 覆盖）：

**Hero.gd**
- 新增字段：
  - `var bonus_attack_range: float = 0.0`（与 `bonus_attack_speed` 同列，~3358）
  - `var _range_base: float = -1.0`（未初始化前 = 攻距底值，懒捕获）
- `_apply_equipment_bonuses()`：重置列表（3590-3595）追加 `bonus_attack_range = 0`。
- `_calculate_buff()`（3364）：与 3368-3378 同列追加 `bonus_attack_range += active_buffs[i].get("bonus_attack_range", 0)`。
- `_recalculate_attributes()`（~3553 后）：派生
  ```
  if _range_base < 0.0:
      _range_base = attack_range - bonus_attack_range
  attack_range = _range_base + bonus_attack_range
  ```
- 新方法 `apply_attack_range_buff(tag, duration, flat)`：同 tag 刷新 else append `{_tag, timer, bonus_attack_range}`，末尾 `_recalculate_attributes()`。
- 新方法 `multiply_attack_range_base(ratio)`：懒捕获底值 → `_range_base *= ratio` → 重算 `attack_range = _range_base + bonus_attack_range` → `_update_attack_range_ring()`。
- 删掉 Q 攻距旧计时回滚（Hero 1351-1356 中 `_lyf_range_timer`/`_lyf_range_bonus` 段，保留 `_lyf_burrow` 段）及声明。

**SkillDataBase.gd `_lyf_q`（2610-2614）**
- 删 `attack_range -= / +=` 三行 → `hero.apply_attack_range_buff("lyf_range", 4.0, 50.0)`（as_haste 那行保留）。

**3 处逐日弓直接乘（改用底值乘法，保持语义）：**
- `scripts/ui/UI_Manager.gd:1519-1520`
- `scripts/entities/ItemPassive.gd:144`
- `ai/tactics/ItemActiveTactics.gd:82`（注意 ratio 用 `AiConfig.SUNSPIRE_RANGE_BOOST_RATIO`）
  各自仍保留 `if hero.attack_range > 500:` 守卫，把乘法换成 `hero.multiply_attack_range_base(ratio)`。

---

## 三、目标型技能锁定（host 主逻辑）

现状关键 bug：触屏拖拽已能 `_pick_skill_target` 选到目标并写 `pending_skill_target_entity`，但 `_start_casting`（2998）立刻置空 → `_finish_casting` type-0（3076-3088）只能走自动索敌（英雄优先），拖拽锁定名存实亡。位置其实已随 `pending_skill_target` 保留，但目标实体被丢、塔被自动索敌排除。

改动：
1. `_pick_skill_target(aim_pos, cast_range)`（1975）：加可选 `max_aim_dist := -1.0`，>0 时跳过 `d > max_aim_dist`（= 支持"悬停小半径吸附"与"轮盘角度"共用同一套"距离瞄准点最近"判定）。
2. 塔门禁 helper：`_skill_target_allowed(t) -> bool`：非 Turret 恒真；Turret 仅 `display_name == "李元芳" and pending_skill_index == 0`。
3. `_start_casting`（2998）：仅当 `skill == null or skill.type != 0` 才清 `pending_skill_target_entity`（type-0 保留触屏/远程已锁实体）。
4. `_finish_casting` type-0 分支：
   - pending 实体存活则用（再经 `_skill_target_allowed` 校验，不通过则丢弃走下一步）；
   - 否则**本地玩家**（`not is_ai`）先做**悬停吸附**：`_pick_skill_target(pos, skill.cast_range, 1.2)`（鼠标指向地面点小半径），非塔/李元芳Q 通过才采纳；无则维持原 `_get_attack_target(...)` 自动兜底。
   - 选中后写回 `pending_skill_target_entity = target`（供 SkillDataBase `_lyf_q` 优先命中「已锁定目标」，避免塔前站一堆兵/英雄时 nearest 抢走印记）。

**SkillDataBase `_lyf_q` 命中段（2618-2630）**：若 `hero.pending_skill_target_entity` 存活且敌对方且在 pos 小邻域（≤1.8m）→ 直接对该实体 `lyf_cast_mark`；否则维持原 nearest 1.2m 兜底。

---

## 四、桌面「按住技能键进入瞄准 / 移动瞄准 / 松开施放」（type 0，host）

意图：与触屏轮盘共用同一定位语义 —— 瞄准方向=鼠标相对自身（屏幕中心→光标 = 拖动轮盘向量），目标=该方向上与英雄的相对角度最近者。

改动（`Hero._handle_skill_input` 一带）：
- type-0 技能键盘**按下**不再立即 `_start_casting`，而是进入 hold 态：记录 `_desktop_skill_hold_index` + 按下时刻，进入既有的每帧 skill-hold 预览分支（2741-2824）：
  - 桌面 aiming 时（`touch_aiming == false` 且 type 0 且处于 hold）：`target_pos` 由鼠标光标算得后做**小半径吸附**（`_pick_skill_target(pos, range, 1.2)`，非塔门禁）；把吸附结果当锁定候选，用 `aoe_fill` 小圈（照触屏小圈样式）+ 可选 `attack_aim_marker` 高亮当前候选；`cast_range_ring` 同步显示。
- 键盘**松开**（`Input.is_action_just_released("skill_%d")`）且 hold 该槽：
  - 若按住时长 ≤ 点按阈值（~0.18s）→ 按旧智能施法（鼠标落点 + 自动索敌兜底）直接施放（保手感）；
  - 否则 → 用最后一帧锁定的候选（若无候选回退自动索敌）写 `pending_skill_target_entity`，`_start_casting(i, skill, 候选/落点位置)`。
  - 施放前仍复核 `silence_timer`/`skill_cast_ready`/沈梦溪·太乙·李白特例等，与触屏松手路径同守卫。
- 保持 type>0 桌面即时施放不变；`is_ai` 不进入该 hold 态（AI 不受影响）。

---

## 五、暗印显示 + 黄血预告（GameEntity 计算 + 两条血条绘制）

**GameEntity.gd**
- 新增 `lyf_mark_sources() -> Array`（去重、valid 的 source 列表）。
- 新增 `lyf_predicted_damage() -> float`（所有印记若现在引爆，各自按 take_damage 同式算 actual 后求和）：
  - 逐 source：`stacks=lyf_mark_stack`；`lv=source.skill_levels[0]`；`base=220+44*max(0,lv-1)`；`raw=(base+source.bonus_attack*0.7)*(1+stacks)`。
  - 减伤镜像 take_damage（694-710）：`res=max(armor - source.flat_phys_pen,0)`（source 必 Hero）→ `reduction=res/(res+602)`；`source.sky_book` 增伤、自身 sky_book 减伤、李元芳被动对非英雄 +5%（`not (self is Hero) and not is_magic`）逐条镜像。
  - 返回**护盾前**的预扣血（血条端再减盾 clamp），爆炸为 `skill_id=-80` 无暴击/无穿透% → 不额外乘。
- 复用：标记层数文本用 `lyf_mark_sources`/`lyf_mark_stack`（0 层显示「暗印」无层数，≥1 显示「N层」）。

**HealthBarControl.gd**（塔/兵/野/史诗通用）
- `_draw()` 血量两段（108-109）之后：算 `doom = clamp(entity.lyf_predicted_damage() - shield_value, 0, current_value)`，`px = doom/max_value*w`；>0 时在血量右尾绘黄：`draw_rect(Rect2(max(health_width-px,0), 0, px, h), Color(1.0,0.92,0.35,0.6))`（画在血量层之上、闪橙/回血之下，避免覆盖新伤反馈）。
- `_draw_markers()`（188-205）：现有 Marco 循环后追加 `lyf_mark_sources()`，文本并入同一条黄字（`"%s %d层"`，0 层则 `"%s 暗印"`）。史诗分支因提前 return 调用同一 `_draw_markers`，自动覆盖；史诗黄段暂不做（分格条太密）。

**HeroInfoControl.gd**（英雄头顶血条）
- 顶部 marker 文本（21-31）追加 LyF source（同格式 `"%s\n%d层"`，0 层 `"暗印"`）。
- HP 实条（150）与白描边（151）之间插入右尾黄段：`doom=clamp(hero.lyf_predicted_damage()-hero.shield_remaining,0,hero.health)`，`px=doom/max_hp*bar_width`。

注：印记本体（挂 / 叠 / 爆 / 到期）已实现在 GameEntity `_process` 与 AA 段，无需改逻辑；仅补预估 API 与展示。

---

## 六、联机同步（NetSession / NetClientBattle）

远程接管下英雄逻辑在 host 跑，host 核心改动自动生效；客户端要同步的是「发送端选目标门禁 + 世界血条里的层数/黄段」。

**NetSession.gd（host 打包）**
- 新增 `_pack_lyf(e) -> Array`：每 source `[display_name, lyf_mark_stack, lyf_predicted_damage 单源]`；并给 `lyf_prediction()`/`lyf_source_pred(source)`（单源预扣，供拆包）。空则 `[]`。
- 打包尾字段：`_pack_hero` 追加 idx14=`_pack_lyf(e)`；`_pack_unit` 在（塔的 under_attack extra 之后）追加 idx8(塔=idx9)=`_pack_lyf(e)`；own 块加 `"lyf": _pack_lyf(h)`。
- C_CAST 守卫：若 `cmd[2]` 目标是 Turret 但 `h.display_name != "李元芳" or idx != 0` → 忽略 target_entity（仅用落点），保持不可点塔规则。
- （客户端无需公式：预测值 host 权威直接发。）

**NetClientBattle.gd**
- `_on_snapshot`（376-386 一带）：按新尾索引读 `v.lyf`（hero idx14 / turret idx9 / minion·jungle idx8，均长度守卫）。
- `_collect_world_bars` 行构造 `_hero_bar_row`/`_unit_bar_row`：透传 `v.lyf`。
- `_draw_hero_bar`/`_draw_unit_bar`：黄段（同 Host 公式，`doom=clamp(Σpred - shield,0,hp)` → px）+ 顶部/底部 LyF 层数字样。
- type-0 目标门禁：
  - `_pick_skill_target_net`/`_type0_smart_target` 结果若为塔 → 仅当 `hero_name=="李元芳" and slot==0` 采纳，否则继续当无候选处理。
  - `_kbd_cast`（键盘悬停/落点）可复用：光标小半径内命中塔（李元芳Q）时发送该塔 nid（host C_CAST 已做双端守卫）。
- own 血条：若客户端有自己英雄的世界条则同样用 `own.lyf` 绘制（找不到即跳过）。

---

## 七、改动文件清单

| 文件 | 内容 |
|---|---|
| `scripts/entities/Hero.gd` | bonus_attack_range 管线、_range_base、攻距 buff/底值乘法方法；Q 旧回滚删除；_pick_skill_target 半径参数；塔门禁；_start/_finish 锁定；桌面 hold-aim |
| `assets/SkillDataBase.gd` | `_lyf_q`：range buff 行替换 + 命中段优先已锁实体 |
| `scripts/entities/GameEntity.gd` | lyf 展示 API（lyf_mark_sources/单源与总 pred） |
| `scripts/ui/HealthBarControl.gd` | 黄段 + 层数字样 |
| `scripts/ui/HeroInfoControl.gd` | 黄段 + 层数字样 |
| `scripts/ui/UI_Manager.gd`、`scripts/entities/ItemPassive.gd`、`ai/tactics/ItemActiveTactics.gd` | 逐日弓改底值乘法 |
| `scripts/net/NetSession.gd` | `_pack_lyf` + hero/unit/own 尾字段 + C_CAST 塔守卫 |
| `scripts/net/NetClientBattle.gd` | 快照取 lyf、血条黄段/层数字样、type-0 塔门禁、kbd_cast 悬停 |

---

## 八、门禁（沿用四道无头门禁）

1. **parse**：`--headless --path . --quit` grep `SCRIPT ERROR|Parse Error`（GDScript 无类型推断错误：凡经 untyped 参数调方法返回 Variant 处不用 `:=`，显式标 `var x: ...`）。
2. **100s battle.tscn 稳定**：`timeout 100 godot --headless res://scenes/battle.tscn` 期望 EXIT=124 无脚本错误。
3. **联机集成**：跑 `scripts/net/net_integration_test.ps1`（**换端口**，别撞 7000 的用户对局），覆盖 snapshot 尾字段长度守卫与 C_CAST 塔路径不报错。
4. （可选）Android export 不炸再收尾。

---

## 九、F5 人工核对清单（交付时给出中文版）

- 选择李元芳进一局；给 1 技能升到可用。
1. **轮盘锁塔**：走位到敌方一塔前，拖动 1 技能轮盘指向塔 → 松开：暗印落在塔上（塔旁 1 米内出现黄段预告 + 「暗印/0层」字样）；AA 塔每次叠 1 层，4 层在塔上爆炸且对塔造成物理伤害；到期未叠满也会自动爆。
2. **悬停即锁/按住瞄准（桌面）**：按住技能键移动鼠标在敌英雄/小兵/塔间扫 → 准星/小圈随目标相对方向吸附并高亮；松手施放到所选目标；只点按(≤0.18s)仍智能施放。
3. **不可点塔保护**：换亚瑟等其他目标型英雄，按住/拖动瞄准塔不会锁定塔（自动索敌忽略塔）。
4. **攻距 buff**：Q 命中后攻击距离 +50 持续 4 秒，结束后精确还原；期间点/再按 Q 刷新时长不叠加不残留；升级/买装/死亡复活后攻距仍正确（派生自底值）。
5. **逐日弓回归**：出逐日弓开主动，攻距 ×1.25 生效且与 Q 的 +50 并存；再开一次仍倍乘、无异常坍缩。
6. **层数与黄段**：敌人头顶血条（HeroInfoControl）与世界血条（HealthBarControl）都显示层数字样；敌方英雄/塔/兵/野身上均出现对应黄段，随护盾变化、扣血/回血实时收缩。
7. **联机**：双开（非 7000 端口）远程接管李元芳：轮盘拖塔可点塔、客户端敌人血条同步黄段/层数。

## 十、验收后交付

- 跑完上述四门禁 → 给中文 F5 核对清单 → 问「需要我继续整理下一个英雄吗？」。
