# 第二轮机制修正计划：元流之子 W锁敌 / Q击退 / 流衰减 + “技能视作普攻”装备触发

用户口径（已逐条澄清）：
> 元流之子2技能是**锁敌型**而非线性；「流」若未使用 → **5秒后先失1层，之后每秒1层**，直到使用流（普攻或技能，**获得/消耗都会重置** 5 秒窗口）；1技能有**击退**效果；3技能**每3支箭视作1次普攻**，可触发普攻类装备（闪电匕首等）；其余英雄中“视作普攻”的技能同样生效（狄仁杰1/2、马可1/3）。
补充澄清：破釜=纯单体必中（锁定选中/最近敌人，cast_range 6.5m；无目标甩空弩箭）· 每3发算1次 · Q为范围内全体击退(约1.5m+0.3s短击飞)。

验证：无测试套件 → 四道无头门禁：parse / battle.tscn 100s(exit 124) / Android export / net integration **-Port 7817**（绝不用7000）。

---

## A. 破釜之箭 → 纯单体锁敌（assets/SkillDataBase.gd `_yuanliu_w` 2880-2952 整体重写）

现状：12-tick 直线扫射、非英雄贯穿击退、敌方英雄挡停 —— 全部删除。

重写为：
1. **取锁**：`hero.pending_skill_target_entity`（_finish_casting type0 已填，Hero.gd:3218）。
   - 无效/同队/已死 → 兜底 `hero._get_attack_target(6.5, false)` 取最近敌方单位；仍无 → 空放：只播一支出膛即灭的水色短箭（前方 5m 飞行 ~0.3s，无伤害）后 return。
2. **伤害/命中**：dmg 公式不变 `int(480+96*(lv-1)+hero.bonus_attack*1.2)`；主箭**追踪必中**：Tween 式前导球 0.5s 内逐帧 `global_position` 追锁目标当前位置（每 0.04s 一跳，目标被击飞/位移也不脱靶），到达后若目标仍存活且敌方 → 单次 `e.take_damage(dmg, hero, false, -65, 0)`。
3. **命中特效**：锁目标受 **1.5m 小击退**（自施法原点推开，y 归 0.5）+ 0.3s `knockup_timer`（Turret 跳过击退）。此前“非英雄击退/英雄格挡”整段逻辑删除。
4. **保留**：`Hero._finish_casting` 中 2.5m 摇杆滑步(3193-3197)、流连发(4层/3166-3175)、连发窗口、凌空段——一律不动。
5. 技能定义无需改：`yuanliu_w` 已是 `type=0; cast_range=6.5`（SkillDataBase 3492-3496），type0 锁敌解析已走通。

## B. 汇流为一 → 范围击退（SkillDataBase `_yuanliu_q` 2846-2850 伤害循环内）

命中判定 `dist<=3.5` 命中后，除 Turret/Wall 外每个受击目标：
```
var dir2 := (平铺目标坐标 - c0); 若 |dir2|<0.01 用 目标相对施法者方向
目标.global_position = 平铺位置 + dir2.normalized()*1.5（y 归 0.5）
e.knockup_timer = maxf(e.knockup_timer, 0.3)
hero.cc_duration_dealt += 0.3（若 e is Hero）
```
其余（伤害量/自疗/友军加成/流+5+N/冷却减半/水流漩涡视觉）不动。
在 2868 `hero.yuanliu_flow = mini(...)` 之后追加 `hero.yuanliu_flow_activity()`（见 C）。

## C. 「流」衰减（scripts/entities/Hero.gd）

1. **字段**（314 行元流块后）：`var yuanliu_flow_idle: float = 5.0`（距首层流失剩余，活动刷新）。
2. **方法**（就近新增）：
   ```
   func yuanliu_flow_activity() -> void:   # 获得/消耗「流」→ 闲置窗口重置满 5 秒
       if display_name == "元流之子":
           yuanliu_flow_idle = 5.0
   ```
3. **逐帧衰减**：`_physics_process`(1177) **最顶部**、`if is_dead` return 之前插入（死亡/回城期间同样流失）：
   ```
   if display_name == "元流之子":
       if yuanliu_flow > 0:
           yuanliu_flow_idle -= delta
           if yuanliu_flow_idle <= 0.0:
               yuanliu_flow_idle = 1.0    # 首层流失后 → 1 秒 1 层
               yuanliu_flow -= 1
       else:
           yuanliu_flow_idle = 5.0
   ```
   客户端 doll 的 yuanliu_flow 恒 0 → 该块无副作用；主机权威流失。
4. **活动锚点**（3 处调用 `yuanliu_flow_activity()`）：
   - AA 消耗：_perform_attack 2386 `yuanliu_flow -= 1` 之后；
   - W 连发消耗 4 层：_finish_casting 3167 之后；R 连发消耗 5 层：3177 之后。
   - Q 获得由 B 在 SkillDataBase 侧调用。

## D. “每N发视作普攻”→ 真正的普攻类装备触发

### D1. Bullet.gd
- 38 行 `skill_id` 旁新增：`var counts_as_aa: bool = false`（该命中视作一次普攻）与 `var aa_proc_done: bool = false`（穿刺只触发首个目标一次）。
- on_hit() **主目标命中段**（非塔/非刘禅分支，~416 行主 take_damage 之后）插入：
  ```
  if counts_as_aa and not aa_proc_done and source is Hero and is_instance_valid(source) and source.health > 0:
      aa_proc_done = true
      source.proc_aa_item_effects(target)
  ```
  AoE/溅射循环(532-606)与穿刺后续目标**不**触发（一次普攻只对一个目标触发装备）。
  注意：本类命中都在 else 分支（非 Turret），若锁定塔则天然落在 345 塔分支不触发。

### D2. Hero.gd `proc_aa_item_effects(target)`（新私有方法，仅主机权威触发）
仿 _perform_attack 普攻命中装备段(2086-2283)，**逐件只作用于已购装备**，每件按普攻语义结算：
- **闪电匕首**：`_perform_attack` 2086-2136 整段**抽取**为 `_aa_lightning_proc(target)`（附伤 -20 + `lightning_count` 链式电弧：第3次触发 160+lv*16 传导链、黄色弧线视觉复用），_perform_attack 原位改为调用；`proc_aa_item_effects` 同样调用 → 共享计数/冷却。
- **末世**：附伤 `80+lv*5.3`（目标 Hero 再 `+target.bonus_health*0.07`），以物理 `take_damage(..., self, false, -72, 0)` 单独结算。
- **金色圣剑**：`+60` 单次物理 `take_damage(-73)` + `OnHitProcessor.apply_gold_saint_sword(self, target, false)`（叠层/满层AP）。
- **凝冰之息**(CD3s)：减速+`75+lv*5+0.15AP`(-25 复用)。
- **寒霜袭侵 / 制裁·梦魇**：`OnHitProcessor.apply_frost_assault(self, target)` / `apply_grievous_wounds(self, target)`。
- **影刃**：普攻命中+10/20%攻速与5%移速3秒；**急速战靴**：回复；**逐日/破晓**+50/25 物理附伤（-74/-75）。
- **不消费**「技能后下次普攻」类标记（宗师/冰痕/巫术/冰拳/大禹等 2160-2235 段），不触发 狩猎DoT/日渊主动/血魔·怒龙·张飞·亚瑟·刘禅等英雄/情境专属 —— 只做“把这一发当作普通攻击命中的通用装备命中”。

### D3. GameEntity._skill_source_label 追加标签
`-72→"末世(普攻类)"`、`-73→"金色圣剑(普攻)"`、`-74→"逐日之弓(普攻)"`、`-75→"破晓(普攻)"`（533-568 match 表）。

### D4. 打上 `counts_as_aa` 标记（SkillDataBase 施放端）
- **马可波罗 Q**(71-76)：`bid == 0` 的子弹 `bullet.counts_as_aa = true`；**R**(86-95)：`bid == 0` 那轮 4 发全部打标。维持现有 i%3==0 相位。
- **狄仁杰 Q**(13-29)：每方向 i%3==0 时 bullet 与 bullet1 **两个令牌都** `counts_as_aa = true`（“发”=方向对）；W(33-51) 同口径；skill_id 保持不变(1/2)。
- **元流之子 R**(2991)：`pid == 0` 的箭 `arrow.counts_as_aa = true`（“每3支=1次普攻”）。配套注释去掉“负id跳过 on-hit”的旧说明。

## E. 技能说明文字（SkillDataBase get_skill_fx 2374-2382）
- Q：追加「命中范围敌人并击退（约1.5米/短击飞）」＋「流不使用时5秒后流失（之后每秒1层，普攻/技能用流即重置）」。
- W：改为锁敌口径「锁定敌人射出巨型弩箭·必中并小幅击退；无目标则空放」＋保留位移/连发描述。
- R：补「每3支视作1次普攻，可触发普攻类装备效果（闪电匕首等）」。
- 图标伤害与技能定义数值**不改**。

---

## 验证顺序（四道门禁全绿后收尾）
1. **parse**：`G --headless --path . --quit 2>&1 | select-string ...`（既有脚本/口令，期待 PARSE-CLEAN）——并发 peer 可能同时在改 Net* 文件，若 peer 红则 SendMessage 协作后再跑。
2. **battle 100s**：headless 跑 `scenes/battle.tscn` EXIT=124（120s 窗口内，期待 exit 124 / 无脚本错）。
3. **Android export**：导出 ~33MB 无错。
4. **net integration**：`pwsh scripts/net/net_integration_test.ps1 -Port 7817` → PASS（**绝不 7000**）。

之后：中文 F5 视觉核对清单（W 锁敌必中/空放、Q 击退、流衰减曲线、R与狄仁杰/马可普攻装备触发），结尾「需要我继续整理下一个英雄吗？」；写 memory 文件 + MEMORY.md 一行（沿用约定）。
