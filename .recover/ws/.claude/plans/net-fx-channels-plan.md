# #42/#43 视觉通道：SNAP_BULLETS + SNAP_FX（接管窗口技能可见化）实施方案

> 状态：待审批。用户已选档位「**全量含一次性闪光**」。
> 背景：M4-U P1–P3 接管客户端已与 host 1:1（触控层/相机/小地图/血条/面板/结算），但接管窗口的 3D 战场里**子弹与技能特效完全不可见**（快照 v4 只含 heroes/minions/turrets/jungles + own）。#42/#43 补上这两类瞬态视觉。
> 硬边界不变：client 绝不模拟；host 是唯一事实源；共享文件改动最小、行为不变；不覆盖伤害/判定/AI。

## 1. 现状事实（已勘察）

- 快照 `_build_snapshot`(NetSession.gd:697) 每次组包：`[time,state,own,heroes,minions,turrets,jungles]`，SNAP_*=0..6（NetSession:86–92 / NetClientBattle:24–30 各一份常量，两处 enum 顺序已对齐，**须同步扩展**）。传输通道 `_rpc_snapshot` = **unreliable_ordered**(NetSession:1052)，无 ack——Fx 事件不能只发一次。
- 子弹：所有弹体 `_ready()` 里 `add_to_group("projectiles")`(Bullet.gd:63)，运行中/命中/超时各自 `queue_free`；命中判定在弹体自身 `_physics_process` 手动完成。既有组枚举遍历（heroes/minions/turrets）是现成范式，直接照抄对 projectiles 遍历即可，**不触碰 Hero/Bullet 逻辑**。
- 特效：技能视觉集中在 `SkillDataBase.gd`（`class_name SkillApplier`，Node）——
  - `apply_skills(hero,skill_id,pos)` L7–~1870 按英雄/技能分支做伤害 + 视觉；
  - 具名视觉 helper 是**主要收敛点**：`create_spell`/`create_preview`/`create_terrain`/`_create_water_splash`/`_create_water_zone`/`_create_water_pulse`/`_lyf_storm_visual`/`_yuanliu_flow_pool`(L2439–2943)，各自已知 pos/radius/team 且多为硬编码色；
  - 直接 `MeshFactory.create_*` 闪光点：SkillDataBase 内 22 处（多数在 apply_skills 或 helper 内）、Bullet.on_hit 后羿R 爆炸组(L467–493)、Hero.gd 少量自旋特效。
- 视野口径（沿用既有规则）：非己方实体只在 `e.visible or e.vision_expose_timer>0` 或塔/事件进我方 18m 内才发（`_turret_in_vision`，NetSession:794）。子弹/FX 照抄，避免隐藏敌人被透视。

## 2. 方案总览

三段可各自过门禁、各自可 F5 的推进；最终形态 = 全量：

- **A 段：#42 子弹通道 + FX 基础设施**（全在 NetSession / NetClientBattle，零共享文件改动）。
- **B 段：#43 插桩·持续地面特效**（8 个具名 helper 各 +1 行 recorder 调用，SkillDataBase 最小 diff）。
- **C 段：#43 插桩·一次性闪光**（Bullet 爆炸组 + apply_skills 内直接 MeshFactory 点，逐个上 kind）。

### 2.1 host 侧（NetSession.gd）

快照布局 **v5**：SNAP_ 常量追加 `SNAP_BULLETS:=7, SNAP_FX:=8`，`_build_snapshot` 末尾 append 两段（兼容：长度守卫用 `> SNAP_JUNGLES` 的现有写法扩为 `> SNAP_BULLETS` 读新段）。

- **bullets 段**：遍历 `get_tree().get_nodes_in_group("projectiles")`，`is_instance_valid` 且未 `is_queued_for_deletion` 才收；可见性 = `team==TEAM_PLAYER` 或 `_proj_in_vision(pos)`（复用 sources≤18m 口径，塔/英雄同款）；行 = `[iid(int(instance_id())), x, y, z, team, size, houyi]`：
  - `size`：`source is Hero or source is Turret` → 1（host 放大 ×3），默认 0（小）；`is_houyi_ult` → 2（大号太阳火箭视觉）。
  - 帧间去向不打包——客户端用两帧采样做纯视觉插值，host 零压力。
- **FX recorder（host 专用环形缓冲）**：
  - `var _fx_buf: Array = []`；`func push_net_fx(kind:int, pos:Vector3, team:int, r:float, life:float)`：`mode!=HOST` 或不在对局 → no-op；非己方且不在我方 18m 视野 → no-op（防透视）；`_fx_buf` 每元素 `[kind,x,y,z,team,r,life,born_tick]`，cap≈64 丢最老。
  - **防 unreliable 丢包**：元素在缓冲里保留到 `born≥~0.35s`（约 5 个快照周期）才剔除，`_build_snapshot` 把整段拷进 `out[SNAP_FX]` 并附**自增 `fx_seq`**（打进 SNAP_FX 首元素）；客户端按 seq 去重 → 即使 1-shot 也能至少中一发，zone 事件必达。
  - 持久型 zone（水区等）：host 只在生成时 push 一次 + `life`=总时长；客户端本地按 life 收尾淡出，无需结束事件。
- 顺带在 NetSession 常量注释/`_net_summary` 的计数口径里带上 `bullets/fx` 计数（便于 90s soak 日志断言非零/无报错）。

### 2.2 客户端（NetClientBattle.gd）

- `SNAP_BULLETS/FX` 常量 + decode：`_snap.size() > SNAP_JUNGLES` 处扩展。
- **子弹代理池** `_bpool: Dictionary /*iid*/`（`_fx_root` Node3D 下 MeshInstance3D 复用池）：
  - 每快照更新：对在列 iid 更新 `last_pos / prev_pos / game_t`；对不再在列的 iid 标记淘汰（容 1 帧防抖后移除）。
  - 两帧采样线性插值 + **速度外推但 clamp 到采样间隔**（前向半窗）：`pos = cur + v*clamp(age, 0, 0.066)`；行进方向朝向 = 速度方向，代理长轴沿速度旋转。
  - 视觉（忠实风格、形状代表性）：team0 青(0,0.886,1) / team1 敌红(1,0.33,0.264)，unshaded；`size==0` 小球、`size==1` 放大、`size==2` 橙色拉长彗星（配 host 后羿R 火环观感）；发射源死亡/弹体消失即移除。
  - 地面命中（非 houyi）不额外合成——B/C 段 FX 事件负责。
- **FX 渲染器**：
  - 每帧收 `SNAP_FX`：`seq` 与上帧比对，新元素按 kind 走 catalog 生成 `MeshInstance3D`（放 `_fx_root`），已存在(seq 相同)的跳过；元素带自身 id（`[seq,kind,...]`）避免同一 buffer 重发重复画。
  - catalog 每种 kind → {build: MeshFactory 同款基础形（flat ring / disc / expanding ring / 拉长 cone），tint：固定色（照抄 host helper 硬编码 palette，例如水区=蓝），team 影响仅对 `create_spell` 这类用 team 分色的做二色};动画 = 宿主同款短 tween 语义本地复刻（scale/alpha 淡出），zone 类在 `life` 内保持后淡出。
  - 生命周期本地走墙钟，与 15Hz 快照解耦；超龄自动 queue_free。

### 2.3 插桩清单（SkillDataBase.gd = `class_name SkillApplier`，B/C 段）

在 **8 个具名 helper 函数头**各插一行 recorder（B 段，共 ~8 行，锚点=函数首行、peer 并发漂移风险最低），kind 表如下；形状/颜色实现阶段照抄各 helper 硬编码，不重设计：

| kind | 来源 helper | 形状基调 |
|---|---|---|
| 1 spell | create_spell | team 色扩圈（Ring 系） |
| 2 preview | create_preview | 浅蓝地面圆 |
| 3 terrain | create_terrain | 地形块/圈（按 shape_id 后期追平） |
| 4 splash | _create_water_splash | 蓝色水花闪盘 |
| 5 waterzone | _create_water_zone | 蓝色地面水域（persist，life=helper 实际时长） |
| 6 waterpulse | _create_water_pulse | 蓝色扩散水圈 |
| 7 lyfstorm | _lyf_storm_visual | 青色风暴环 |
| 8 ylpool | _yuanliu_flow_pool | 元流区域池 |

C 段一次性闪光：
- `Bullet.on_hit` 后羿R 爆炸组(L467–493，ring+glow+sparks) → 1 个 kind=20 `houyi_explode`（r=2，life≈0.5，橙，客户端一组盘+点簇近似）。
- `apply_skills` 内**直接 `MeshFactory.create_*` 的闪光点**（22 处，多为近战挥砍/命中爆发）：逐点标 kind=21+n + pos/半径，实现阶段在阅读该函数时逐条落点并登记成清单，**不在本文件外的任何逻辑**。凡属前述 8 helper 内部的 MeshFactory 自动被 helper 行覆盖，不重复插。
- Hero.gd 自旋类（张飞变身环等）已是英雄身上常驻 ring，随 hero 快照可见，**不新增通道**（避免触碰 Hero.gd）；马超/甄姬 `skillapply.bpos` 落点圈若经 helper 已覆盖则不再单点。

### 2.4 共享文件与并发纪律

- 本方案唯一共享文件改动 = **SkillDataBase.gd 共 ~30 行 recorder 插入**（B 段 8 行 + C 段 ~22 行），不删不改原有行；锚点用函数头/既有唯一串，改前 `grep -n` 重验。
- peers 常在此文件加英雄（元流/玉流刚落地），若 parse 红且是对方半成品 → **等对方补完再跑**，绝不代修。
- NetSession/NetClientBattle 是本会话自持文件（近几小时 mtime 均为本会话产物），冲突面小。

## 3. 阶段与门禁

| 阶段 | 内容 | 门禁 |
|---|---|---|
| A | 常量 v5 + bullets 段 + _fx_buf/push_net_fx + 客户端池/渲染骨架 | parse → 7011 集成 PASS |
| B | 8 helper 插桩 + client zone/field 渲染成形 | 上 + 90s net soak（0 SCRIPT ERROR，日志见 fx 计数非零） |
| C | 一次性闪光插桩（后羿爆炸 + apply_skills 直接点） | 上 + export-debug Android exit0（APK） |

F5 增量对照（每段后给用户一次聚焦清单）：A=「普攻/技能弹道可见、方向对、命中消失」；B=「甄姬水区/元流池等地面特效现形、按 helper 色/时长」；C=「后羿R爆炸、近战挥砍闪光」；最后与 host 同屏逐技能对照。

## 4. 已知边界（诚实声明）

- 客户端 FX 是「同位置/同色/同时长 + 代表性形状」而非逐网格复刻 host 的 `MeshFactory` 组合——host 单帧十数个 Node3D+tween 的组合无法在 15Hz 通道保真；**形状差异留待 F5 逐点追平**，颜色/时长/空间由 host 事件携带、1:1。
- bullets 用两点速度外推做视觉平滑，极短命弹（<66ms 内生灭）可能漏拍；对局观感可接受，F5 若见明显跳变再提「出生事件通道」。
- 敌方 18m 视野外技能不推（防透视），敌方远处技能闪光不可见——与既有实体可见性口径一致。
