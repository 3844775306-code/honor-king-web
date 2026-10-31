# AI 自动学习（决策越打越聪明 · 真实对局 + 自对弈共用同一档案）

目标（用户已确认）：**决策随对局自动改进**，喂入两个来源——真人局 + 后台 AI-vs-AI 自对弈——同一份持久档案。

## 0. 探索结论（决定方案的关键事实）

- AI 的**现行决策栈**（不是文档里写的那套）：
  - 每帧 `HeroAI._process` → 0.5/1s 决策节拍 → `_decide()`（水晶/高地/本线塔防御、低血回城）→ 交给 `LaneStrategy.decide()`/`JungleStrategy.decide()`（推进/发育/蹲草/换线）。
  - 4 分钟后 `BattleManager._process`（2540 行）每 60s `team_tactics.allocate_all()` → `hero_ai.apply_team_lane()` 分推/抱团/打龙。
  - 所有阈值都读 `AiConfig.X` 常量。
- **死代码（不碰）**：`BehaviorScorer`、`AiStateMachine`、`AiCoordinator`（自注"早期原型未实例化"）、`HeroAI` 顶部 `SCORE_*` 常量——均无实例化/调用。
- 所有决策键读点都走 `AiConfig.X` 符号访问 → 选中的 `const` 改成 `static var`（默认值原样）**调用点零改动**。且 `AiConfig` 已有 `static var difficulty` 先例。
- 离线对局 10 人构成：`_start_game()` → `_create_player_hero`（人类 `is_ai=false`）+ `_create_team_ai(PLAYER,4)` + `_create_team_ai(ENEMY,5)`；全场英雄入 group `"heroes"`；`crystal_destroyed()`(3159) 单点收尾设 `winner` 并 `_show_game_over()`。
- 场景：`lobby.tscn`（默认）/`battle.tscn`（离线可独立跑，soak 用）/`net_client.tscn`。

**同脑对称问题**：自对弈两端用同一策略 → 不能用"单局胜负"做策略信号。故 v1 用**全场效率代理**（发育/推进节奏总量）作适应度，候选与现行策略分场对照取均值。把胜负做成团队感知信号留给 v2（需把决策键改成按 team 读取，工作量大、本版不做）。

## 1. 学习面：AiConfig 决策键 15 个 const→static var

全部默认值=现值，仅改 `const` 关键字并加注释块 `# ===== 可学习参数（AiLearn 自动调优，勿硬改默认值）=====`：

| 键 | 现值 | 语义 | 变异步长/范围 |
|---|---|---|---|
| HEALTH_RECALL | 0.25 | 回城血线 | ±0.05 [0.1,0.5] |
| HEALTH_LOW | 0.4 | 血包血线 | ±0.05 [0.2,0.6] |
| HEALTH_DEFEND | 0.5 | 防守倾向 | ±0.05 [0.2,0.7] |
| DEFENSIVE_HP_RATIO | 0.6 | 防守触发比 | ±0.05 [0.3,0.8] |
| ENGAGE_RANGE | 8.0 | 交战/追击 | ±1.0 [4,12] |
| RETREAT_RANGE | 6.0 | 撤退范围 | ±1.0 [3,10] |
| FLEE_ENEMY_COUNT | 2 | 逃跑敌数(int) | ±1 [1,3] |
| SKILL_USE_RANGE | 10.0 | 技能距离 | ±1.0 [6,14] |
| DODGE_CHANCE | 0.6 | 躲弹道概率 | ±0.1 [0.2,0.9] |
| LANE_THINK_INTERVAL | 1.0 | 线上节拍 | ×/÷1.15 [0.4,2.0] |
| JUNGLE_THINK_INTERVAL | 0.5 | 打野节拍 | ×/÷1.15 [0.25,1.2] |
| EARLY_GAME_END | 240.0 | 分推启动 | ±20 [150,400] |
| DRAGON_GOLD_DEFICIT | 3000 | 落后放弃龙(int) | ±400 [800,5000] |
| SPLIT_LEAD_GOLD | 2000 | 领先分推(int) | ±400 [400,4500] |
| SPLIT_DEFICIT_GOLD | 3000 | 落后分推(int) | ±400 [1000,6000] |

变异：每代从现行 champ 挑 1~2 个键按上表扰动生成 1 个候选；浮点键语义相关的不做交叉约束（门禁/浸泡会兜底）。

## 2. 新 Autoload `AiLearn`（`scripts/ai/AiLearn.gd`）

注册进 `project.godot`（排在 `UiManager` 之后；`AiConfig` 读点全在运行时，autoload `_ready` 先于任何场景覆写即可）。

职责：
- **档案** `user://ai_learn.json`：`{version, generation, champion:{键:值}, champ_proxy_history:[], attempts:[], pending, last_match}`。启动 `_ready` 加载并 `apply_policy(champion)` 写回 AiConfig statics（无档案→默认，即现状行为）。
- `apply_policy(d)`：把 d 的键值赋给 AiConfig 对应 static var（`AiConfig.HEALTH_RECALL = ...`），保证语义 clamp。
- `compute_proxy(bm) -> float`：**效率代理**，对局中任意时刻可算：
  `0.45×双队总金产速 + 0.20×平均等级 + 0.15×总击杀 − 0.20×总阵亡`，再归一到 0~100（公式常量集中在函数头，实现时按现有字段对齐：gold/level/kills/deaths + team_player_gold/team_enemy_gold）。自对弈同策两端，全场总量反映"发育/推进节奏"，即策略效率。
- 训练会话驱动（autoload 跨场景存活，state 不因 change_scene 丢）：
  - `_process`：`in_training` 时——场景是 battle → 检测 BM 就绪 → `bm._start_game(默认英雄)` → 把玩家位 `bm.hero` 转 bot（`is_ai=true` + `add_child(HeroAI.new())`，与 `_create_team_ai` 同法）→ 置 `Engine.time_scale=3.0`，记录本场开始；`bm.game_over` 或 `game_time ≥ 240` → `finish_arm()`。
  - 不在训练、场景是 lobby.tscn 且 `pending≥3`、上次匹配结束已静默 ≥6s、距上次自动训练 ≥60s → 自动开始一代（`in_training=true`, change_scene battle）。
  - Esc → 中断本会话、回 lobby。
  - 训练 HUD：autoload 自挂一个 CanvasLayer 顶角标签（`"AI 学习 第G代 · 经验 n/3 · 候选试炼 x/y · 按 Esc 跳过"`），仅 in_training 显示。
- `finish_arm()`：取 proxy → 依 arm 队列决策：
  - arm = [候选×2, 现行×1] 交替（每代 3 场 ≈ 240s/3× ≈ 1.3 分钟/场）。**一代** ≈ 4 分钟真实时间。
  - 候选两场均值 > 现行场 ×1.015 → 提升 `champion=候选` 并写档；否则保留现行（档案记录 attempt 结果）。
  - 队列空 → 训练会话结束、写档、`Engine.time_scale=1.0`、回 lobby.tscn。
- 真实对局记录（每次打完一把）：
  `bm.crystal_destroyed()` 末尾加一行 `AiLearn.on_match_end(self)`（host/离线单点；也覆盖联机 host）。`on_match_end` 只统计 **`is_ai and not net_taken` 的英雄**（排除人类/联机真人），`compute_proxy` 计入现行 champion 实测池、`pending += 1`、写档——即"每打一把档案必更新"。

## 3. 自对弈完整回路（实现时组装）

lobby（空闲 ≥ pending 阈值）→ AiLearn 自动 change_scene `battle.tscn` → 首帧 `_start_game` 转全员 AI → 限 240s 或到 game_over → `finish_arm` → 下一场（同法切 battle）→ 一代毕 → 可能提升 champion 写档 → 回 lobby。重开 battle.tscn 由引擎自然释放上一场资源，无需手拆节点树。

## 4. 文件改动清单

| 文件 | 改动 |
|---|---|
| `ai/AiConfig.gd` | 15 键 `const`→`static var`（默认值不变）+ 注释块 |
| `scripts/ai/AiLearn.gd`（新） | 见 §2 全部逻辑 |
| `project.godot` | `[autoload]` 增 `AiLearn` |
| `scripts/core/BattleManager.gd` | `crystal_destroyed` 末尾调用 `AiLearn.on_match_end(self)`（1~2 行） |
| 无新场景 | 复用 battle.tscn/lobby.tscn |

训练自检（附加门禁）：AiLearn 支持 `--ai-smoke`（`OS.get_cmdline_user_args`）——开机即跑 1 场候选试炼、cutoff=90s、time_scale=6、场末写档后 `get_tree().quit(0)`。连续跑两次断言档案 `generation` 或 attempt 计数增长 → 证明"每把落档→进化"闭环真实可验。

## 5. 验收与门禁

1. host parse：`G --headless --path . --quit`（无 SCRIPT ERROR）
2. net_client 场景 parse：`G --headless --path . res://scenes/net_client.tscn --quit`
3. 浸泡 100s：battle.tscn exit 124 且零 SCRIPT ERROR（AiLearn 空转不影响）
4. Android export：`--export-debug "Android"`（禁 release）
5. 集成：`pwsh scripts/net/net_integration_test.ps1 -Port 7817`（禁 7000）
6. **训练冒烟**（新）：`G --headless --path . -- --ai-smoke`，连跑两次，断言档案进化计数增长
7. 手动 F5：lobby 连打 2~3 把真人局 → 回 lobby 观察自动"AI 学习"标签与训练场次流转；`user://ai_learn.json` 可见 generation/attempt 变化；esc 可中止回 lobby。

## 6. 边界与诚实预期（写进 README/档案头）

- v1 适应度是**发育/推进效率代理**而非单局胜负（同脑对称无法用胜负信号），学习是"每打一把落档 + 攒满自动进化一代"的缓慢爬坡；偶尔因噪声不提升属预期（保留现行）。
- 训练场限 240s，主要调优 0-4 分钟对线/打野键；4 分钟后的宏观键（EARLY_GAME_END/SPLIT_*/DRAGON_*）靠真人局长局提供 champion 实测证据，进化同样会动它们。
- 不做"匹配玩家水平"的难度自适应（用户明确否决该目标）。
- v2（不在本版）：决策键按 team 感知 → 候选 vs 现行同场对打 + 单局胜负信号。
