# Phase 2 修改方案：面板对称化 + 玩家移动/攻击重构 + 王者荣耀式技能施放

## 一、英雄面板 / 商店面板：居中对称 + 关闭按钮（桌面与手机两端一致）

**现状问题**：两个面板在桌面端为全屏铺满（`PRESET_FULL_RECT`），内容全部堆在左上角；关闭按钮只在移动端（`is_mob` 分支）创建，桌面没有关闭按钮 → 看起来「偏左上角、不对称、无法关闭」。

**修改（`scripts/ui/UI_Manager.gd`）**：

1. 新增辅助 `_anchor_center_panel(ctrl: Control, size: Vector2)`：`PRESET_CENTER` 锚定 + 固定尺寸居中（`-size/2 .. +size/2`），两端通用。
2. **英雄面板 `_create_hero_detail_panel`**：
   - 两端统一：面板改为居中对称面板（约 `980×1180`），删除「移动端右抽屉 / 桌面全屏」的分支差异。
   - 遮罩 `hero_detail_dim`：两端都创建，并用 `_connect_tap_to_action(dim, toggle_hero_detail)` —— 点击遮罩即关闭面板（原仅移动端有、且点击不关）。
   - 关闭按钮「×」：两端都创建（面板右上角），点击 → `toggle_hero_detail()`。
   - `ScrollContainer` 保持铺满面板，内容自适应滚动。
3. **商店 `_open_shop`**：
   - `drawer` 两端统一为居中对称面板（约 `1040×1300`），删除分支差异。
   - 遮罩 `dim`：两端都创建，`_connect_tap_to_action(dim, _close_shop)`。
   - 关闭按钮「×」：两端都创建（drawer 右上角），点击 → `_close_shop()`。
   - 内部布局（标题/分类/装备网格/详情/已拥有条）的偏移量都是相对 drawer 的锚点计算，居中后自动适配，无需逐项改动；桌面仍 3 列 / 移动端 2 列。
   - 「打开商店时自动关闭英雄面板」改为两端都执行（原仅移动端）。
4. `_is_fullscreen_open()`（触摸按钮自动隐藏）逻辑不变。

## 二、玩家移动 / 攻击逻辑（`scripts/entities/Hero.gd`）

**现状问题**：锁定目标（`manual_target`，点选敌人产生）超出普攻范围时会自动追击（1133–1137 行）；`_get_attack_target()` 只返回已锁定目标、无自动选敌；且只有站定（不移动）时才发起普攻。

**修改**：

1. **移除玩家自动追击**：1133–1137 的追击分支改为仅 AI 执行（`elif is_ai and manual_target and ...`）。玩家移动只由 左摇杆 `joy_vec` / WASD `input_dir` / 右键移动指令 `move_target` 驱动，**不再因锁定目标而移动**。
2. **超范围清空锁定**：在 `_physics_process` 移动段前新增（仅玩家）：`manual_target` 有效但 `距离 > attack_range * 0.01` → `manual_target = null`（锁定环消失，不再追；AI 保留原行为）。
3. **`_avoid_walls` 调用简化**：去掉玩家向锁定目标截断寻路的分支（1143–1144），玩家一律 `_avoid_walls(move_vec, delta, move_target)`；AI 保持原调用。
4. **重写 `_get_attack_target(range)`**（仅玩家分支）：
   - 锁定目标在范围内 → 优先返回它；
   - 否则在范围内收集所有敌方存活单位：**优先英雄（剩余血量最低者优先），其次非英雄（小兵/塔/野怪，剩余血量最低者优先）**；
   - AI 保持原逻辑（锁定目标在范围→返回，否则 `null`）。
5. **普攻保持站定才打**（用户确认）：保持现有「移动时不普攻、站定（`move_vec.length() <= 0.1`）时才普攻」的结构，不做边走边打。

## 三、技能施放完全仿照王者荣耀（`SkillTouchButton.gd` / `TouchController.gd` / `Hero.gd`）

**现状问题**：移动端非引导技能按下即施放（无瞄准窗口），拖拽瞄准只对引导技能生效；目标型（type 0）技能没有拖拽选目标指示；没有「拖回按钮取消施放」。

**修改**：

1. **`SkillTouchButton.gd`**：松开时记录最终拖拽与取消判定
   - 新增 `signal released(index: int, drag: Vector2, cancelled: bool)`。
   - 手势期间跟踪 `_max_drag`（最大拖拽距离）。
   - 松开时：`final_drag = event.position - _origin`；`cancelled = _max_drag > 30px 且 final_drag.length() < 40px`（「拖出去又拖回按钮」→ 取消；快速点按从未离开按钮 → 判定为施放，即智能施法）。

2. **`TouchController.gd`**：新增 `_skill_release_pending: Array` 与 `consume_skill_release(i) -> Dictionary`；按下时清空、松开时存入 `{drag, cancel}`；`_on_skill_pressed_changed` 连接新的 `released` 信号。

3. **`Hero.gd _handle_skill_input`**：
   - 把 1793–1817 的瞄准计算抽成辅助 `_compute_skill_aim(drag: Vector2, skill: Skill, source_mouse: bool) -> Vector3`（拖拽方向 / 锁定目标 / 面朝方向 → 地面射线 → 限制到 `cast_range`），预览与施放共用。
   - **释放施放（移动端）**：轮询 `consume_skill_release(i)` —— 非取消 → 用释放时的拖拽算目标点并 `_start_casting(i, skills[i], pos)`；取消 → 退出瞄准（`channeling_skill_index = -1`）。引导（channeling）与非引导技能统一走释放施放。
   - **键盘（桌面）保持按下即施放**：`Input.is_action_just_pressed("skill_%d")`，瞄准=鼠标位置，行为不变；原 `channeling_skill_index` 引导释放逻辑仅保留给键盘（触摸端不再走它，避免双次施放）。
   - **保留太乙Q特例**：`taiyi_q_channeling and i == 0` 时按 1 技能 → 立即引爆（按下即处理）。
   - **目标型技能（type 0）**：
     - 按住瞄准拖拽时：新增 `_pick_skill_target(pos, cast_range)` —— 在 `pos` 附近（且处于施法范围内）选最近的敌方单位，并显示小型 `aoe_fill` 目标标记 + 施法范围圈；
     - 施放时：吸附到目标 → 锁定该目标位置；否则回退到新的 `_get_attack_target()`（优先级选敌）；仍无目标 → 不施放（保持现状 fizzle）；
     - 快速点按（tap）＝智能施法：自动选范围内优先级最高的目标（英雄最低血优先）。

**兼容性**：AI 英雄不调用 `_handle_skill_input`（仅玩家），移动/攻击/skill 改动对 AI 行为全部保持不变；17 名英雄技能定义不动。

## 四、验证

1. 无头编译检查：`godot --headless --editor --quit`（0 errors）。
2. 重新导出 Android APK：`godot --headless --export-debug "Android" build/honorking.apk`，确认成功。
