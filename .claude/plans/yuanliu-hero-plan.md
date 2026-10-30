# 元流之子（沉舟之志 · 射手）实现方案

> 目标：与「李元芳」同一套落地范式（hero_configs → GameEntity/Hero 钩子 → SkillDataBase 三臂 + UI 两臂 → ItemDatabase 三套出装 → parse/100s 门禁 → F5 清单）。
> 本英雄是全引擎机制最复杂的一例（"流"资源、泉水四选一、贯穿强普、连锁位移箭、箭雨+普攻判定），下文先给**引擎能力映射决策**，再给落地任务清单。

## 0. 数值速查（权威来源转录）

| 项 | 值 |
|---|---|
| 基础 | 最大生命 3250｜法力 600｜物攻 170｜物防 150 / 法防 75｜移速 360｜远程｜回血 40/5s 回蓝 15/5s |
| 被动·万物为流 | 攻速 +10%~20%（随等级）；四选一：生机 +300~600 生命 / 穿心 +30~60 物攻 / 迅疾 +12.5~25 移速 / 凝神 +5%~10% 冷却缩减（成长取 `t=(level-1)/14` 线性插值，Lv1 起、Lv15 满） |
| 被动·强化普攻 | 耗 1 层"流"：贯穿弩箭，路径每个敌人额外造成 `80+20%额外AD`，逐次命中伤害衰减至 70% |
| Q 汇流为一 | 范围伤害 `100+20·lvQ +25%额外AD`、击退（无硬控）、自身回复 `150+30·lvQ +4%额外生命`（友军/小兵额外回复上限 +100%、"流" 最高 9）；5 层"流"；减【W】【R】剩余 CD 50%｜CD 12.5→10（0.5/级）、耗蓝 50 |
| W 破釜之箭 | 巨型弩箭 `480+96·lvW +120%额外AD`，被敌方**英雄**阻挡，击退非英雄单位；自身位移一段｜CD 7.5→6（0.3/级）、耗蓝 25 |
| W 连锁 | 2s 内再次释放 → **参连之箭**（伤害+25%）；第三次 → **凌空之箭**（+50% 并浮空） |
| W 额外 | 耗 4 层"流"可额外再放一次 |
| R 万箭齐发 | 朝指定区域放 N 支轻型弩箭（锁定区域内目标），每支 `50+25·lvR +24%物攻`，**每 3 支=1 次普攻判定**；释放获得移速 +20~40；再次释放浮空｜CD 25→20（2.5/级）、耗蓝 60 |
| R 弩箭数 / 数值 | Lv1 7 支 / 50 伤害 / +20 移速；Lv2 10 / 75 / +30；Lv3 13 / 100 / +40 |
| R 额外 | 耗 5 层"流"可额外再放一次 |

## 1. 机制→引擎映射决策（与"权威资料"的偏差在此显式声明，供你核对）

1. **泉水四选一（生机/穿心/迅疾/凝神）**
   - 一次性：玩家在**开局**弹一个 4 键小面板（CanvasLayer，风格同现有 buff 图标体系）选择，选后永久生效（复活不再重选——声明为近似，真游戏泉水可换，后续可加）。
   - AI（含敌方同英雄）出生时随机选 1 种。
   - 默认（未选即开局）＝生机。
   - 数值随**英雄等级**线性成长（Lv1→Lv15），每次 `level_up`/`upgrade_skill` 已自动 `_recalculate_attributes()` 重算。
2. **"流"层数（0~9）**
   - 英雄字段 `yuanliu_flow`。Q 给 5 层，其身边每名友军/小兵额外 +1 层（封顶 9）＝ 常见场景 Q 后 6~9 层。
   - 消耗：强化普攻 1 层；W 额外释放 4 层；R 额外释放 5 层。
   - **Buff 面板**常驻一行「流 N/9」显示（UI_Manager `_push_hero_passive_buffs` 增加 display_name 分支，glyph「流」，tint 青蓝）。
3. **强化普攻＝自动消耗**：拥有"流"时普攻**自动**变成贯穿弩箭并扣 1 层（无需额外技能键；引擎没有第 4 技能槽通用先例）。
   - 实现：`Hero._perform_attack()` 远程子弹分支加 `display_name=="元流之子"`：置 `pierce=true`、改 `set_linear(dir, speed)`（贯穿直线弹道）、给 Bullet 新增 `yuanliu_strong/yuanliu_strong_extra/yuanliu_hits` 三字段，路径上每个命中目标追加 `80+20%额外AD × 0.7^(已命中数)`。
4. **Q 汇流为一（自身周边 AoE）**
   - 技能 type=1（范围圈），apply 内以施放点/自身为中心半径 2.5m 扫敌人：伤害 + 沿径向小位移击退（≈1.2m，无硬控）+ 自疗 `_apply_healing`。
   - 治疗 = 基础回复 ×`clamp(1+0.2×友军数, 1, 2)`；友军计数＝7m 内同队英雄+小兵。
   - "减 50% 冷却"＝对 `skill_cooldowns[1]`/`[2]` 各自 `*0.5`（仅剩余 CD）。
   - 流 +5+友军数（≤9）。
5. **W 破釜之箭（type=4 位移 + 弩箭）**
   - 位移朝瞄准点（self_displacement≈4.0）。
   - 弩箭 = `create_bullet`（伤害已含等级+120%额外AD + 连发倍率），沿位移方向飞行、`pierce=true`；命中非英雄 = 伤害 + 击退 2m（手动 `global_position += 径向dir*2`），命中**英雄**＝结算伤害后子弹停下（视觉/逻辑上箭被挡）。
   - **连发阶段** `yuanliu_w_phase`（0/1/2）＋ `yuanliu_w_window`（2s）：窗口内连发下一箭伤害 ×1.25（参连）→ ×1.5＋浮空（凌空）。超窗重置。
   - **额外释放**：施放结算后若 `flow>=4` → 扣 4、`skill_cooldowns[1]=0`（立即能再放，天然形成 W 三段连）。
   - 浮空映射：`yuanliu_float=0.7s`，模型 Y 上抬 ~1.6m、期间 `wd_timer=max(wd,0.6)`（不可被锁定/免伤免控——**与引擎现有"无法选中"同一套能力**，声明为"凌空"近似）。
6. **R 万箭齐发（type=1 区域）**
   - 以施放点为圆心 R=3.5m，持续 `N` 支弩箭（N=7/10/13），每隔 `≈0.55 / attack_speed` 秒发射一支**自动索敌**区域内的随机敌人（每支 = `50+25·lvR +24%总物攻` 物理伤）。
   - **每 3 支的 bullet `skill_id=0`**（触发普攻判定：吸血/普攻触发类装备），其余用负 id 避免 on-hit 分支。
   - 施放即刻获得移速 `20+10·lvR`（2s，`apply_move_pct_buff` 用固定数值型加分——参考沈梦溪 msup 同式需确认字段）。
   - **额外释放**：`flow>=5` → 扣 5、`skill_cooldowns[2]=0`，且此次浮空（再放即凌空）。
7. **常驻被动数值烘焙**：在 `Hero._sync_passive_buffs()` 追加 `elif display_name=="元流之子"`：
   - 攻速（全员）：`attack_speed_pct = 0.10+0.10×t`；
   - 穿心：`bonus_attack = 30+30×t`；迅疾：`bonus_move_speed = 12.5+12.5×t`（均走 `_sync_tagged_entry`，与狄仁杰/后羿同构）；
   - 生机（HP）与凝神（CDR）不在 buff 聚合键表内 → 在 `_recalculate_attributes()` 的 `actual_max_health=` 与 `actual_cd_timer` 收尾处各加一行 `display_name=="元流之子"` 特判（生机 +`yuanliu_hp`，凝神 -`yuanliu_cdr`，字段在选型/升级时更新）。
   - 英雄新增字段：`yuanliu_flow/yuanliu_pick/yuanliu_hp/yuanliu_cdr/yuanliu_w_phase/yuanliu_w_window/yuanliu_float`。
8. **出装（ItemDatabase `get_recommended_items`）** 射手发育三套（键均为已存在）：顺风 `swift_boots,world_end,shadow_blade,infinity_edge,dawn,bloodthirster`；均势 `swift_boots,world_end,shadow_blade,infinity_edge,dawn,chase_wind`；逆风 `resist_boots,world_end,blade_of_sanction,dawn,shadow_blade,revive`。

## 2. 落地文件清单

### T1 BattleManager（接入）
- `hero_configs` 增 `"元流之子": {role:"射手", max_health:3250, attack:170, attack_range:700, move_speed:360, max_mana:600, skills:[yuanliu_q,w,r], summoner:"flash", hp_reg:40, mana_reg:15}`（置后羿/李元芳附近）。
- `valid_heroes` 追加。
- AI 生成分支：若英雄为元流之子 → `yuanliu_pick` 随机四选一并 `_recalculate_attributes()`；玩家英雄由 T6 面板设置。

### T2 Hero.gd
- 变量区（李元芳变量后）加 §1.7 字段。
- `_physics_process` timers：`yuanliu_w_window` 递减清零阶段；`yuanliu_float` 递减控制模型 Y 抬升/回落 + wd 管理。
- `_perform_attack()` 远程子弹分支：§1.3 贯穿强普（耗流/linear/pierce/extra 字段）。
- `_sync_passive_buffs()`：§1.7 四选一+攻速常驻条目。
- `_recalculate_attributes()`：生机/凝神两行特判。
- `HERO_MODEL_MAP`：`"元流之子": ["res://model/hero/character-male-a.glb",""]`（与李元芳同款男模，无独立资产——声明近似）。

### T3 GameEntity / Bullet（最小扩展）
- GameEntity：无（流不参与受击钩子）。
- Bullet：新增 `yuanliu_strong/yuanliu_strong_extra/yuanliu_hits`；命中处（主伤害结算点附近）追加：若 `source.display_name=="元流之子" and yuanliu_strong` → 追加 `extra×0.7^hits` 并 `hits+=1`（注：主伤害取整后相加，纯物理）。

### T4 SkillDataBase
- `_init_skills()`：3 条定义：
  - Q `yuanliu_q`：type=1、cd 12.5、cd_bonus 0.5、mana 50、damage 100、bonus_ratio 0.25、radius 2.5；
  - W `yuanliu_w`：type=4、cd 7.5、cd_bonus 0.3、mana 25、self_displacement 4.0、damage 480、bonus_ratio 1.2；
  - R `yuanliu_r`：type=1、cd 25、cd_bonus 2.5、mana 60、radius 3.5、damage 50、bonus_ratio 0.24。
- apply_skills 增 `"元流之子":match skill_id:` → 三辅助函数 `_yuanliu_q/_yuanliu_w/_yuanliu_r(hero, level, pos)`（放 `_init_skills` 前空档，同李元芳范式）：
  - Q：AoE 伤害+击退、`_apply_healing`、流层+CDR、`skill_cooldowns[1]/[2] *=0.5`；
  - W：连发阶段结算、位移方向箭、英雄阻挡、击退非英雄、浮空/额外释放耗流逻辑；
  - R：N 支定时索敌箭、每 3 支 skill_id=0、移速 buff、额外释放耗流+浮空。
- `get_skill_icon_damage`：Q=`int(100+20*(lv-1)+0.25*ad)`、W=`int(480+96*(lv-1)+1.2*ad)`、R=`int(50+25*(lv-1)+0.24*aad)`。
- `get_skill_fx`：Q 回复/击退文本、W 连锁倍率文本、R `count=7+3*(lv-1)`、`unit="支"`、msup 与描述。

### T5 ItemDatabase
- §1.8 三套出装。

### T6 UI_Manager（四选一面板 + buff 行）
- `_push_hero_passive_buffs()` 增 display_name 分支：「流 N/9」行 + 已选被动常驻行（glyph 生/穿/迅/凝）。
- 新增 `show_yuanliu_pick(hero)`：CanvasLayer+4 Button（Button 带效果文本），点击回调设置 `yuanliu_pick`、更新 `yuanliu_hp/cdr`、`_recalculate_attributes()`、关面板；BattleManager 开局玩家主英雄创建后调用一次（不可重复弹）。AI 不弹。

## 3. 门禁与验证
1. parse：`--headless --path . --quit`，无 `SCRIPT ERROR/Parse Error`（注意 `:=` 对 Variant 的推断——未标注 hero 参数处全部显式 `: Vector3 =`）。
2. 100s 稳定性：`timeout 100 <godot> --headless --path . res://scenes/battle.tscn`，预期 EXIT=124。
3. F5 手动清单（交付时附）：
   - 选人射手组出「元流之子」→ 开局弹四选一（生机/穿心/迅疾/凝神），选后属性面板/Buff 行可见对应项与「流 0/9」；
   - Q：伤敌+自身回血+小兵群中流变 6~9、W/R 剩余 CD 减半；
   - 普攻（有流时）：箭变贯穿、沿途掉血、每下耗 1 层流；
   - W：位移+巨箭被敌方英雄挡停、小兵被击退；2s 内连放 2/3 段伤害提升、第三段浮空；
   - R：区域落 N 支箭（每 3 支吃普攻特效如吸血）、期间移速提升、耗 5 流可再放且浮空；
   - B 键三套出装齐全、图标/详情伤害数字与公式一致。

## 4. 显式声明的近似（与权威资料不同处，供否决/微调）
- 四选一为**开局一次性**（真游戏泉水内可换）。
- 强化普攻为**有流即自动消耗**（不提供单独触发键）。
- "凌空/浮空"用引擎"无法选中/免伤免控"（wd_timer）+模型上抬近似，0.6~0.7s。
- 友军对小兵回复/流的精确数值采用"每名友军 +20% 回复、+1 流（封顶9）"式近似，便于对齐节奏。
- R"施法速度受攻速成长"按 `间隔≈0.55/attack_speed` 近似。
- Q 基础伤害/回复、W 伤害、R 单支伤害与 CD 均严格按 Lv 表转录（见 §0）。
