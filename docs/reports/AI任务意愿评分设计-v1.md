# AI 任务意愿评分设计 v1（待评审）

> 目标：把「固定优先级」改为「硬约束 + 意愿评分」。
> 所有 U 归一化到 0~1，最终优先级 `P = clamp(round(900 * U * 承诺修正), 1, 900)`。
> 生存类硬约束不进入评分池（见文末）。

## 0. 通用记号

| 变量 | 含义 / 计算 |
|---|---|
| `hp` | 当前生命 / 最大生命 |
| `low_hp` | `1 - hp` |
| `mp` | 当前法力 / 最大法力 |
| `low_mp` | `1 - mp`（无蓝英雄=0） |
| `adv` | `(我方存活 - 敌方存活 + 3) / 6`，夹到 0~1 |
| `threat` | `clamp(ThreatModel.enemy_threat() / 2, 0, 1)` |
| `travel(d)` | 距离折扣 = `clamp(1 - 路径时间/8s, 0, 1)` |
| `near(p, r)` | 目标 p 的 r 米内人数系数 = `clamp(1 - 最近距离/r, 0, 1)` |
| `safe(p)` | `1 - clamp(敌方英雄在p附近12m人数/3, 0, 1)` |
| `tower_low` | 目标塔 `1 - 塔当前血量/最大血量` |
| `wave` | 兵线推进度：己方小兵最前线越过河道后的归一化进度 |
| `role_fit` | 英雄职责与任务匹配度（刺客抓人/射手推塔等），0~1 |
| `commit` | 当前任务继续执行的承诺加成 |

## 1. 团队任务层（TeamTactics 下发）

| 任务 | 当前优先级 | 意愿 U 公式 | 主要因子说明 |
|---|---|---|---|
| DEFEND_LANE 守水晶/塔 | 100 | `0.45·crystal_threat + 0.25·tower_low + 0.20·minion_pressure + 0.10·travel` | `crystal_threat`=水晶30m内敌兵数/6；`minion_pressure`=本路敌方兵线压力；`travel`=赶到时间折扣 |
| PUSH_TOWER 抱团推塔 | 90（经济/打龙触发 950） | `0.30·adv + 0.20·gold_lead + 0.20·wave + 0.15·tower_low + 0.15·epic_recent − 0.25·enemy_defense` | `gold_lead`=经济差/10000夹0~1；`epic_recent`=12s内击杀龙/暴君；`enemy_defense`=敌方存活回防人数/5 |
| INVADE_JUNGLE 反野 | 85 | `0.35·adv + 0.25·enemy_jungle_alive + 0.15·jungle_speed + 0.15·travel + 0.10·gold_lead − 0.20·risk` | `enemy_jungle_alive`=敌方半区存活野怪数/6；`jungle_speed`=清野速度/打野适配；`risk`=敌方英雄靠近野区程度 |
| OBJECTIVE 争夺龙/暴君 | 80 | `0.30·gold_parity + 0.25·ally_near + 0.20·enemy_dead + 0.15·dragon_safe + 0.10·travel` | `gold_parity`=1-|经济差|/10000；`ally_near`=己方在龙坑附近人数/5；`dragon_safe`=龙坑敌方威胁反向值 |
| GANK 抓人 | 70（动态 1~900） | `clamp((Σt_ally − Σt_enemy − t_tower·hp_target) / 5, 0, 1)`，`U>0.4` 才抓 | `t=1-d/40`；`t_tower`=目标到其最近塔的 `1-d/20`；即现有可抓指标/5 |
| PEEL 保排 | 50 | `0.40·carry_threat + 0.25·carry_low_hp + 0.20·self_near_carry + 0.15·enemy_dive` | `carry_threat`=射手被威胁程度；`enemy_dive`=敌方突进英雄靠近射手 |
| PUSH_LANE 推线/刷野 | 50 | `0.35·wave + 0.25·lane_safe + 0.20·tower_window + 0.10·role_fit + 0.10·travel` | `tower_window`=本路敌方塔可攻击/兵线到位；`lane_safe`=本路安全度 |
| RETREAT 任务撤退 | 900 | 生存约束，固定最高档，不参与竞争 | 由生存分支直接接管 |

### 团队任务下传到英雄的修正

```
英雄对团队任务的执行意愿 U_hero = U_team × (0.75 + 0.25·role_fit) × travel(到任务点)
```

同一任务对不同英雄的 `role_fit`、距离不同，避免「所有人无脑接同一任务」。

## 2. 英雄 Action 层

| Action | 当前优先级 | 意愿 U 公式 | 主要因子说明 |
|---|---|---|---|
| SAFE_RECALL 回城 | 960 / 958 | `0.40·low_hp + 0.30·low_mp + 0.20·threat + 0.10·no_blue` | `no_blue`=无蓝buff且蓝量低；血量/蓝量到硬阈值时直接强制 |
| RETURN_TO_BASE 撤退 | 900 / 880 | `0.40·threat + 0.25·low_hp + 0.20·trade_cd + 0.15·escape_route` | `trade_cd`=换血CD中；`escape_route`=有安全撤退路线（反向分权方向安全度） |
| DEFEND_TOWER 守塔 | 940 | `0.35·tower_low + 0.25·under_attack + 0.20·enemy_minions + 0.10·self_hp + 0.10·travel` | `under_attack`=本塔正在被攻击；`enemy_minions`=塔附近敌兵 |
| TRADE 换血 | 945 | `0.30·hp_advantage + 0.20·target_low_hp + 0.15·ally_adv + 0.15·no_tower_risk + 0.10·skill_ready + 0.10·near` | `hp_advantage`=自身血量比例-目标血量比例；`skill_ready`=关键技能/召唤师可用 |
| FINISH_CHASE 残血追击 | 940 | `0.30·target_low + 0.20·target_abs_low + 0.20·no_tower_risk + 0.15·ally_support + 0.15·mobility_ready` | `mobility_ready`=闪现/位移技能可用；`ally_support`=附近队友数 |
| TEMP_CLEAR 临时清兵 | 850 | `0.35·gold_at_risk + 0.20·lane_pressure + 0.20·safe + 0.15·travel + 0.10·task_free` | `gold_at_risk`=即将进塔的兵线经济；`task_free`=当前无高价值团队任务 |
| HEALTH_PACK 血包 | 860 | `0.45·low_hp + 0.25·pack_near + 0.20·safe + 0.10·travel` | `pack_near`=血包距离折扣；`low_hp` 高但未到回城线时价值上升 |
| BLUE_BUFF 打蓝 | 870 | `0.40·low_mp + 0.25·buff_near + 0.20·safe + 0.15·travel` | 无蓝英雄/有蓝buff时=0 |
| TRIPOD 拆鼎 | 810 | `0.45·tripod_value + 0.25·safe + 0.20·travel + 0.10·enemy_absent` | `tripod_value`=鼎剩余血量/功能价值；`enemy_absent`=附近无敌人 |
| JUNGLE_FARM 刷野 | 20 | `0.35·camp_near + 0.25·jungle_affinity + 0.20·safe + 0.20·travel` | `camp_near`=最近野怪距离折扣；`jungle_affinity`=打野/清野能力 |
| PUSH_LANE 本地推线 | 20 | `0.40·wave + 0.25·lane_safe + 0.15·tower_window + 0.20·travel` | 默认兜底行为，通常分数最低 |
| TEAM_TASK 执行团队任务 | 70（动态） | `0.85·U_team_or_hero + 0.15·commit` | 团队任务价值下传；`commit`=继续执行加成 |
| VISION_SPIRIT 视野之灵 | 810 | `0.40·spirit_value + 0.30·safe + 0.20·travel + 0.10·vision_need` | `vision_need`=己方视野缺口 |
| DODGE / TOWER_ESCAPE | 1000 | 生存硬约束，`U=1`（触发即执行），不参与比较 | 弹道/塔仇恨即将命中 |

## 3. 选择与防抖

```
P(task) = clamp(round(900 × U × (1 + 0.12 × is_current)), 1, 900)
```

- 只有 `P_new > P_current + 60` 且当前任务已执行 ≥0.8s 才切换
- 同一任务连续执行时 `commit` 逐帧增加，最多 +0.12
- 生存硬约束（死亡/受控/施法/读条/必死塔下）先于评分执行
- 评分不使用随机数，保证 host / 录像确定性

## 4. 不进入评分池的硬约束

- 死亡、复活、泉水养伤
- 眩晕/击飞/压制/沉默/冰冻
- 正在施法、回城读条、传送
- 塔下必死判定
- 网络/回放同步强制动作

## 5. 调参建议

- 所有系数先放进 `AiConfig` 的 `UTILITY_WEIGHTS` 字典，按英雄职责分档
- 第一版先接管：GANK / PUSH_TOWER / INVADE_JUNGLE / OBJECTIVE
- 用影子模式打印 top-3 候选分数，观察 10 局再切换
