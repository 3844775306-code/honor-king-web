# M4-U：接管客户端与单机主机「全屏 1:1」UI/操作一致性计划

> 状态：待审批。延续已批 M4（P1-B 真模型+地形对齐已完成并过门禁，剩双窗口 F5 视觉确认）。
> 本计划不覆盖 FX 通道任务（#42 SNAP_BULLETS / #43 SNAP_FX），它们保持排队，可与本计划各阶段交错执行。

## 1. 目标

NetSession 接管客户端（第二个 2400×1400 PC 窗口）在**视觉与操作**上与单机主机窗口全屏 1:1 一致：
触控操作层（左摇杆 + 右侧技能钮/攻击钮/装备钮）、键位、相机系统、小地图、世界血条、buff 图标、
常驻 HUD、目标信息、属性/队伍/商店面板、死亡回放与击杀播报。基准已确认 = **严格全屏 1:1，触控层优先**。

主机权威原则不变：**client 绝不模拟**，动态状态全部由 host 推送；两端共享的静态数据
（ItemDatabase / SkillDatabase / UiManager / TouchController autoload）在 net client 进程同样加载，
商店目录、合成树、推荐出装、技能基础定义等一律本地读取，不落网络包。

## 2. 非目标（沿用已批 M4 边界）

- PvP 红蓝双方真人对抗、房间内英雄选择、断线重连、全局聊天。
- 单机战役模式任何玩法改动。

## 3. 实现策略（三条硬原则）

1. **host 是逐帧 UI 状态的唯一事实源。** buff 图标行、技能钮伤害预览等若在客户端复刻枚举逻辑，
   会复制数百行 bespoke 代码并漂移。做法：把 UI_Manager / TouchController 里「给定一个 Hero 计算展示状态」
   的纯计算段**抽取成与实例无关的函数**（原绘制路径调用它，行为逐字节不变），host NetSession 对被接管的
   AI hero 调同一函数并推给对应 peer；客户端只渲染。
2. **widget 类复用优先于重绘。** `SkillTouchButton.gd` / `VirtualJoystick.gd` / UI_Manager 内部
   `BuffIcon` 等是独立 `class_name`、数据驱动 + 自处理输入，两端实例化**同一个类**即可保证像素一致。
   仅当某控件与 hero/battle 耦合过深才在其上做隔离重构，不做风格重写。
3. **共享文件改动最小、行为不变。** Hero.gd 只允许新增「受控直驱」分支与只读字段暴露
   （`net_drive_input`，默认 Vector3.ZERO → 完全等同原行为）；不碰伤害/技能/AI 逻辑。
   TouchController/UI_Manager 只做第 1 条所述的计算抽取。peers 并发编辑中，改前重验 anchor、保持 diff 最小。

## 4. Host 数据面扩展总清单（NetSession 为主，多数在自家文件）

### 4.1 own 块新增字段（快照 15Hz，每 assigned hero）
| 字段 | 来源 | 用途 |
|---|---|---|
| `rot_y` | `h.rotation.y` | 朝向三角/第一人称相机/转向 |
| `recalling` + `recall_ratio` | `h.is_recalling` + 回城进度 | 回城指示器 |
| `exp_to_next` | `h.exp_to_next` | 经验条 |
| `skill_btns` | §4.3 | 技能钮逐帧状态 |
| `buffs` | §4.2 | buff 图标行 |
| `act_cds` / `act_usable` | 装备主动冷却 | 主动装备钮 |
| `hidden_self` | 隐身类英雄对己方视角 | 兰陵王等相机×1.25 近似 |

### 4.2 buff 行（host 计算推送）
从 UI_Manager 的枚举（`_update_buff_icons` 1749 起 ~200 行 + `_push_marker_buffs` 1558 /
`_push_hero_passive_buffs` 1625 的调用关系）抽取纯函数 `collect_buff_rows(hero) -> {top:[], bot:[]}`，
每行 `[key, glyph(单字), tint(rgb), remain, total, is_static, sub]`。UI 原路径改为调用它后照旧绘制。
长描述（点击图标弹 BuffInfo 用）通过可靠 `_rpc_buff_catalog` 按需缓存下发 `{key:{name,desc}}`。

### 4.3 技能钮状态（host 计算推送）
TouchController `_update_skill_button_ui`（926–~1090）对每技能钮推送一堆字段（cd_ratio/cd_total/mana_ok/
in_window/win_left/win_total/segments_left/charge_now/charge_max/blocked/icon_dmg/icon_dmg2/icon_count/
icon_fx/icon_aa/sub_text/display_name/max_level/skill_level）。抽取纯函数
`compute_skill_button_states(h: Hero) -> Array[Dictionary]`，原 UI 路径调用它，NetSession 对被接管 hero 调同一函数。

### 4.4 事件 / 面板（可靠低频 RPC）
- `_rpc_event(kind, payload)`：击杀播报/多杀/推塔/史诗野怪/升级——host 监测实体信号或快照 diff 后广播，尽量复用 host UI 现有事件入口的数据。
- `_rpc_death_recap(pid, data)`：own hero 死亡瞬间，host 从该 hero 的伤害记录聚合出与 UI 死亡回放同源的分段数据，可靠发给对应 peer。
- `_rpc_roster(payload)`：队伍/详情面板数据（0.5s 节流 + 打开时请求）。每 hero：`[nid,name,team,level,hp,maxhp,kills,deaths,assists,gold,equipment_slots,攻击,法强,护甲,魔抗,移速]`（我方 5 + 可见敌方）。
- `_rpc_inspect(pid, nid, data)`：客户端 C_INSPECT 请求单目标详情（攻击/法强/护甲/魔抗/移速/等级/装备/KDA，或单位 hp/maxhp）。
- `_rpc_game_over(winner_team)`：host 结算 → 客户端显示与主机同款结算（复用现有 ResultsPanel 数据形状）。

### 4.5 命令新增
| 命令 | 载荷 | 语义 |
|---|---|---|
| `C_DRIVE(7)` | `[7, vx, vz]`（非零=直驱意图，零=恢复 AI） | 客户端 WASD/摇杆 → host `h.net_drive_input`，Hero 最小分支按键盘式语义直驱 |
| `C_INSPECT(8)` | `[8, nid]` | 请求目标详情（host 回 `_rpc_inspect`） |
| `C_SELL(9)` | `[9, slot]` | 卖装备 |
| `C_ACTIVE(10)` | `[10, idx]` | 触发第 idx 个主动装备（host 调与 UI 相同的 active API） |

C_MOVE / C_ATTACK / C_CAST / C_UPGRADE / C_RECALL / C_CANCEL_RECALL / C_BUY 沿用；
点击地面/点目标（AI 追击语义）与直驱两条路径并存，CI 既有驱动继续走 C_MOVE，不受影响。

## 5. Phase 计划（每阶段过 4 道门禁 + 双窗口 F5 对照清单）

### P0 前置探查（半天，不写业务代码）
- 探明 SkillTouchButton / VirtualJoystick 的全部公开字段、输入事件流、与 hero 的耦合点；探明它们是否/如何在桌面端同时接收键盘（WASD input actions → joystick；1/2/3/5/6/Z/F2… → 谁处理）。
- 通读 TouchController `_build_ui`（698–878）全部几何与语义：摇杆锚点、攻击钮与兵/塔优先级钮、技能钮/第4技能/召唤师/回血/回城/升级/取消/主动装备钮位置、`SkillTouchButton` 每字段的喂值入口。
- 定位 host 装备主动触发 API 与死亡回放/击杀事件的可挂接信号。
- 产出：可复用 widget 清单 + TouchController._build_ui 几何表（放实现注释里）。

### P1 触控层复刻（最先、体量最大，拆三子步，每子步可 F5）
- **P1a 移动与攻击**：客户端左半屏 VirtualJoystick（含 WASD input actions 直驱）+ 攻击钮 + 兵/塔优先级切换 + 空格锁最近敌方。→ C_DRIVE / C_ATTACK / C_SPACE 对应命令；host Hero 直驱分支。**Host 唯一 Hero.gd 改动**。
- **P1b 技能钮群**：技能 1/2/3(+第4技能) + 召唤师 + 回血 + 回城 + 取消钮，复刻 _build_ui 几何与 SkillTouchButton 视觉；每帧用 `own.skill_btns` 喂值；按下→拖动→松手语义复刻 host，释放转 C_CAST（targeted→tid，方向/落点→tx,tz，自释→无参）；Ctrl+钮=升级 → C_UPGRADE。
- **P1c 装备/杂项钮**：主动装备钮（own.act_cds）→ C_ACTIVE；回城钮/进度 → C_RECALL + own.recalling；F2 显隐；保留/对齐主机键盘热键双轨；关掉/让位于旧的 1/2/3 预选+左键点地 HUD（以 host 表现为准）。
- 对照清单：右侧钮组尺寸/底色/冷却遮罩/伤害预览/段数圆点/充能与主机逐钮一致；左摇杆拖动与键盘移动手感一致；攻击优先级切换生效。

### P2 相机 / 小地图 / 世界血条
- **相机**：host 固定跟随复刻（fov70、rotation(-70,0,0)、offset(0,12,8)+pan）；Tab 第一人称（own.rot_y）；小地图点击/拖动相机覆盖为**纯本地**实现；兰陵王隐身缩放用 own.hidden_self 近似；观战相位保留现有自由视角。
- **小地图**：NetMiniMap（按 MiniMap.gd 画法/常量重做，数据源换成 _views + map payload：塔方块血条、小兵/野怪点、英雄三角+血环、我方塔被攻击警告圈、回城/传送线）；点击跳转/拖动跟手。
- **世界血条**：先读 host 血条真实实现（UI_Manager.update / 实体头饰条），按同 spec 绘制（敌我颜色/等级/名称/蓝条/死亡隐藏），client 用快照 hp/maxhp 驱动。

### P3 常驻 HUD + 面板
- buff 图标行：host `own.buffs` 行数据 → 客户端 BuffIcon（复用类）；点击弹 BuffInfo（buff_catalog）。
- 目标信息面板：C_ATTACK 目标 + `_rpc_inspect` 数据 → 与 host `target_detail_panel` 同布局。
- 属性面板 C / 队伍面板 T：`_rpc_roster` + own.stat 快照；`stat_breakdown` 基础/装备/增益三段显示（host 可整段推，面板打开时按需）。
- 商店 O / 推荐 B / 卖：本地 ItemDatabase 同目录/合成树/推荐；C_BUY/C_SELL。
- 回城指示 / 死亡回放 / 击杀播报：own.recalling / `_rpc_death_recap` / `_rpc_event`。
- 结算页：`_rpc_game_over`。

## 6. 风险与约束
- **peers 并发**：TouchController/UI_Manager/Hero 是共享文件，抽取前重验 anchors；若遇 mixup 回退。
- **P1 widget 复用可行性**：若 SkillTouchButton/VirtualJoystick 与 hero 耦合超出预期，改为在其上做最小隔离（复制为 client 变体并注释来源），P0 必须给出结论。
- **伤害预览/icon_fx**：一律 host 推送，禁止客户端复算公式。
- **既有 CI net 驱动走 C_MOVE**：C_DRIVE 引入后此路径必须保持全绿（integration test 断言不依赖 block 数变化）。
- 无测试套件，任何改动仅靠 parse/90s/export/integration 四道无头门禁 + 双窗口 F5 人工对照。

## 7. 验收（每阶段）
parse（3 scenes clean）→ battle 90s（仅允许已知 benign shutdown noise）→ `net_integration_test.ps1` PASS
→ Android export 成功 → 双窗口 F5：逐屏与主机对照清单打勾（P1 对照触控层、P2 对照相机/小地图/血条、P3 对照面板），全勾后该阶段闭环。
