# AI 归档区（未启用）

这里的脚本**不参与运行时**，仅为历史参考保留，不要在新代码里引用。

| 文件 | 原用途 | 归档原因 |
|---|---|---|
| `AiCoordinator.gd` | 早期团队协调原型（BALANCED/AGGRESSIVE/DEFENSIVE/GROUP_UP + 分路池） | 已被 `TeamTactics` + `LaneStrategy` / `JungleStrategy` 取代；`BattleManager` 曾 `new()` 但从未调用 |
| `AiStateMachine.gd` | PUSH/FARM/RETREAT/RECALL/DEFEND/AVOID 状态机 | `HeroAI._ready()` 中早已注释掉，从未实例化 |
| `BehaviorScorer.gd` + `DecisionContext.gd` | 生存/收益/紧急度三维评分的动作选择 | 同上，从未实例化 |
| `behaviors/*.gd` | AiBehavior 基类 + Push/Farm/Defend/Recall 四个行为 | 全项目零实例化 |

当前真实链路见 `ai/HeroAI.gd` 顶部注释。若将来要做评分式决策，请以 `DecisionContext` 为基础重写并替换 `HeroAI._decide()` 的 if 链，而不是直接复活这些原型。
