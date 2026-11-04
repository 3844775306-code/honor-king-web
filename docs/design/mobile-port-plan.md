# HonorKing 手机版（Android）修改方案

> 日期：2026-08-31
> 目标：Android + 王者荣耀式虚拟摇杆 + 完整改造（UI 全量自适应）
> 工作量估算：7~11 个工作日

**实施进度**

- ✅ 阶段 1 工程配置与渲染（2026-08-31 完成，headless import 验证无错误）
- ✅ 阶段 2 触摸输入系统（2026-08-31 完成，headless import 验证无错误）
- ✅ 阶段 3 UI 自适应重构（2026-08-31 完成，headless import 验证无错误）
- ✅ 阶段 4 性能调优（2026-08-31 完成，headless import + 运行时纹理测试验证通过）
- ⬜ 阶段 5 Android 导出

---

## 一、现状与核心障碍

| # | 障碍 | 现状 | 影响 |
|---|---|---|---|
| 1 | **渲染器** | `project.godot:15` 是 `Forward Plus` | **不支持移动端**，硬性阻塞 |
| 2 | **输入全键鼠** | WASD/右键移动、左键攻击、1/2/3 技能、鼠标瞄准 | 手机没有键盘鼠标 |
| 3 | **UI 全部硬编码** | `UI_Manager.gd`（1883 行）全部写死 2400×1400 像素坐标 | 换分辨率/比例全部错位 |
| 4 | **无导出配置** | 没有 `export_presets.cfg` | 无法打包 |
| 5 | **性能未优化** | 小地图每帧 14400 个 draw_rect、MSAA、阴影 | 中低端机会卡 |

有利条件：

- 3D 场景全部是程序化网格 + StandardMaterial3D，**兼容 Mobile 渲染器**。
- 相机是固定俯视跟随（`BattleManager.gd:2073`），天然适合手机 MOBA。
- **`canvas_items` 缩放模式下，触摸事件坐标自动映射到虚拟 2400×1400 的 Canvas 空间**，`cam.project_ray_origin(event.position)` 这条射线逻辑（`BattleManager.gd:2566`、`Hero.gd:1790`）可原样复用，无需换算坐标。这是方案能落地的核心原因。

---

## 二、阶段 1：工程配置与渲染（0.5~1 天）

### 1.1 切换 Mobile 渲染器

`project.godot`：

```ini
config/features=PackedStringArray("4.5", "Mobile")   ; 第15行

[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
```

场景里的 `DirectionalLight3D shadow_enabled=true`（`BattleManager.gd:120`）Mobile 渲染器支持（1 个阴影方向光），无需改。

### 1.2 显示与缩放策略

```ini
[display]
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/handheld/orientation=4      ; 横屏（sensor landscape）
```

### 1.3 触摸设置

```ini
[input_devices]
pointing/emulate_touch_from_mouse=true    ; 桌面用鼠标模拟触摸，先调手感
pointing/emulate_mouse_from_touch=false   ; 项目默认关闭，移动端在 TouchController._ready 运行时开启
```

**重要修正（2026-08-31）**：最初为防"按技能=走一步"串扰而全局关闭 `emulate_mouse_from_touch`，代价是**所有普通 `Button`（英雄选择"开始游戏"、商店分类/装备/购买/出售）在手机上全部失效**——Godot 4 的 `BaseButton` 原生不处理 `InputEventScreenTouch`，只认鼠标事件。

正确做法（移动端运行时开启模拟 + 消除串扰）：
1. `TouchController._ready`：`Input.set_emulate_mouse_from_touch(OS.has_feature("mobile"))` —— 仅移动端开启，桌面保持关闭走真实鼠标。
2. 串扰防护：摇杆/技能/动作按钮吞掉合成鼠标事件（`accept_event()`）；`BattleManager._unhandled_input` 在模拟开启时跳过鼠标世界点击分支（触摸走 `_handle_world_touch`）；`MiniMap._gui_input` 模拟开启时跳过鼠标事件（触摸路径已完整处理）。
3. 全屏面板（商店/英雄详情/队伍决策/死亡回放）根节点吞掉未消费的触摸（`_block_touch_to_world`），防止点击面板按钮时误触世界移动指令。

### 1.4 Android 构建模板

Godot 编辑器 → 项目 → 安装 Android 构建模板。前置环境：JDK 17、Android SDK（platform-tools + build-tools + platform 35）、NDK r27。

---

## 三、阶段 2：触摸输入系统（核心，2~3 天）

### 3.1 架构：新增 `TouchController` 自动加载 ✅

新建 `scripts/mobile/TouchController.gd`，注册进 `project.godot [autoload]`。它 `_ready` 时创建触摸 UI 层，并暴露统一状态 API：

```gdscript
var move_vector: Vector2          # 摇杆向量 -1~1
var attack_held: bool             # 普攻键
var skill_state: Array            # skill_state[i] = {pressed, just_pressed, aim_screen_pos}
var summoner_just_pressed: bool
var recover_just_pressed: bool
var active_just_pressed: Array    # 2个主动装备槽
```

新增组件（都在 `scripts/mobile/`）：

- **`VirtualJoystick.gd`**（左下锚定）—— 底座+摇杆头，用 `event.index` 区分手指，输出归一化向量。
- **`SkillTouchButton.gd`**（右下 3 个）—— **按下开始瞄准，拖动更新 `aim_screen_pos`，松开施放**；CD/技能等级图层复用 `UI_Manager.gd` 的 `SkillIcon` 样式。
- **`AttackButton.gd`** / **`SummonerButton`** / **`RecoverButton`** / **`ActiveItemButton`(×2)**。
- 顶部快捷按钮：商店(O)、英雄详情(C)、推荐装(B)、队伍(T)。

按钮用 `accept_event()` 吃掉触摸，**落到 UI 上的手指不会触发世界操作**。

### 3.2 `Hero.gd` 接入点（桌面路径保留）✅

| 行 | 现在 | 改成 |
|---|---|---|
| `1102` | `Input.get_axis(...)` WASD | 读 `TouchController.move_vector`，`keyboard_move=false`，让它朝移动方向转向 |
| `1158` | `Input.is_action_pressed("ui_accept")` | 追加 `or TouchController.attack_held` |
| `1778` | `Input.is_action_pressed("skill_%d")` | 读 `skill_state[i].pressed` |
| `1789` | `get_viewport().get_mouse_position()` | 读 `skill_state[i].aim_screen_pos`（未拖时=屏幕中心）—— 下面施法预览/引导/释放代码全部复用 |
| `1864` | `is_action_just_pressed("skill_%d")` | 读 `skill_state[i].just_pressed` |
| `1875/1884` | `summoner_spell` / `recover` | 读对应 `just_pressed` |

### 3.3 `BattleManager.gd` 接入点 ✅

- **`2528 _input` → 改成 `_unhandled_input`**：触摸落在 UI 按钮上时已被 GUI 消费，世界输入自然跳过；键鼠路径不受影响。
- 新增触摸分支（复刻 `2561-2594` 射线逻辑）：`InputEventScreenTouch.pressed` + `event.index==0` 限制主手指 →
  - 点到**敌人** → `set_manual_target()`（普攻）
  - 点到**地面** → `move_towards()`（移动指令）
- 英雄选择界面（`_show_hero_select_ui` `1713`、卡片点击 `1932/1936`）：目前是 `MouseButton` 判定，触摸模拟关闭后失效 → 卡片改 `Button` 控件。
- 相机跟随（`2051-2073`）不动；Tab 第一人称默认在移动端禁用。

### 3.4 小地图触摸 ✅

`MiniMap.gd:49-101 _gui_input` 全是鼠标事件 → 已统一为鼠标/触摸等价处理（按 `event.index`），tap=跳转/传送，drag=拖动相机，并 `accept_event()` 防止穿透到世界输入。逻辑本体（`_local_to_world` 等）不变。

### 3.5 主动装备键 ✅

`ItemPassive.gd:109-170 handle_active_input` 是 V/7/= /9/0/-/8 一串键盘键；`UI_Manager.gd:1595-1596` 的 6/7 键同理。已改为：触摸端在右下角渲染 2 个主动装备按钮，直接调用 `UiManager._trigger_active_equip(hero, i)`，桌面按键路径不动。

### 3.6 触摸按钮修正 ✅（2026-08-31）

针对手机实机反馈（不能打开商店/升级技能/回城/查看英雄面板/购买推荐装备）的根因修复：

- **根因**：`emulate_mouse_from_touch=false` 导致普通 `Button` 全部失效 → 见 1.3 节修正。
- **回城**：原"回城"按钮误接到回血技能（`_recover_press_pending`）。改为 `_recall_press_pending` → `Hero.start_recall()`（`TouchController.consume_recall_press()`）。
- **回血**：新增独立"血"按钮接回回血技能（原按钮被回城占用后补上）。
- **技能升级**：桌面仅 Ctrl+1/2/3 可升级、无自动加点。新增"升"按钮（`hero.skill_points>0` 时显示，优先升 1→2→3 技能），且技能按钮右上角绘制可升级 "+" 徽标。
- **小地图**：右上 → 左上（顶部快捷按钮移到右上角避让）。
- **左侧英雄头像**：`RespawnWidget` 整体放大 1.5×（`ring_radius` 30→45，字号/偏移同步 ×1.5）。

---

## 四、阶段 3：UI 自适应重构 ✅（2026-08-31 完成）

**总策略**：所有硬编码像素坐标 → 锚点定位 + 统一字号常量表（按 `ui_scale()` 缩放，最小可读字号按手机屏保证）。

**实现要点**：

- `UI_Manager.gd` 新增 `ui_scale() = max(1.0, 视口宽/2400) * 1.35`（canvas_items+expand 下虚拟高恒 1400，宽随设备变化），3 个样式 helper + 5 处硬编码字号统一乘缩放。
- 顶部信息带（时间/金币/比分/KDA/推荐装）→ 锚定视口水平中心；Buff 面板 → 右下锚定。
- 桌面技能栏 → 底部整体水平居中；手机端由 `TouchController._update_visibility` 隐藏桌面技能栏，避免与触摸按钮混叠。
- 商店 → 全屏锚定 + 顶部分类横排 + 3 列网格卡片 `SIZE_EXPAND_FILL` 随宽度均分 + 详情面板/装备网格各自 `ScrollContainer` 纵向滚动。
- 英雄详情 → `PRESET_FULL_RECT`；死亡回放 → 居中 + 滚动；队伍决策 → 居中放大（1000 高）。
- 击杀播报 → `PRESET_CENTER_TOP`；回城指示/目标详情 → 尺寸按 `ui_scale()`。
- 英雄选择界面（`BattleManager.gd`）→ 面板/卡片尺寸与字号按 `_ui_scale` 缩放（桌面 1.35，手机更高），保持动态居中。
- 结算 `ResultsPanel.gd` → 已有锚点+滚动，字号 helper 增加 `_ui_scale()`。
- HUD 血条已基于 `get_visible_rect()` 自适应，未改动。

---

## 五、阶段 4：性能调优 ✅（2026-08-31 完成）

1. **小地图 `_draw`（`MiniMap.gd`）** ✅ —— 新增 `_ensure_terrain_texture()` 把 120×120 地形网格一次性渲染成 200×200 的 `ImageTexture`，`_draw` 每帧只 `draw_texture_rect` 一次底图 + 画实体点；`_process` 的 `queue_redraw` 节流到每 3 帧。顺手删掉了每帧都在算、但从未被 `_draw` 使用的 fog_mask 视野网格死代码（原来含 14400 格初始化 + 全部实体×半径² 循环）。运行时验证：纹理 200×200 生成正常，三种地形颜色分布与原地形逻辑一致（丛林 12474 / 分路 18466 / 河道 9060）。
2. **阴影** ✅ —— `rendering/lights_and_shadows/directional_shadow/size=2048`，低端机可再关闭阴影。
3. **MSAA** ✅ —— `rendering/anti_aliasing/quality/msaa_3d=2`（4×）。
4. **帧率** ✅ —— `display/window/vsync/vsync_mode=2`（自适应垂直同步；比方案初稿的 `1`=关闭更优：关闭会在手机上无限跑帧、更耗电且有撕裂，自适应在帧率不足时不同步、帧率充足时才同步）。
5. 运行中若仍卡，优先砍阴影 → MSAA → 粒子，再考虑减兵线数量（涉及游戏平衡，非首选）。

---

## 六、阶段 5：Android 导出（0.5~1 天）

1. 新建 `export_presets.cfg`：`platform="Android"`，包名 `com.xxx.honorking`（自定），`min_sdk=24`，`target_sdk=35`，纹理格式 `ASTC+ETC2` 兼容所有机型。
2. 导出命令（或编辑器内 Export）：

   ```bash
   godot --headless --export-debug "Android" build/honorking.apk
   ```

3. 真机联调：adb 连手机，编辑器"运行到设备"；`logcat` 看崩溃日志。

**国内导出坑（2026-08-31 已修）**：Gradle 发行版下载报 `PKIX path building failed` —— 本机 Java 的 TLS 信任库校验 `services.gradle.org` 证书失败（curl 和其余站点如 `dl.google.com`/`repo.maven.apache.org` 全部正常，仅此一个域名挂）。已把 `android/build/gradle/wrapper/gradle-wrapper.properties` 的 `distributionUrl` 改为腾讯云镜像 `https://mirrors.cloud.tencent.com/gradle/gradle-8.11.1-bin.zip`（Java 可直连，已验证 Gradle 8.11.1 下载安装成功）。依赖下载走 `google()`/`mavenCentral()`/`gradlePluginPortal()`，本机直连均可达，无需额外 Maven 镜像。

---

## 七、工作量与顺序建议

| 阶段 | 内容 | 估算 |
|---|---|---|
| 1 | 渲染器 + 显示 + 触摸设置 + 导出模板 | 0.5~1 天 |
| 2 | 触摸输入系统（核心） | 2~3 天 |
| 3 | UI 自适应重构 | 3~5 天 |
| 4 | 性能调优 | 1 天 |
| 5 | Android 导出 + 真机 | 0.5~1 天 |
| **合计** | | **7~11 个工作日** |

**建议实施顺序**：先做阶段 1 + 阶段 2，用 `emulate_touch_from_mouse` 在 PC 上把"摇杆+技能瞄准"手感调好，再动手阶段 3 的 UI——阶段 3 工作量大且风险最高，UI 应**逐个面板迁移**，先动核心 HUD（顶部信息、商店入口），完整面板后面再迁。

**风险点**：

- 阶段 3 是最大变量，1883 行硬编码坐标，必须增量迁移、每迁一个面板就上真机验证一次。
- 技能"拖拽→松手"的判定时机要在真机上反复调。
- Mobile 渲染器与 Forward+ 有细微视觉差异（无 SSAO），个别特效需微调。
