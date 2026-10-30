# 沈梦溪1技能「按下连发」+ 东皇太一2技能「1.5米后移落点 + 施放前预览圈」

## 一、背景与已确认的关键事实
- 施放链路：技能按钮按下→(原设计)按住瞄准→松开 → `_start_casting` → 下一帧 `_finish_casting`(扣蓝/CD) → `skillapply.apply_skills(hero, skill_id, pos)` 以协程执行各英雄技能分支。
- 沈梦溪被动(炸弹充能)：`hero.stat` 上限 10，UI 文案早已写「每0.75秒投掷一枚炸弹（可连续，最多5枚）」。Q=slot 0。
- 东皇太一能量体：`donghuang_orbs` 上限 3（Q 加、R 补满、W 消耗）。W=slot 1，技能 type 3，cast_range 6。
- `barrage_live_aim()`(Hero.gd) 上一轮已实现并仍被沈梦溪 Q 使用；东皇 W 本轮由新排布规则取代其逐发跟随。
- `Bullet.set_goal()` + `damage_range` 模式 = 飞到落点原地 AoE 爆炸；`Bullet.on_hit` 对 AoE 范围内敌人会应用 `slow_dur/slow_per/stun_dur`（已验证）。
- 并行会话可能同时编辑 Hero.gd / SkillDataBase.gd → 每次编辑与跑闸门前先 grep 核对目标片段。

## 二、沈梦溪 1技能：按下轮盘即开始、按住跟踪方向 0.75s 一发，松开/弹尽/满5发即停

### 触发点改造（Hero.gd `_handle_skill_input`）
1. 触摸按下循环（现只处理太乙Q）追加：`display_name=="沈梦溪" and i==0` 且未沉默、`skill_cast_ready(0)`、`stat>0` 时——用当前轮盘拖动值 `_compute_skill_aim(...)` 得首发瞄准点，立即 `_start_casting(0,...)`，`continue`（不等松开）。`stat<=0` 不施放（不放空炮、不白耗CD）。
2. 触摸松开循环：对 `display_name=="沈梦溪" and i==0` 直接 `continue`（同太乙Q写法），避免同一次手势「按下+松开」重复施放。
3. 键盘本就按下即施放（just_pressed 分支），无需改；按住键在连发循环里被识别为「仍按住」。
4. 预览：按住期间沿用现有 type1 的 `aoe_fill` 落点圈；CD 开始后隐藏，连发中每发落点由技能循环内的预览圈标示。

### 技能逻辑（SkillDataBase.gd `"沈梦溪":1` 分支整段重写）
- 保留开头疾跑强化 buff（数值原样）。
- `shots = min(5, int(stat))`；`shots==0` 直接结束。
- 连发循环：
  - 第 1 发按下即发（快按=1 发）。
  - 第 2 发起每发前 `await 0.75`；玩家再判「仍按住」(TouchController.get_skill_held(0) or Input.is_action_pressed("skill_0"))，松开即 break（已发保留、剩余充能/弹不烧）。AI(`is_ai`)不做松手判断，整轮打完。
  - 每发 `hero.stat -= 1`；重读 `hero.barrage_live_aim(0, pos)` 得实时瞄准点 aim；炸弹 `set_goal(aim)`、`damage_range=3.0`；每发落点预览圈(create_preview r3)在飞行期间常驻，下一发生成时释放上一发。
  - 伤害/强化分支数值全部原样（180+0.45AP+45*lv；stat2 强化 100+0.25AP+25*lv）。
  - 循环条件 `fired<shots`（满5发自然止，即「>5发」上限）；每轮迭代加 `is_instance_valid(hero) and hero.health>0` 保护；末发预览短暂保留后释放。
- 注：CD 在按下即走(3.5s)，满5发全程约3s；按满后继续按住也不会多发（循环已结束，CD 内也不会再产生施放）。

## 三、东皇太一 2技能：落点按「后一发在前一发身后1.5米」排布 + 施放前生成等量预览圈

### 几何规则
瞄准点为 aim、英雄→aim 的水平单位方向 d、共 n=donghuang_orbs 发：第 i 发落点 `landing = aim - d*1.5*i`（i=0 在 aim；后一发恒较前一发向英雄侧缩1.5m，即逐发回缩排成一条线）。落点以「松开施放」的最终瞄准点一次性算定。

### 施放前预览圈（Hero.gd）
- 新增成员 `donghuang_aim_rings: Array = []`（MeshInstance3D 池，最多3个）。
- 新增 `_show_donghuang_w_preview(aim_pos)`：按规则摆 n 个环（`MeshFactory.create_torus_ring(3.0, 3.25, 团队色, false, 1.0)`，y≈0.2），不足补建、多的隐藏；每帧随 target_pos 更新。新增 `_hide_donghuang_w_preview()`。
- `_handle_skill_input` 预览段：当 `any_held and skill_cast_ready and display_name=="东皇太一" and held_index==1` 时 → 调 `_show_donghuang_w_preview(target_pos)` 并隐藏 arrow/aoe/cast_range 三件套（替换原 type3 箭头预览）；未就绪/未按住路径统一补 `_hide_donghuang_w_preview()`。效果：按住 W 瞄准时可见「数量=能量体数、间隔1.5m、随拖拽移动」的预览圈。
- 东皇 Q/R 与其它英雄不受影响。

### 技能逻辑（SkillDataBase.gd `"东皇太一":2` 分支）
- 保留 ms_haste 加速 buff（数值原样）。
- `total = hero.donghuang_orbs`；若 `total>0`：
  - 由 pos 求 fwd（水平归一；退化用面朝方向）。
  - 每发：`landing = pos - fwd*1.5*i`；落点预览圈(create_preview r3) → await 1.0 → 生成能量体弹（400+0.6AP+100*lv；i==0 减速24%+lv*6%、2s；i==1 减速90%、2s；i==2 眩晕1s —— 数值不变）→ **新增 `bullet.set_goal(landing)`**（飞至各自落点爆炸，而非原线性贯穿/撞敌即爆）→ 挂树 → await 0.5 → 释放预览圈、`donghuang_orbs -= 1`。
  - 移除上一轮「逐发跟随轮盘」的 `barrage_live_aim(1, pos)` 行。
- 末尾 `donghuang_orb_meshes` 清空逻辑保留原样。发射节奏（每发约1.5s）与原实现一致。
- AI 施放走同一分支，同样生效。

## 四、明确不改的部分
- 沈梦溪 2/3 技能、东皇 Q/R、其余所有英雄逻辑不动。
- `barrage_live_aim()` 保留（沈梦溪 Q 仍用）。
- Bullet / TouchController / SkillTouchButton / UI_Manager 不动。

## 五、假定与风险
- 「后面1.5米」取义：后一发落点向施法者一侧回缩1.5m（第0发在瞄准点）。若想要相反（向远处延伸），几何仅差一个符号，改动很小。
- 沈梦溪首发方向=按下瞬间轮盘方向（未拖=手动锁定目标/面朝）；第2发起实时跟轮盘。点按=1发。
- 改动集中在 2 个文件 5 处区域，受并行会话影响 → 每次编辑前后核对。
- 验证：Godot headless parse / 90s 运行 / Android 导出三闸门，错误集合跨运行变化则等树稳定重跑；X=1 干净后报告。
