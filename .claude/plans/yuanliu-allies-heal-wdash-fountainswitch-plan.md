# 元流之子 第三批机制修正 实现计划

按用户权威规格修正（三处，离线+联机都做，维持既有四门禁全绿为前提）：
1. **1技能「汇流为一」**：以自身为圆心统计附近友方英雄/友方小兵（封顶 4 名）——每名使「流」额外 +1，且自身回复量 ×(1+0.25×人数)（最高 ×2）。
2. **2技能「破釜之箭」**：施放瞬间沿当前摇杆/移动输入方向滑移固定 2.5m；巨箭仍朝拖拽/锁定方向射出，贯穿/格挡/击退命中行为全保留。
3. **被动「万物为流」**：四选一改为「在自家泉水内随时可重新切换」——交互用泉水内**常驻『流派·切换』按钮**（非进泉自动弹），开局首弹保留。

已确认现状（避免误改）：
- Hero 槽位 0=汇流为一(type1 AoE 3.5)、1=破釜之箭(type0 targeted cast_range6.5，代码注释里的"type=4 位移"是陈旧描述，实际无位移)、2=万箭齐发(type1)。
- 汇流 Q 效果在 `SkillDataBase._yuanliu_q`（2837）：敌方 AOE 伤害 + 自身回复 `60+12·(Lv-1)+15%额外AD` + `yuanliu_flow += 5`(上限9) + 破釜/万箭剩余冷却减半。
- 破釜 W 效果在 `_yuanliu_w`（2867）：读 `hero.dash_from` 与瞄准 pos 定方向，直线光束命中判定。
- 被动四选一状态：`yuanliu_pick` 默认"生机"；穿心/迅疾走 `_sync_passive_buffs` 的 `_sync_tagged_entry("yuanliu_choice",…)`，生机/凝神在 `_recalculate_attributes` 特判。**直接改 pick 再 recalc 会残留旧流派 buff 键**（换穿心→迅疾时 bonus_attack 残留）——必须整体删 tag 再重算。
- 泉水：蓝方 (-58,0,58)/红方 (58,0,-58)，回复半径 5.0（Hero 1242-1248 已存在判据）；泉水视觉圆盘半径 3。
- UI：玩家被动面板 `UI_Manager.show_yuanliu_pick`（1754）——开始即 `yuanliu_picked=true`，二次打开被 1758 挡；buff 行「万物为流·流/流派」已由 `collect_buff_rows` 推送（主机→联机 own.buffs 同源）。
- 联机：命令码至 15（C_ROSTER=15），`NetSession._on_client_cmd` 的 match 在 `_can_control` 之后；own 快照 hero 字段无 `team`（需补一个字段以判断接管方泉水）。桌面/触控移动输入在 Hero `_physics_process` 里是局部 `move_vec`，无成员缓存——需要新增 `last_move_dir` 缓存当前世界方向。

## 实现步骤

### #1 Hero.gd：移动方向缓存 + 泉水判定 + pick 安全切换
- 新增字段（元流之子字段区附近，~line 320）：
  - `last_move_dir: Vector3 = Vector3.ZERO`（每帧移动段有有效 move_vec 时更新为归一化世界方向；net_drive/TouchController/AI 追击都走同一处，天然覆盖离线与联机）。
  - 在移动块末尾（move_vec 算完、非零、非回城）写 `last_move_dir = move_vec.normalized()`。
- 新增 `func in_own_fountain() -> bool`：`is_dead` 直接 false；team==PLAYER 用 (-58,0,58)、否则 (58,0,-58)，`distance_to <= 5.0`。（泉水回复段保留原逻辑或改调此函数均可。）
- 新增 `func set_yuanliu_pick(pk: String) -> bool`：非元流之子/非法值返回 false；同值 true；否则**先移除 `_tag=="yuanliu_choice"` 的 active_buffs 条目**，再赋值 `yuanliu_pick=pk`，`_recalculate_attributes()`，health/mana 超上限时收敛（离开生机流派 maxhp 回落场景），返回 true。此方法不在内部强制泉水（启动首弹也在泉水）。

### #2 SkillDataBase：汇流附近友军计数 + 破釜 2.5m 摇杆位移
- `_yuanliu_q`（2837）：
  - 加常量 `YUANLIU_ALLY_RADIUS := 5.0`（可调）。
  - 计数：遍历 `hero.get_tree().get_nodes_in_group("entities")`，条件 `e != hero && e.health>0 && e.team==hero.team && (e is Hero || e is Minion)`，按**自身** `global_position` 距离 <= 半径 统计；`var n := mini(count, 4)`。
  - 自疗改为 `base_heal * (1.0 + 0.25*n)`（原基础公式不变）。
  - 流改为 `hero.yuanliu_flow = mini(hero.yuanliu_flow + 5 + n, 9)`。
- `_yuanliu_w`（2867）：命中判定/巨箭逻辑**不动**；位移部分由 Hero 端负责（见 #3），此处可顺带把注释改为“位移已由 Hero 侧按摇杆方向 2.5m 完成”。
- 更新技能文案（`get_skill_fx` texts 附近 2376-2382 等出现处）：
  - 汇流为一：追加“附近每名友方英雄/小兵使回复+25% 并额外 +1「流」（至多 4 名）”。
  - 破釜之箭：“向目标方向位移…”→“施放时朝摇杆方向位移 2.5 米…”（保留贯穿/格挡/击退描述）。

### #3 Hero.gd `_finish_casting`：破釜施放即摇杆方向滑移 2.5m
- 在 `dash_from = global_position`（3144）之后、代价/CD 结算区附近加（仅首次与每次连发重放都执行）：
  ```
  if display_name == "元流之子" and pending_skill_index == 1:
      var _d := last_move_dir
      if _d.length() > 0.1:
          global_position += _d.normalized() * 2.5
          global_position.y = 0.5
  ```
- 连发第二/三段（3162-3171）已有流消耗+浮空，改动自动对每段生效（一段一滑）。不动瞄准：type0 目标选择/智能施法链路维持，`_yuanliu_w` 仍沿瞄准方向出箭。

### #4 UI_Manager：泉水常驻『流派·切换』钮 + 面板可重开
- 新增控件 `_yl_switch_btn`（用现成 `_connect_tap_to_action` 模式或按钮样式），创建时 `visible=false`。建议锚到右上角金币/推荐装备下方空档（offset 参照现有 right-anchor 组件，避免与技能/小地图区冲突；位置 F5 阶段可再微调）。
- `update()`（2764 已有每帧入口，hero=battle.hero）里刷新可见性：`hero.display_name=="元流之子" && hero.health>0 && hero.in_own_fountain() && (无模态面板打开)`；按下→`show_yuanliu_pick(hero, true)`。
- `show_yuanliu_pick(hero, reopen=false)` 改造：
  - `reopen` 时不再因 `yuanliu_picked` 早退（首次自动弹仍走原逻辑）。
  - 面板标题/提示文案区分：重开时“万物为流 · 泉水抉择（可切换）”，并把“进入战场后不可更改”改为“离开泉水后仍生效，回泉可再换”。
  - 当前流派按钮文字加“(当前)”；补一枚“取消”按钮仅重开时显示（关面板不改流派）。
  - 选择回调统一走 `hero.set_yuanliu_pick(pick_name)`（替换现在直接 `yuanliu_pick=`+recalc 的两行，避免残留）。

### #5 联机：NetSession 命令 + 快照补 team；NetClientBattle 客户端切换钮/面板
- `NetSession.gd`：
  - `const C_YUANLIU_PICK := 16`（注释“元流之子泉水切换流派：[16, 流派名]”）。
  - `_on_client_cmd` match 内 `C_YUANLIU_PICK`（在 `_can_control` 之后）：`h.display_name=="元流之子"`、流派名合法、**`h.in_own_fountain()`** 才 `h.set_yuanliu_pick(pk)`，否则 printerr 拒绝。
  - own hero 字段补 `"team": h.team`（客户端定位自家泉水用；`.get` 无匹配时按 0 兜底无影响）。
- `NetClientBattle.gd`：
  - 新增切换按钮 + 四选一面板（CanvasLayer 覆盖物，布局可参考 NetShopPanel/NetResultPanel 既有覆盖物风格，简化文本按钮即可）。
  - 可见条件：`_owned && _own.name=="元流之子" && alive && 距离自家泉水(按 own.team：PLAYER(-58,58)/ENEMY(58,-58))<=5`。
  - 按钮→弹出四选一；点选 → `NetSession.send_command([NetSession.C_YUANLIU_PICK, name])` 并关面板；可选“取消”。
  - own.buffs 已由 host 推送（含万物为流·流/流派行），切换后自动反映当前流派。

### #6 文案/详情一致性（顺带小改）
- `get_skill_icon_damage`/`get_skill_fx` 若有写死旧文案（“进入战场后不可更改”“向目标方向位移”）同步更新；AI 仍开局随机选、不回泉水切换（本批不做 AI 行为扩展）。

### 门禁（与 honor-king-gates.md 一致）
1. parse：`& $godot --headless --path . --quit`（不打印中文，grep SCRIPT ERROR/Parse Error）。
2. 100s 稳定性：`timeout 100 … res://scenes/battle.tscn` 期望 EXIT=124、0 SCRIPT ERROR（元流之子 AI 也在局内，能覆盖 W 滑移/Q 计数路径冒烟）。
3. Android export（--export-debug "Android"，exit 0）。
4. net 集成：`scripts/net/net_integration_test.ps1 -Port <非7000>` → INTEGRATION PASS（改到 own["team"] 后旧客户端 .get 兜底不破坏集成）。

### F5 人工核对清单（交付时附给用户）
- **1技能**：选元流之子（生机路线也行）→ 对着一波己方小兵放 1技能：回复数字明显变大、头顶“流”层数一次到 9（基础5+附近4名=封顶）；清掉身边队友/小兵再放：回复回到基础、只 +5；爆开落点敌方仍吃 AOE、破釜/万箭 CD 仍减半。
- **2技能**：按住方向移动的同时按 2：英雄沿移动方向小滑 2.5m 并朝目标方向射出巨箭（贯穿/格挡/击退不变）；站定按 2 不滑动仍出箭。连发（4 流再放）每段各滑 2.5m、第三段上抬。
- **泉水切换**：开局自动四选一面板正常；选后离开泉水面板不再弹；回泉后右上出现“流派·切换”→ 打开面板，当前流派标“(当前)”，换选后数值立即变（生机生命/穿心攻击/迅疾移速/凝神冷却四选一各自生效，无残留旧加成：尤其穿心→迅疾换着切验属性面板）。
- **联机 F5（双开、非 7000）**：客户端接管 元流之子 后，回泉出现切换钮，点选发送 → 主机 hero 流派改变、own.buffs 流派行同步、快照属性跟随；客户端看 1技能回复加成/流层变化与主机一致（host 端跑规则）。
- 门禁默认不给中文 stdout。

### 风险与备注
- 元流之子 Q 计数用小兵会导致“对线时几乎总是满加成”——符合“友方英雄或小兵”的措辞，半径 5m 常量可调。
- W 滑移量 2.5m 为固定值常量；若与墙壁/推挤冲突由 CollisionSystem 下一帧修正，不额外做寻路回退（同现有 type4/位移手法）。
- 破釜 tooltip 目前声称带位移但代码没有——本次落实“摇杆方向 2.5m 滑移 + 巨箭照旧”，不引入长距离冲刺语义。
