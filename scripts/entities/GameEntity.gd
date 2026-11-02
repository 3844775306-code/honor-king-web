class_name GameEntity
extends CharacterBody3D

signal died

var entity_id: int = 0
var display_name: String = ""
var team: int = 0
var max_health: float = 100.0
var health: float = 100.0
var attack: float = 0.0
var ability_power: float = 0.0
var attack_range: float = 1.0
var attack_speed: float = 1.0
var armor: float = 0.0
var magic_resist: float = 0.0
var body_radius: float = 0.5
var mana: float = 0.0
var max_mana: float = 100.0
var level: int = 1
var anim_player: AnimationPlayer = null
var current_anim: String = ""
var death_delay_override: float = 0.0   # >0：脚本指定死亡表现时长（无骨骼动画的塔等）
var _shield_fx: MeshInstance3D = null      # 护盾视觉泡（P0：所有护盾统一显示）
var _hit_react_active: bool = false        # 受击后仰动画中（防重入）
var _last_feedback_msec: int = 0           # 镜头反馈节流
var _last_hit_flash_msec: int = 0          # 非英雄受击闪光节流
var can_move: bool = false
var attack_timer: float = 0.0
var anim_atk_seq: int = 0   # 每次真正出手 +1，客户端据此严格按服务器节奏播攻击动作
var current_target: GameEntity = null
var move_speed: int = 350
var vision_range: int = 7
var attack_damage: float = 0.0
var kill_gold: int = 0
var kill_exp: int = 0

# ---------- A* 导航 ----------
var _nav_path = PackedVector3Array()
var _nav_index = 0
var _nav_target = Vector3.ZERO
var _stuck_recovery_t: float = 0.0
var _nav_recalc_timer = 0.0
# 卡墙检测
var _stuck_timer: float = 0.0
var _stuck_pos: Vector3 = Vector3.ZERO
var _stuck_recovery_dir: Vector3 = Vector3.ZERO
# 净进展看门狗：贴墙滑行会让「移动 0.3m」重置卡墙计时，改用「1.2 秒内是否真的更靠近目的地」判定
var _net_timer: float = 0.0
var _net_dist: float = -1.0
var _net_travel: float = 0.0
var _net_progress: float = 0.0   # 1.2s 窗口内沿“到目的地”方向的实际前进量（忽略碰撞推离抖动）
var _net_prev: Vector3 = Vector3.ZERO
# A*路径调试显示（F4切换）
static var debug_show_path: bool = true   # 默认显示AI移动路径（F4可关）
static var debug_show_ai_chip: bool = true  # 显示AI决策胶囊（F5可关）
var _debug_path_nodes: Array = []   # A*路径调试可视化节点（折线+终点球+失败红球）
const DEBUG_PATH_Y := 0.22          # 抬到兵线面(0.14)/高地砖(0.177)之上，否则路径被地面盖住看不见
var _astar_log_cd: float = 0.0

# ---------- 状态效果 ----------
# 移速/攻速增减统一使用 active_buffs 计时条目（见 _calculate_buff / 各 apply_*_buff 入口），
# slow_timer / slow_amount 仅作“净移速效果”报告值供UI/被动读取（每帧在 _process 刷新）。
var slow_timer: float = 0.0    # 报告：移速效果条目中最长剩余时长
var slow_amount: float = 0.0   # 报告：净减速比例（>0减速 <0加速 = -净移速百分比）
var stun_timer: float = 0.0
var knockup_timer: float = 0.0
var last_attacker: GameEntity = null
var last_hit_timer: float = 0.0
var vision_expose_timer: float = 0.0  # 攻击暴露视野残留（2秒）
var skill_reveal_timer: float = 0.0   # 技能侦察视野（鲁班2/后羿R，2秒；可照出草丛/隐身）
var skill_reveal_team: int = -1       # 施放侦察技能的一方，避免敌方也共享该视野
var _last_skill_id: int = -999
var last_type: bool = false
var is_dead: bool = false
var orig: float = 0.0
var actual_attack_damage: float = 0
var actual_ability_power: float = 0
var actual_max_health: float = 0
var actual_armor: float = 0
var actual_magic_resist: float = 0
var actual_move_speed: float = 0
var bonus_attack: float = 0
var bonus_ability_power: float = 0
var bonus_armor: float = 0
var bonus_magic_resist: float = 0
var bonus_move_speed: float = 0
var bonus_move_speed_pct: float = 0.0    # 移速百分比净聚合（条目键 move_speed_pct，正=加速 负=减速）
var bonus_attack_speed_pct: float = 0.0  # 攻速百分比净聚合（条目键 attack_speed_pct，正=更快 负=更慢）
var base_attack: float = 170
var base_ability_power: float = 0
var base_armor: float = 150
var base_magic_resist: float = 75
var base_move_speed: float = 350
var active_buffs: Array = []
# ---------- 经济与连杀 ----------
var kill: int = 0                     # 不死累计击杀数
var primitive_score: int = 0          # 原初积分
var continuous_deaths: int = 0        # 连续死亡次数
var shield_remaining: float = 0.0
var _next_damage_is_true: bool = false   # take_true_damage 的一次性标记：跳过护盾 + 红字
var shield_timer: float = 0.0
var kai_combat_timer: float = 0.0
var wangzhaojun_combat_timer: float = 0.0
var markers: Array = []
var lyf_marks: Dictionary = {}   # 李元芳·暗印: source(Hero) -> {"stacks": int, "timer": float}
var fly:float = 0.0
var fly_timer :float = 0.0
var froze_timer:float = 0.0
var _frozen_tint_active: bool = false             # 冰冻染色状态
var suppress_timer: float = 0.0
var silence_timer: float = 0.0
# 受控时长统计（死亡回放"受控时长"用）：记录处于任一控制下的真实时间区间（仅Hero统计）
var cc_segments: Array = []      # [{start,end,hero,skill}] 已结束的控制区间（秒，按时间单调追加）
var cc_seg_start: float = -1.0   # 当前未结束控制区间的起始时刻；-1 = 未受控
var cc_seg_hero: String = ""     # 当前控制来源英雄名（进入控制时抓取 last_attacker）
var cc_seg_skill: int = -999     # 当前控制来源技能 id（进入控制时抓取 _last_skill_id）
var toughness: float = 0.0
var grievous_wounds: float = 1.0
var grievous_wounds_timer: float = 0.0
var taiyi_protected: bool = false
var taiyi_protect_timer: float = 0.0
var hunt_damage: float = 0.0
var hunt_ticks: int = 0
var hunt_tick_timer: float = 0.0
var hunt_source: GameEntity = null
var hunt_is_magic: bool = false
var attack_speed_timer:float = 1
var lanling_hited: bool =false
	  # 伤害记录（用于死亡回放）
func _calculate_buff():
	for i in range(active_buffs.size() - 1, -1, -1):
		if active_buffs[i]["timer"] > 0:
			bonus_attack += active_buffs[i].get("bonus_attack",0)
			bonus_ability_power += active_buffs[i].get("bonus_ability_power",0)

			bonus_armor += active_buffs[i].get("bonus_armor_resist",0)

			bonus_magic_resist += active_buffs[i].get("bonus_magic_resist",0)
			bonus_move_speed += active_buffs[i].get("bonus_move_speed",0)
			bonus_move_speed_pct += _entry_move_pct(active_buffs[i])
			bonus_attack_speed_pct += active_buffs[i].get("attack_speed_pct",0)
func _recalculate_attributes():
	bonus_armor = 0
	bonus_attack = 0
	bonus_ability_power = 0
	bonus_magic_resist = 0
	bonus_move_speed = 0
	bonus_move_speed_pct = 0
	bonus_attack_speed_pct = 0
	_calculate_buff()

	actual_attack_damage = base_attack  + bonus_attack
	actual_ability_power = base_ability_power + bonus_ability_power
	actual_armor = base_armor  + bonus_armor
	actual_magic_resist = base_magic_resist  + bonus_magic_resist
	actual_move_speed = (base_move_speed + bonus_move_speed)*(1.0 + bonus_move_speed_pct)
	move_speed = actual_move_speed
	attack_damage = actual_attack_damage
	attack = attack_damage
	armor = actual_armor
	attack_speed_timer = clampf(1.0 + bonus_attack_speed_pct, 0.1, 5.0)
	magic_resist = actual_magic_resist
	ability_power = actual_ability_power
	_refresh_speed_report()
	
func setup(config: Dictionary):
	add_to_group("entities")
	entity_id = config.get("id", 0)
	display_name = config.get("name", "")
	team = config.get("team", 0)
	max_health = config.get("max_health", 100.0)
	health = max_health
	attack = config.get("attack", 0)
	ability_power = config.get("ability_power", 0)
	attack_range = config.get("attack_range", 150)
	attack_speed = config.get("attack_speed", 1.0)
	move_speed = config.get("move_speed", 0)
	can_move = move_speed > 0
	armor = config.get("armor", 0)
	magic_resist = config.get("magic_resist", 0)
	body_radius = config.get("body_radius", 0.5)
	mana = config.get("mana", 0)
	max_mana = config.get("max_mana", 100.0)
	kill_gold = config.get("kill_gold", 0)
	kill_exp = config.get("kill_exp", 0)
	base_armor = armor
	base_attack = attack
	base_ability_power = ability_power
	base_magic_resist = magic_resist
	base_move_speed = move_speed

	
# —— 移速/攻速 buff 计时器统一入口 ——
# 减速/加速全部转为 active_buffs 计时条目（与其他属性加成一致）：
#   同 tag 重施加 = 刷新计时与数值；不同 tag 各自独立计时、在 _process 到期后自动移除并重算属性。
# 旧 apply_slow / apply_ak_slow 双参入口已移除，全工程统一按 tag 直接调用下方入口。
# 规范减速 tag 约定（减速是带 cc 的条目，净化/韧性可减免；自身加速不带 cc）：
#   减速(移速)：  apply_move_pct_buff("ms_slow",  dur, -pct, true)
#   减速(攻速)：  apply_attack_pct_buff("as_slow", dur, -pct, true)
#   自身加速(移速)：apply_move_pct_buff("ms_haste",  dur, pct)
#   自身加速(攻速)：apply_attack_pct_buff("as_haste", dur, pct)
# 需要与同类型效果并存/独立计时的场合改用各自专属 tag。
# 单次爆发加速规则：自身移速加成 ≥50%（大禹Q 75%、孙悟空W 90%、刘禅1、不知火舞 50%、
# 孙尚香1、大禹R、夜之守护等）视为爆发加速，自动标记衰减条目，效果随时间线性降到 0（非全程恒定）。

# 固定数值移速 buff：直接加减移速（与基础移速相加），马超拾枪、铠大招等使用。
# 与百分比（move_speed_pct）可叠加：实际 = (基础+bonus_move_speed) × (1+move_speed_pct)
func apply_flat_move_buff(tag: String, duration: float, flat: float):
	_push_or_refresh_speed_buff(tag, duration, {"bonus_move_speed": flat, "cc": false}, false)

# 带符号百分比移速/攻速 buff 通用入口（pct>0 加速/更快，<0 减速/更慢）。用于英雄/装备特殊效果。
func apply_move_pct_buff(tag: String, duration: float, pct: float, cc: bool = false):
	_push_or_refresh_speed_buff(tag, duration, {"move_speed_pct": pct, "cc": cc}, cc)

func apply_attack_pct_buff(tag: String, duration: float, pct: float, cc: bool = false):
	_push_or_refresh_speed_buff(tag, duration, {"attack_speed_pct": pct, "cc": cc}, cc)

# 按 tag 移除某个移速/攻速 buff（常驻光环退出、霸体解除等）
func remove_speed_buff(tag: String):
	var changed := false
	for i in range(active_buffs.size() - 1, -1, -1):
		if active_buffs[i].get("_tag", "") == tag:
			active_buffs.remove_at(i)
			changed = true
	if changed:
		_recalculate_attributes()

# 当前是否带某个 tag 的移速/攻速 buff（用于条件刷新/避免每帧重复施加）
func has_speed_buff(tag: String) -> bool:
	for b in active_buffs:
		if b.get("_tag", "") == tag:
			return true
	return false

# 净化/霸体：移除全部控制类减速（移速+攻速），保留自身加速类效果
func remove_cc_speed_buffs():
	var changed := false
	for i in range(active_buffs.size() - 1, -1, -1):
		if active_buffs[i].get("cc", false):
			active_buffs.remove_at(i)
			changed = true
	if changed:
		_recalculate_attributes()

# 核心写入：找到同 tag 条目则刷新（时长与数值整体覆盖），否则追加新条目。
# duration <= 0 时视为“取消该 tag 效果”（取消可直接调用 remove_speed_buff(tag)）。
func _push_or_refresh_speed_buff(tag: String, duration: float, keys: Dictionary, is_cc: bool):
	if duration <= 0.0:
		remove_speed_buff(tag)
		return
	if is_cc and _is_speed_cc_immune():
		return
	for b in active_buffs:
		if b.get("_tag", "") == tag:
			b["timer"] = duration
			for k in keys:
				b[k] = keys[k]
			_set_decay_fields(b)
			_recalculate_attributes()
			return
	var entry: Dictionary = keys.duplicate()
	entry["timer"] = duration
	entry["_tag"] = tag
	_set_decay_fields(entry)
	active_buffs.append(entry)
	_recalculate_attributes()

# —— 单次爆发加速（自身移速百分比加成 ≥50%）随时间线性衰减 ——
# 施加时标记衰减条目(_decay/_full)；_calculate_buff/_entry_move_pct 按“剩余时长/总时长”
# 取当前生效百分比（满值→0），每帧由 _refresh_decaying_move_speed 轻量刷新实际移速。
# 仅作用于自身正百分比移速条目；减速(负值/带cc)、攻速不受影响；同 tag 重施加会刷新并重新从满值衰减。
func _set_decay_fields(entry: Dictionary):
	entry.erase("_decay")
	entry.erase("_full")
	if entry.get("move_speed_pct", 0.0) >= 0.5:
		entry["_decay"] = true
		entry["_full"] = float(entry.get("timer", 0.0))

# 读条目“当前生效”的移速百分比：衰减条目从施加值随时间线性减到 0，其余原样返回
func _entry_move_pct(b: Dictionary) -> float:
	var mv := float(b.get("move_speed_pct", 0.0))
	if mv != 0.0 and b.get("_decay", false):
		var full := float(b.get("_full", b.get("timer", 0.0)))
		if full > 0.0:
			mv *= clampf(float(b.get("timer", 0.0)) / full, 0.0, 1.0)
	return mv

# 霸体/无法选中期间免疫控制减速（Hero 可覆写）
func _is_speed_cc_immune() -> bool:
	return false

# 每帧刷新 slow_timer / slow_amount 报告值（净移速百分比与最长剩余时长）
func _refresh_speed_report():
	var _net := 0.0
	var _longest := 0.0
	for b in active_buffs:
		if b.has("move_speed_pct") and float(b.get("timer", 0.0)) > 0.0:
			_net += _entry_move_pct(b)
			if float(b.get("timer", 0.0)) > _longest:
				_longest = float(b["timer"])
	slow_amount = -_net
	slow_timer = _longest

# 有衰减中的加速条目时每帧轻量刷新实际移速：只重聚移速池并按衰减瞬时值重烘焙，
# 避免把整套属性重算（装备/攻速等）挂到每帧
func _refresh_decaying_move_speed():
	bonus_move_speed_pct = 0.0
	for b in active_buffs:
		if float(b.get("timer", 0.0)) > 0.0:
			bonus_move_speed_pct += _entry_move_pct(b)
	actual_move_speed = (base_move_speed + bonus_move_speed) * (1.0 + bonus_move_speed_pct)
	_refresh_speed_report()

func _apply_ak_buff(flat_bonus: float, percent_bonus: float, duration: float,is_magic:bool):
	if is_magic:
		var bonus_val = flat_bonus + actual_ability_power * percent_bonus
		active_buffs.append({
			"timer": duration,
			"bonus_ability_power": bonus_val
		})
	else:
		var bonus_val = flat_bonus + actual_attack_damage * percent_bonus
		active_buffs.append({
			"timer": duration,
			"bonus_attack": bonus_val
		})
	_recalculate_attributes()
func _apply_df_buff(flat_bonus: float, percent_bonus: float, duration: float,is_magic:bool):
	# 临时增加攻击力（基础值 + 百分比）
	if is_magic:
		var bonus_val = flat_bonus + actual_magic_resist * percent_bonus
		
		# 记录Buff，用于持续时间结束后移除
		active_buffs.append({
			"timer": duration,
			"bonus_magic_resist": bonus_val
		})
	else:
		var bonus_val = flat_bonus + actual_armor * percent_bonus
		
		active_buffs.append({
			"timer": duration,
			"bonus_armor_resist": bonus_val
		})
	_recalculate_attributes()
func count_markers(source)->int:
	var count = 0
	for i in range(markers.size() - 1, -1, -1):
		if markers[i]["source"] ==source:
			count +=1
	return count
func clear_markers(source):
	for i in range(markers.size() - 1, -1, -1):
		if markers[i]["source"] ==source:
			markers.remove_at(i)
func get_marker_sources()->Array:
	var sources = []
	for i in range(markers.size() - 1, -1, -1):
		if not markers[i]["source"] in sources:
			sources.append(markers[i]["source"])
	return sources
# ================ 李元芳·暗印印记 ================
const LYF_MARK_RADIUS := 1.6      # 暗印爆炸波及半径(米)
const LYF_MARK_MAX_STACKS := 4    # 叠满立即引爆
const LYF_MARK_CD := 4.0          # 印记持续/刷新时长(秒)
func lyf_mark_stack(source) -> int:
	var e = lyf_marks.get(source)
	return int(e.get("stacks", 0)) if e else 0
func lyf_mark_timer(source) -> float:
	var e = lyf_marks.get(source)
	return float(e.get("timer", 0.0)) if e else 0.0
# Q 施放命中：挂上 0 层印记并开始计时（普攻叠层只作用于已带印记的目标）
func lyf_cast_mark(source) -> void:
	if source == null or not is_instance_valid(source):
		return
	lyf_marks[source] = {"stacks": 0, "timer": LYF_MARK_CD}
	_lyf_dart_visual(1, LYF_MARK_CD)
# 普攻/大招命中：叠 1 层并刷新计时；满层立即引爆（返回是否引爆）
func lyf_add_mark(source) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	var e = lyf_marks.get(source)
	if e == null:
		lyf_marks[source] = {"stacks": 1, "timer": LYF_MARK_CD}
		_lyf_dart_visual(2, LYF_MARK_CD)
		return false
	e["stacks"] = int(e["stacks"]) + 1
	e["timer"] = LYF_MARK_CD
	if int(e["stacks"]) >= LYF_MARK_MAX_STACKS:
		lyf_detonate(source)
		return true
	_lyf_dart_visual(int(e["stacks"]) + 1, LYF_MARK_CD)
	return false
# 暗印飞镖视觉同步：飞镖数 = 已叠层数+1（Q 0层=1枚，普攻叠层递增，最多显示3枚）
func _lyf_dart_visual(count: int, life: float) -> void:
	if self is Node3D and is_inside_tree():
		Vfx.lyf_dart_sync(self, count, life)
# 引爆：对标记目标及其周围半径内敌人造成物理伤害（skill_id=-80 避开一切 on-hit 分支）
func lyf_detonate(source) -> void:
	var e = lyf_marks.get(source)
	if e == null:
		return
	var stacks = int(e.get("stacks", 0))
	lyf_marks.erase(source)
	Vfx.lyf_dart_clear(self, true)
	if source == null or not is_instance_valid(source):
		return
	if is_dead or health <= 0.0:
		return
	var lv = int(source.skill_levels[0]) if "skill_levels" in source else 1
	var base = 220.0 + 44.0 * maxi(0, lv - 1)
	var dmg = (base + float(source.bonus_attack) * 0.7) * (1.0 + float(stacks))
	for ent in get_tree().get_nodes_in_group("entities"):
		if not is_instance_valid(ent) or ent.health <= 0 or ent.team == source.team:
			continue
		if ent != self and global_position.distance_to(ent.global_position) > LYF_MARK_RADIUS:
			continue
		ent.take_damage(dmg, source, false, -80, 0)
# 预测：此刻引爆 source 的暗印，对本实体将造成的实际伤害（减伤镜像同 take_damage 物伤流程，
# 含平A物穿/苍穹法伤互调/李元芳对非英雄5%加成；护盾在血条层另扣，此处返回未扣盾裸伤）
func lyf_predicted_damage(source) -> float:
	if source == null or not is_instance_valid(source) or not lyf_marks.has(source):
		return 0.0
	var e = lyf_marks[source]
	var stacks := int(e.get("stacks", 0))
	var lv := int(source.skill_levels[0]) if ("skill_levels" in source and source.skill_levels.size() > 0) else 1
	var base := 220.0 + 44.0 * maxi(0, lv - 1)
	var dmg := (base + float(source.bonus_attack) * 0.7) * (1.0 + float(stacks))
	var res := armor
	if source is Hero:
		res -= float(source.flat_phys_pen)
	res = maxf(res, 0.0)
	var actual := dmg * (1.0 - res / (res + 602.0))
	if source is Hero and source.equipment_slots.has("sky_book"):
		var sr := actual_ability_power / 100.0 * 0.005
		actual *= 1.0 + sr
	if self is Hero and self.equipment_slots.has("sky_book"):
		var sr := actual_ability_power / 100.0 * 0.005
		actual *= 1.0 - sr
	if source is Hero and source.display_name == "李元芳" and not (self is Hero):
		actual *= 1.05
	return actual
# 暗印来源汇总（供血条层数显示/黄色预判段/联机打包）
func lyf_mark_summary() -> Array:
	var out := []
	for src in lyf_marks.keys():
		if src == null or not is_instance_valid(src):
			continue
		out.append({"source": src, "stacks": lyf_mark_stack(src), "pred": lyf_predicted_damage(src)})
	return out
# ================ 受控时长统计（死亡回放"受控时长"） ================
# 仅英雄、存活时统计：只要处于眩晕/击飞/冰冻/压制/沉默任一状态即记一段连续区间，
# 同时被多种控制只算一次；用真实时钟记录，死亡回放按近7秒窗口求交。
func _update_cc_segment() -> void:
	if not self is Hero:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var under_cc := (not is_dead and health > 0.0
			and (stun_timer > 0.0 or knockup_timer > 0.0 or froze_timer > 0.0
				or suppress_timer > 0.0 or silence_timer > 0.0))
	if under_cc:
		if cc_seg_start < 0.0:
			cc_seg_start = t
			cc_seg_hero = ""
			cc_seg_skill = -999
		if cc_seg_hero == "" and last_attacker != null and is_instance_valid(last_attacker):
			cc_seg_hero = str(last_attacker.display_name)
			cc_seg_skill = _last_skill_id
	elif cc_seg_start >= 0.0:
		cc_segments.append({"start": cc_seg_start, "end": t,
			"hero": cc_seg_hero, "skill": cc_seg_skill})
		cc_seg_start = -1.0
		cc_seg_hero = ""
		cc_seg_skill = -999

# 返回最近 window 秒内处于控制状态的总时长（秒）；顺带清理窗口外的旧区间
func get_cc_duration(window: float) -> float:
	var t := Time.get_ticks_msec() / 1000.0
	var thr := t - window
	while not cc_segments.is_empty() and cc_segments[0]["end"] < thr:
		cc_segments.pop_front()
	var total := 0.0
	for s in cc_segments:
		var seg_start := maxf(s["start"], thr)
		var seg_end := minf(s["end"], t)
		if seg_end > seg_start:
			total += seg_end - seg_start
	if cc_seg_start >= 0.0:
		total += maxf(0.0, t - maxf(cc_seg_start, thr))
	return total

# 按「来源英雄 + 技能」聚合近 window 秒受控时长；未记录的来源归入「未知来源」。
func get_cc_breakdown(window: float) -> Array:
	var t := Time.get_ticks_msec() / 1000.0
	var thr := t - window
	while not cc_segments.is_empty() and cc_segments[0]["end"] < thr:
		cc_segments.pop_front()
	var agg: Dictionary = {}
	for s in cc_segments:
		var a := maxf(float(s["start"]), thr)
		var b := minf(float(s["end"]), t)
		if b > a:
			_add_cc_span(agg, str(s.get("hero", "")), int(s.get("skill", -999)), b - a)
	if cc_seg_start >= 0.0:
		var a2 := maxf(cc_seg_start, thr)
		if t > a2:
			_add_cc_span(agg, cc_seg_hero, cc_seg_skill, t - a2)
	var out: Array = []
	for k in agg.keys():
		out.append(agg[k])
	out.sort_custom(func(x, y): return float(x["duration"]) > float(y["duration"]))
	return out

func _add_cc_span(agg: Dictionary, hero_name: String, skill_id: int, dur: float) -> void:
	if dur <= 0.01:
		return
	var key := hero_name + "|" + str(skill_id)
	if not agg.has(key):
		agg[key] = {"hero": hero_name, "skill": skill_id, "duration": 0.0}
	agg[key]["duration"] = float(agg[key]["duration"]) + dur

func _process(delta: float) -> void:
	if skill_reveal_timer > 0.0:
		skill_reveal_timer = maxf(0.0, skill_reveal_timer - delta)
	if knockup_timer > 0:
		knockup_timer -= delta * (1.0 + toughness)
		attack_timer =0.5
		global_position.y=-pow(knockup_timer-0.75,2)*8/9+2
	else:
		if fly == 0:
			global_position.y=0
		else:
			global_position.y=fly
			fly_timer -=delta
			if fly_timer<=0:
				fly =0
	# Buff 计时器：统一在此扣时，控制类减速(c标记)受韧性加成缩短；到期条目移除并重算属性，
	# 保证移速/攻速等加成到期后立刻还原（不再遗留陈旧数值）。
	var buff_expired := false
	var has_decay := false
	for i in range(active_buffs.size() - 1, -1, -1):
		var tick_rate := (1.0 + toughness) if active_buffs[i].get("cc", false) else 1.0
		active_buffs[i]["timer"] -= delta * tick_rate
		if active_buffs[i]["timer"] <= 0:
			active_buffs.remove_at(i)
			buff_expired = true
		elif active_buffs[i].get("_decay", false):
			has_decay = true
	if buff_expired:
		_recalculate_attributes()
	elif has_decay:
		_refresh_decaying_move_speed()
	else:
		_refresh_speed_report()

	for i in range(markers.size() - 1, -1, -1):
		markers[i]["timer"] -= delta
		if markers[i]["timer"] <= 0:
			if markers[i].has("lanling_mark_dmg"):
				if health > 0:
					var mark_src = markers[i].get("source")
					if is_instance_valid(mark_src):
						take_damage(markers[i]["lanling_mark_dmg"], mark_src, false, -46, 0)
					else:
						take_damage(markers[i]["lanling_mark_dmg"], null, false, -46, 0)
			markers.remove_at(i)

	# 李元芳·暗印到期：按当前层数引爆（仅存活目标）
	for _lyf_src in lyf_marks.keys():
		var _le = lyf_marks[_lyf_src]
		_le["timer"] -= delta
		if float(_le["timer"]) <= 0.0:
			lyf_detonate(_lyf_src)

	if froze_timer > 0:
		froze_timer -= delta * (1.0 + toughness)
		if not _frozen_tint_active:
			_set_freeze_visual(self, true)
			_frozen_tint_active = true
	elif _frozen_tint_active:
		_set_freeze_visual(self, false)
		_frozen_tint_active = false
	if suppress_timer > 0:
		suppress_timer -= delta
	if silence_timer > 0:
		silence_timer -= delta
	
	# 狩猎DoT
	if hunt_ticks > 0:
		hunt_tick_timer -= delta
		if hunt_tick_timer <= 0:
			hunt_tick_timer = 0.5
			take_damage(hunt_damage, hunt_source, hunt_is_magic, -40, 0)
			hunt_ticks -= 1
			if hunt_ticks <= 0:
				hunt_source = null
	# 受控时长统计（每帧刷新控制区间，仅Hero内部判断）
	_update_cc_segment()
	_update_shield_visual()

# 护盾视觉泡：shield_remaining > 0 时显示团队色半透明球，护盾清空自动移除。
# 统一在基类处理，覆盖所有直接写 shield_remaining 的技能/装备，无需逐个插桩。
func _update_shield_visual() -> void:
	if shield_remaining > 0.0 and health > 0.0 and not is_dead:
		if _shield_fx == null or not is_instance_valid(_shield_fx):
			_shield_fx = MeshInstance3D.new()
			_shield_fx.name = "ShieldFx"
			var sm := SphereMesh.new()
			sm.radius = 1.05
			sm.height = 2.1
			sm.radial_segments = 16
			sm.rings = 8
			_shield_fx.mesh = sm
			_shield_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.albedo_color = Color(0.55, 0.82, 1.0, 0.15)
			mat.emission_enabled = true
			mat.emission = Color(0.45, 0.78, 1.0)
			mat.emission_energy_multiplier = 1.1
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_shield_fx.material_override = mat
			# 护盾泡加两条倾斜光环：避免“纯色球”观感（全英雄护盾技能共用）
			for ri in range(2):
				var rim := MeshInstance3D.new()
				var trm := TorusMesh.new()
				trm.inner_radius = 1.06 + 0.06 * float(ri)
				trm.outer_radius = 1.18 + 0.06 * float(ri)
				trm.rings = 24
				trm.ring_segments = 6
				rim.mesh = trm
				rim.material_override = mat
				rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				rim.rotation = Vector3(PI * 0.5 + 0.32 * float(ri), 0.0, PI * 0.18 * float(ri + 1))
				rim.name = "ShieldRim%d" % ri
				_shield_fx.add_child(rim)
			add_child(_shield_fx)
		_shield_fx.position = Vector3(0, 0.95, 0)
		# 光环缓慢自转 + 呼吸式缩放
		var st := Time.get_ticks_msec() / 1000.0
		_shield_fx.rotation.y = st * 0.85
		var rim_a := _shield_fx.get_node_or_null("ShieldRim0")
		var rim_b := _shield_fx.get_node_or_null("ShieldRim1")
		if rim_a != null: rim_a.rotation.y = -st * 1.4
		if rim_b != null: rim_b.rotation.z = PI * 0.36 + sin(st * 2.0) * 0.2
		_shield_fx.scale = Vector3.ONE * (1.0 + 0.035 * sin(st * 4.2))
		_shield_fx.visible = true
		var ratio := clampf(shield_remaining / maxf(1.0, actual_max_health * 0.5), 0.25, 1.0)
		var s := 0.82 + 0.18 * ratio
		_shield_fx.scale = Vector3(s, s * 1.05, s)
	elif _shield_fx and is_instance_valid(_shield_fx):
		_shield_fx.queue_free()
		_shield_fx = null

# 受击反馈（P0 全局）：命中的单位统一闪白；英雄额外镜头轻震 + 受击后仰。
# 非英雄只做材质闪光/轻抖，不生成额外粒子，避免小兵/野怪高频受击吃光特效预算。
func _damage_feedback(actual: float, _is_magic: bool) -> void:
	if actual <= 0.0 or get_tree() == null:
		return
	# 回放：记录受击时刻（与本地闪白/后仰同一时机），回放按同帧复现
	var _rec = get_tree().get_first_node_in_group("replay_recorder")
	if _rec != null and self is Hero:
		_rec.call("note_hit", self, actual)
	if not (self is Hero):
		var now := Time.get_ticks_msec()
		if now - _last_hit_flash_msec >= 70:
			_last_hit_flash_msec = now
			var root := get_hit_flash_root()
			UnitVisuals.hit_flash(root)
			UnitVisuals.hit_pulse(root)
			if has_method("play_hit_react"):
				call("play_hit_react")
		return
	# 本地玩家英雄受击闷响（内部按本人过滤；小额伤害/DoT 不响，节流在 SfxManager）
	if actual > maxf(20.0, actual_max_health * 0.03):
		SfxManager.try_hurt_sfx(display_name)
	var col: Color = Vfx.color_for_hero(display_name) if self is Hero else Vfx.team_color(team)
	Vfx.hit_spark(global_position + Vector3.UP * (1.15 if self is Hero else 0.55), col)
	var bm := get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if bm and self is Hero and bm.hero and is_instance_valid(bm.hero):
		var now := Time.get_ticks_msec()
		if now - _last_feedback_msec > 90:
			_last_feedback_msec = now
			if global_position.distance_to(bm.hero.global_position) < 14.0 \
					and actual > maxf(5.0, actual_max_health * 0.02):
				bm.camera_shake(clampf(0.03 + actual / 5000.0, 0.03, 0.12), 0.18)
	if self is Hero and not _hit_react_active:
		var hm := self as Hero
		if hm.visual_mesh and is_instance_valid(hm.visual_mesh) \
				and actual > maxf(8.0, actual_max_health * 0.04):
			_hit_react_active = true
			var tw := create_tween()
			tw.tween_property(hm.visual_mesh, "rotation:x", -0.14, 0.06)
			tw.tween_property(hm.visual_mesh, "rotation:x", 0.0, 0.14)
			tw.tween_callback(func(): _hit_react_active = false)

# --- 伤害来源调试映射 ---
## 受击闪光的可视根；小兵/野怪/塔覆盖为模型根，避免把范围环等辅助节点一起闪白
func get_hit_flash_root() -> Node3D:
	return self

func _skill_source_label(skill_id: int, source: GameEntity = null) -> String:
	match skill_id:
		1, 2, 3: return "技能" + str(skill_id)
		0:   return "普攻"
		-1:
			
			if source is Minion:
				return "小兵攻击"
			return "被动"
		-2:  return "红buff灼烧"
		-41: return "血魔之怒(附伤)"
		-42: return "反伤刺甲(反弹)"
		-43: return "闪电匕首(技能触发)"
		-44: return "冰霜冲击(主动)"
		-45: return "东皇能量体"
		-46: return "兰陵王标记"
		-47: return "张飞变身附伤"
		-48: return "亚瑟标记"
		-49: return "终结"
		-50: return "惩击"
		-51: return "王昭君冰霜冲击"
		-52: return "王昭君强化普攻"
		-10: return "红莲斗篷(灼烧)"
		-11: return "反伤刺甲(反伤)"
		-20: return "闪电匕首(链式电弧)"
		-22: return "金色圣剑(AP附伤)"
		-23: return "巫术法杖(强化普攻)"
		-25: return "凝冰之息(普攻附伤)"
		-26: return "无尽战刃(暴击)"
		-27: return "回响之杖(爆炸)"
		-28: return "痛苦面具(灼烧)"
		-30: return "日渊(溅射)"
		-32: return "破魔刀(附伤)"
		-33: return "不死鸟之眼(反伤)"
		-40: return "打野刀狩猎DoT"
		-72: return "末世(视作普攻)"
		-73: return "金色圣剑(视作普攻)"
		-74: return "逐日之弓(视作普攻)"
		-75: return "破晓(视作普攻)"
		_: return "其他(" + str(skill_id) + ")"

# 统一的“回血”入口：所有治疗/生命回复类计算都应调用本函数，而不是直接改 health。
# 基类版本：过滤非法值、按重伤比例削减、封顶到实际最大生命；Hero 重写后额外累加治疗量统计、
# 处理不死鸟之眼被动。返回实际回血量（0 表示没有产生回血）。
func _apply_healing(amount: float) -> float:
	if amount <= 0 or health <= 0:
		return 0.0
	amount *= grievous_wounds
	var cap := actual_max_health if actual_max_health > 0 else max_health
	var actual = min(amount, cap - health)
	if actual > 0:
		health += actual
	return max(actual, 0.0)

## 真伤（无视护盾）：一次性标记后走常规 take_damage，弹红字
func take_true_damage(amount: float, source: GameEntity = null, is_magic: bool = false, skill_id: int = 0, pen_percent: float = 0.0) -> void:
	_next_damage_is_true = true
	take_damage(amount, source, is_magic, skill_id, pen_percent)
	_next_damage_is_true = false

func take_damage(amount: float, source: GameEntity = null, is_magic: bool = false, skill_id:int=0, pen_percent: float = 0.0, is_crit_forced: int = -1):
	if health <= 0:
		return
	# 真伤标记（take_true_damage 一次性置位）：无视护盾且弹红字
	var is_true_damage: bool = _next_damage_is_true
	_next_damage_is_true = false
	var bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	var _raw_amount := amount   # 调试：保存原始伤害
	var _is_magic_debug := is_magic   # 调试：保存伤害类型
	
	# 暗影之径：整条分路上的友方单位10%免伤（固定60秒，与先锋存活无关）
	if bm and not (self is Turret) and bm.is_on_shadow_path(team, global_position):
		amount *= 0.9
	# jungle protection: first 4 min, a HERO standing in the enemy zone (outside the river)
	# deals 25% reduced damage to enemy heroes and jungle monsters.
	if bm and bm.game_time < 240.0 and source is Hero and (self is Hero or self is JungleMonster):
		if BattleManager.in_enemy_jungle_zone(source.global_position, source.team):
			amount *= 0.75
	# 越塔保护：身处敌方防御塔射程内的英雄，对敌方英雄造成的伤害按阶段降低
	#（前4分钟-25% → 4-10分钟-10% → 10分钟后-5%）；buff 图标与野区保护同源
	if bm and source is Hero and self is Hero:
		if bm.hero_under_enemy_tower(source):
			amount *= bm.tower_dive_factor()

	# 君临/暗影君临：命中触发闪电链（3s内置CD，skill_id<0 不触发防递归）
	if source is Hero:
		if source.tyrant_lightning_active and source.tyrant_lightning_cd <= 0 and skill_id >= 0:
			source.tyrant_lightning_cd = 3.0   # 先置CD防链式递归
			var chain_dmg_hero = (30 + 30 * source.level) if source.tyrant_lightning_shadow else (20 + 10 * source.level)
			var chain_dmg_other = (50 + 50 * source.level) if source.tyrant_lightning_shadow else (60 + 30 * source.level)
			var chain_target: GameEntity = null
			var best_dist := 6.0
			for entity in get_tree().get_nodes_in_group("entities"):
				if entity == self or entity == source or entity.health <= 0: continue
				if entity is Turret: continue
				if entity.team == source.team: continue
				var d = global_position.distance_to(entity.global_position)
				if d < best_dist:
					best_dist = d
					chain_target = entity
			if chain_target:
				var dmg = chain_dmg_hero if chain_target is Hero else chain_dmg_other
				chain_target.take_damage(dmg, source, true, -53, 0)
				# 闪电链视觉：源→目标锯齿光束（暗影君临为紫色）
				var chain_color = Color(0.65, 0.5, 1.0) if source.tyrant_lightning_shadow else Color(0.4, 0.8, 1.0)
				LightningEffect.spawn(get_parent(), source.global_position + Vector3(0, 1.2, 0), chain_target.global_position + Vector3(0, 1.0, 0), chain_color)
	
	# 战斗状态
	# 铠被动：受伤时重置脱战计时器
	if self is Hero and display_name == "铠": kai_combat_timer = 7.0
	if self is Hero and self.display_name == "王昭君": 
		wangzhaojun_combat_timer = 5.0
	if source and source is Hero and source.display_name == "王昭君":
		source.wangzhaojun_combat_timer = 5.0
	# 攻击暴露视野：攻击者与被攻击者互相暴露2秒
	if not source is JungleMonster and not self is JungleMonster:
		source.vision_expose_timer = 2.0
		vision_expose_timer = 2.0
	# 李元芳被动·密探谛听：命中任意单位 → 以受害者为中心暴露草丛中敌方英雄1秒(每个英雄8s CD)
	if source is Hero and source.display_name == "李元芳":
		var _lyf_now = Time.get_ticks_msec() / 1000.0
		var _lyf_src = source
		if not _lyf_src.lyf_reveal_cd:
			_lyf_src.lyf_reveal_cd = {}
		for _ent in get_tree().get_nodes_in_group("heroes"):
			if not is_instance_valid(_ent) or _ent is not Hero or _ent.health <= 0 or _ent.team == _lyf_src.team:
				continue
			if not _ent.hidden_in_bush:
				continue
			if global_position.distance_to(_ent.global_position) > 4.0:
				continue
			if _lyf_src.lyf_reveal_cd.has(_ent) and _lyf_now < _lyf_src.lyf_reveal_cd[_ent]:
				continue
			_lyf_src.lyf_reveal_cd[_ent] = _lyf_now + 8.0
			_ent.vision_expose_timer = maxf(_ent.vision_expose_timer, 1.0)

	# 伤害前英雄效果
	# 兰陵王标记: 受击晕眩+回血
	if not lanling_hited and source is Hero and source.display_name == "兰陵王" and count_markers(source) > 0:
		stun_timer = 1.0
		source._apply_healing(280 + source.skill_levels[1] * 70 + source.bonus_health * 0.1)
		lanling_hited = true
	# 王昭君：护盾存在时受物理伤害→攻击者被挂冰冷（减速+减攻速）
	if self is Hero and display_name == "王昭君" and shield_remaining > 0 and not is_magic and source:
		
		var cryo_percent = int(18.3 + 1.8 * level)
		var cryo_duration = 2.0
		source.apply_move_pct_buff("ms_slow", cryo_duration, -cryo_percent, true)
		source.apply_attack_pct_buff("as_slow", cryo_duration, -cryo_percent, true)
	if source is Hero and source.display_name == "甄姬" and skill_id >0:
		if count_markers(source)>=3:
			clear_markers(source)
			amount += 250+0.48*source.actual_ability_power
			froze_timer = 0.75
			source.cc_duration_dealt += 0.75
		else:
			if amount >0:
				markers.append({"timer": 7,"source":source})
	# 安琪拉被动：技能命中施加灼烧标记（每层3秒，最多10层）
	if source is Hero and source.display_name == "安琪拉" and skill_id > 0:
		if count_markers(source)<10:
			markers.append({"timer": 3,"source":source})
		var angela_count = count_markers(source)
		# 每层额外法伤
		var angela_extra = 10.0 + 0.67 * source.level + source.actual_ability_power * 0.02
		amount += angela_extra * min(angela_count + 1, 10)
		# 每层获得2%移速
		source.apply_move_pct_buff("ms_haste", 3.0, 0.02 * min(angela_count + 1, 10))
	# 妲己被动：技能命中降低法抗（每层3秒，最多3层）
	if source is Hero and source.display_name == "妲己" and skill_id > 0:
		if count_markers(source) < 3:
			markers.append({"timer": 3, "source": source})
			_apply_df_buff(-36.0 - 2.4 * source.level,0,3,true)
			_recalculate_attributes()
	# 李元芳·暗印：普攻命中已带暗印的目标 → 叠1层并刷新(满4层立即引爆)
	if source is Hero and source.display_name == "李元芳" and not is_magic and skill_id == 0:
		if lyf_marks.has(source):
			lyf_add_mark(source)
	# 小乔被动：技能命中获得25%移速，持续2秒
	if source is Hero and source.display_name == "小乔" and skill_id > 0:
		source.apply_move_pct_buff("ms_haste", 2.0, 0.25)
	if source is Hero and source.display_name == "沈梦溪":
		if count_markers(source):
			var boo = 0
			if count_markers(source) >= 1:
				boo= 65+0.13*source.actual_ability_power+5*source.level
			
			if skill_id == 0:
				boo*=0.5
			amount += boo
			if count_markers(source) == 2 and skill_id == 1:
				amount *= 3
			clear_markers(source)
		
		if skill_id >0:
			markers.clear()
			markers.append({"timer": 5,"source":source})
			if source.shen_fuse_active:
				markers.append({"timer": 5,"source":source})
	# 暴击判断：普攻的掷点在出手时由攻击方判定，经子弹作为第6参(is_crit_forced>=0)传入；
	# 未携带时才用旧启发式兜底（技能/法术一律非暴击）。
	orig = source.attack if source else 0.0
	var is_crit := false
	if is_crit_forced >= 0:
		is_crit = is_crit_forced == 1
	else:
		is_crit = orig * 1.6 < amount
		if is_magic:
			is_crit = amount * 1.6 > (source.ability_power if source else 0.0)
		if skill_id != 0: is_crit = false
	# 防御塔免疫暴击（受害者侧兜底）：任何来源的暴击对塔不生效/不上报
	if self is Turret:
		is_crit = false
	
	# 伤害计算
	var resistance = magic_resist if is_magic else armor
	if source is Hero:
		resistance -= source.flat_magic_pen if is_magic else source.flat_phys_pen
		resistance = max(resistance, 0)
	resistance = resistance * (1.0 - pen_percent)
	var reduction = resistance / (resistance + 602.0)
	var actual = amount * (1.0 - reduction)
	if source is Hero and source.equipment_slots.has("sky_book"):
		var sr = actual_ability_power / 100.0 * 0.005
		actual *= (1.0 + sr)
	if self is Hero and self.equipment_slots.has("sky_book"):
		var sr = actual_ability_power / 100.0 * 0.005
		actual *= (1.0 - sr)
	# 李元芳被动·密探谛听：对非英雄单位额外造成5%物理伤害(刷野/清线小加成)
	if source is Hero and source.display_name == "李元芳" and not (self is Hero) and not is_magic:
		actual *= 1.05
	#伤害后英雄效果
	if source is Hero and source.display_name == "马可波罗":
		var threshold = 10 if self is Hero else 5
		# Check if already in defense destruction state
		var in_dd = false
		for m in markers:
			if m.get("type") == "makeboluo_dd" and m.get("source") == source:
				in_dd = true
				break
		if in_dd:
			actual += 100+int(0.35*source.bonus_attack)
		elif count_markers(source) >= threshold:
			clear_markers(source)
			markers.append({"timer": 5.0, "source": source, "type": "makeboluo_dd"})
			actual += 94+int(0.35*source.bonus_attack)+7*level
			print("马可标记"+str(94+int(0.35*source.bonus_attack)+7*level))
			source.mana = min(source.max_mana, source.mana + 30)
		else:
			markers.append({"timer": 5.0, "source": source})
		
	# 同英雄同技能0.1秒内重复伤害衰减为30%
	if source == last_attacker and skill_id == _last_skill_id and (skill_id >0 or source.display_name == "马可波罗") and (is_magic == last_type or source.display_name == "狄仁杰"):
		if bm and bm.game_time - last_hit_timer < 0.1:
			print("[ANTI_SPAM t=", "%.1f" % bm.game_time, "] ", source.display_name if source else "?", " skill=", skill_id, " dt=", "%.4f" % (bm.game_time - last_hit_timer), " raw=", amount)
			
			actual *= 0.3   # 同步衰减实际伤害（原先仅衰减原始伤害，不减少真实掉血）
	# 防短时间爆炸伤害
	last_attacker = source
	_last_skill_id = skill_id
	last_type = is_magic
	source.current_target = self
	if bm:
		last_hit_timer = bm.game_time
	# === 赛后统计：伤害跟踪 ===
	if source is Hero and self is Hero and source != self:
		source.damage_dealt_to_heroes += actual
		self.damage_taken_from_heroes += actual
	if source is Hero and self is Turret:
		source.turret_damage += actual
	# 音效：本地英雄技能命中 / 普攻暴击（内部按玩家过滤+节流）
	if actual > 0.0 and source is Hero and source != self and source.team != team:
		if is_crit and skill_id == 0:
			SfxManager.try_crit_sfx(source.display_name)
		if skill_id > 0 and (self is Hero or self is JungleMonster or self is Turret):
			SfxManager.try_skill_hit_sfx(source.display_name, is_magic)
		
	# 护盾吸收（真伤无视护盾，跳过此块；被护盾吃掉的伤害弹白字）
	if shield_remaining > 0 and not is_true_damage:
		if shield_remaining >= actual:
			shield_remaining -= actual
			_damage_feedback(actual, is_magic)
			NetSession.push_net_dmg(global_position, actual, is_crit, is_magic, true, false)
			var _ui = get_tree().get_first_node_in_group("ui") as UI_Manager
			if _ui:
				_ui.show_damage_number(global_position, actual, is_crit, is_magic, true, false)
			return
		else:
			actual = 0
			shield_remaining = 0.0
	if actual <= 0: return
	
	# === 赛后统计结束 ===
	health -= actual
	_damage_feedback(actual, is_magic)
	# 受击闪白（仅对有 rim overlay 的英雄生效；其它实体空操作）
	UnitVisuals.flash(self)
	
	# === 调试：打印英雄造成的伤害（含普攻/技能明细）===
	if source is Hero and source != self:
		var label := _skill_source_label(skill_id)
		var res_name := "MR" if _is_magic_debug else "护甲"
		var res_val := magic_resist if _is_magic_debug else armor
		# 穿甲明细：固定穿甲 + 百分比穿甲 → 实际生效抗性（与伤害计算同公式）
		var _dbg_flat_pen := (source as Hero).flat_magic_pen if _is_magic_debug else (source as Hero).flat_phys_pen
		var _dbg_pct_pen := pen_percent * 100.0
		var _dbg_eff_res = max(res_val - _dbg_flat_pen, 0.0) * (1.0 - pen_percent)
		var _dbg_pen_str := ""
		if _dbg_flat_pen > 0.0 or pen_percent > 0.0:
			_dbg_pen_str = ", 穿甲[固定%.0f+%.0f%%→生效%.1f]" % [_dbg_flat_pen, _dbg_pct_pen, _dbg_eff_res]
		var _dbg_bm4 = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		var _dbg_gt3 = _dbg_bm4.game_time if _dbg_bm4 else 0.0
		var _dbg_extra := ""
		if skill_id == 0 and source._debug_atk_info != "":
			_dbg_extra = source._debug_atk_info
			source._debug_atk_info = ""
		elif skill_id >= 1 and skill_id <= 3 and source._debug_skill_info != "":
			_dbg_extra = source._debug_skill_info
			source._debug_skill_info = ""
		print("[DAMAGE t=", "%.1f" % _dbg_gt3, "] ", source.display_name, " → ", display_name, " : raw=", str(round(_raw_amount)), " → actual=", str(round(actual)), " (", label, ", ", res_name, "=", str(round(res_val)), _dbg_pen_str, ")", _dbg_extra)

	# 数值弹出（真伤弹红字）
	NetSession.push_net_dmg(global_position, actual, is_crit, is_magic, false, is_true_damage)
	var ui = get_tree().get_first_node_in_group("ui") as UI_Manager
	if ui:
		ui.show_damage_number(global_position, actual, is_crit, is_magic, false, is_true_damage)

	# 伤后装备效果
	if source is Hero:
		# 泣血之刃：技能额外+25%物理吸血
		var bt_bonus = 0.0
		if source is Hero and source.equipment_slots.has("bloodthirster") and skill_id >= 0:
			bt_bonus = 0.25
		var heal = actual * (source.actual_magic_lifesteal if is_magic else source.actual_phys_lifesteal + bt_bonus)
		if heal > 0:
			# 治疗统一走 _apply_healing：按重伤比例削减、封顶并累计治疗量，不再这里直接改 health
			if source is Hero and source.equipment_slots.has("bloodthirster") and not is_magic:
				var before = source.health
				source._apply_healing(heal)
				# 泣血之刃：溢出治疗50%转为额外最大生命(上限400-800)
				var overheal = (before + heal) - source.actual_max_health
				if overheal > 0:
					var cap = 400 + source.level * 26
					var bonus = min(overheal * 0.5, cap)
					source.actual_max_health += bonus
					source.max_health = source.actual_max_health
					source._apply_healing(bonus)
			else:
				source._apply_healing(heal)
	

	if self == bm.hero:
		if source:
			self.damage_log.append({
				"source": source.display_name,
				"amount": actual,
				"is_magic": is_magic,
				"crit": is_crit,
				"skill_id": skill_id,
				"time": Time.get_ticks_msec() / 1000.0
			})
		var now = Time.get_ticks_msec() / 1000.0
		for i in range(self.damage_log.size() - 1, -1, -1):
			if now - self.damage_log[i].time > 7.0:
				self.damage_log.remove_at(i)

	if health <= 0:
		if is_dead:
			return
		# 复活倒计时期间禁止再次进入死亡分支（防持续伤害重复触发击杀奖励）
		if self is Hero and self.is_reviving:
			return
		source.current_target = null
		# 调试：英雄死亡分支执行日志（同一死者短时间内多次出现=击杀奖励被重复触发）
		if self is Hero and bm and bm.debug_kill_rewards:
			print("[死亡分支] t=%.1f %s hp=%.1f 来源=%s skill=%d" % [bm.game_time, display_name, health, source.display_name if source else "无", skill_id])
		if self is Turret and source:
			bm.award_tower_gold(1-team,display_name)
			# 推塔助攻：附近同队英雄全部列头像；小兵按类型各列一个（推塔才考虑小兵）
			var t_assists: Array = []
			var seen_minion: Dictionary = {}
			for e2 in get_tree().get_nodes_in_group("entities"):
				if e2 == source or not (e2 is GameEntity) or e2.team != source.team:
					continue
				if not (e2 is Hero or e2 is Minion):
					continue
				if e2.global_position.distance_to(global_position) > 12.0:
					continue
				if e2 is Hero:
					t_assists.append({"name": e2.display_name, "team": e2.team})
				elif seen_minion.size() < 3 and not seen_minion.has(e2.display_name):
					seen_minion[e2.display_name] = true
					t_assists.append({"name": e2.display_name, "team": e2.team})
			ui.show_kill_feed(source.display_name, source.team, "已摧毁", display_name, team, t_assists)
		if source is Hero:
			if self is Hero:
				if bm:
					bm.add_team_kill(source.team)
				source.on_kill(self)
				if self.red_buff_active:
					self.red_buff_active = false
					source.apply_red_buff()
				if self.blue_buff_active:
					self.blue_buff_active = false
					source.apply_blue_buff()
			# 击杀金币由 BattleManager 统一计算
				if bm:
					bm.on_hero_killed(source, self)
		else:
			if self is Hero:
				var killer = _find_nearest_enemy_hero()
				if killer and bm:
					bm.add_team_kill(killer.team)
					killer.on_kill(self)
					bm.on_hero_killed(killer, self)
				elif ui and (source is Turret or source is Minion or source is JungleMonster):
					# 环境击杀（防御塔/野怪/小兵打死英雄且无英雄记功）→“塔野杀”战报+语音
					ui.show_kill_feed(source.display_name, source.team, "击杀了", display_name, team)
		die(source)
		return

	if skill_id == -2:
		for i in range(6):
			if health<= 0:return
			if is_dead or (self is Hero and self.is_reviving):
				break
			await self.get_tree().create_timer(0.25).timeout
			health -= actual
			NetSession.push_net_dmg(global_position, actual, is_crit, is_magic)
			ui.show_damage_number(global_position, actual, is_crit, is_magic)
			if health <= 0:
				if is_dead or (self is Hero and self.is_reviving):
					break
				# 调试：DoT死亡分支执行日志（重复出现=同一DoT多次触发击杀奖励）
				if self is Hero and bm and bm.debug_kill_rewards:
					print("[死亡分支-DoT] t=%.1f %s hp=%.1f 来源=%s skill=%d" % [bm.game_time, display_name, health, source.display_name if source else "无", skill_id])
				if self is Hero:
					if bm:
						bm.add_team_kill(source.team)
					source.on_kill(self)
					if self.red_buff_active:
						self.red_buff_active = false
						source.apply_red_buff()
					if self.blue_buff_active:
						self.blue_buff_active = false
						source.apply_blue_buff()
				# 击杀金币由 BattleManager 统一计算
					if bm:
						bm.on_hero_killed(source, self)
				die(source)

# A* 寻路导航：使用 PathFinder 计算绕墙路径，返回修正后的移动方向
func _avoid_walls(move_dir: Vector3, delta: float, destination: Vector3 = Vector3.ZERO, attack_range: float = -1.0, attack_target: Vector3 = Vector3.ZERO) -> Vector3:
	if move_dir.length() < 0.01:
		return move_dir
	if not PathFinder.initialized:
		return move_dir
	# AI 被碰撞推到地图边缘（|x|/|z| ≥ 60 是 A* 实心墙格）时先夹回可行走区，
	# 否则 A* 起点在实心格，寻路反复失败/卡墙，AI 会贴边撞墙甚至绕向敌塔。
	if self is Hero and (self as Hero).is_ai:
		# 泉水在 |坐标|≥60 的地图角外；靠泉 8m 内不夹回，否则 AI 永远走不进泉池（回城后也会被夹出来）
		var spring := Vector3(-62.0, 0.0, 62.0) if int(team) == int(Config.Team.PLAYER) else Vector3(62.0, 0.0, -62.0)
		if global_position.distance_to(spring) > 8.0:
			global_position.x = clampf(global_position.x, -59.0, 59.0)
			global_position.z = clampf(global_position.z, -59.0, 59.0)
	# 卡墙检测：无目的地（玩家直控）时用位移判据；有目的地时用「沿目标方向的真实前进量」，
	# 避免 CollisionSystem 每帧推离造成的来回抖动把卡墙计时器一直骗重置。
	if destination == Vector3.ZERO:
		if _stuck_timer > 0.0 and global_position.distance_squared_to(_stuck_pos) > 0.09:
			_stuck_timer = 0.0
			_stuck_recovery_dir = Vector3.ZERO
		_stuck_pos = global_position
		_net_dist = -1.0
		_net_timer = 0.0
		_net_travel = 0.0
		_net_progress = 0.0
	else:
		if _net_dist < 0.0:
			_net_dist = global_position.distance_to(destination)
			_net_timer = 0.0
			_net_travel = 0.0
			_net_progress = 0.0
			_net_prev = global_position
		var step := global_position - _net_prev
		_net_travel += step.length()
		var to_dest := destination - global_position
		to_dest.y = 0.0
		if to_dest.length() > 0.1:
			_net_progress += step.dot(to_dest.normalized())
		_net_prev = global_position
		_net_timer += delta
		if _net_timer >= 1.2:
			var cur_d: float = global_position.distance_to(destination)
			# 距离没变近、沿目标方向也几乎没前进（贴墙来回抖）→ 真卡墙
			if _net_dist - cur_d < 0.5 and _net_progress < 0.4:
				_stuck_timer = maxf(_stuck_timer, 1.6)
				_stuck_recovery_dir = Vector3.ZERO   # 让下面立刻重新选侧向
				_stuck_recovery_t = 0.0
				_nav_path = PackedVector3Array()     # 清路径触发下一帧重算；保留 _nav_target 供指示/重算
				_nav_index = 0
			else:
				_stuck_timer = 0.0
			_net_dist = cur_d
			_net_timer = 0.0
			_net_travel = 0.0
			_net_progress = 0.0
	# 卡墙超过1.5秒：进入贴墙滑行恢复
	if _stuck_timer > 1.5 and _stuck_recovery_dir.length() < 0.01:
		# 尝试垂直于原移动方向的左右两侧
		var perp = Vector3(move_dir.z, 0, -move_dir.x).normalized()
		var space_state = get_world_3d().direct_space_state
		var origin = global_position + Vector3.UP * 0.5
		var left_query = PhysicsRayQueryParameters3D.create(origin, origin + perp * 3.0, 1)
		var right_query = PhysicsRayQueryParameters3D.create(origin, origin - perp * 3.0, 1)
		var left_hit = space_state.intersect_ray(left_query)
		var right_hit = space_state.intersect_ray(right_query)
		var left_dist = left_hit.get("position", origin + perp * 3.0).distance_to(origin) if left_hit else 3.0
		var right_dist = right_hit.get("position", origin - perp * 3.0).distance_to(origin) if right_hit else 3.0
		_stuck_recovery_dir = perp if left_dist > right_dist else -perp
	# 卡墙超过4秒：放弃，让上层逻辑重新决策
	if _stuck_timer > 4.0:
		_stuck_timer = 0.0
		_stuck_recovery_t = 0.0
		_stuck_recovery_dir = Vector3.ZERO
		_nav_path = PackedVector3Array()
		_nav_index = 0
		return Vector3.ZERO
	# 卡墙恢复模式：沿墙滑动
	if _stuck_recovery_dir.length() > 0.01:
		# 沿墙滑动方向混合原方向；滑动最多 1.0s，之后强制重算路径，避免永久进入贴墙恢复
		_stuck_recovery_t += delta
		if _stuck_recovery_t > 1.0:
			_stuck_timer = 0.0
			_stuck_recovery_t = 0.0
			_stuck_recovery_dir = Vector3.ZERO
			_nav_path = PackedVector3Array()
			_nav_index = 0
			return move_dir
		var blend = _stuck_recovery_dir * 0.7 + move_dir.normalized() * 0.3
		return blend.normalized()
	# 优先使用实际目标点（长距离寻路），否则前瞻30单位
	var desired: Vector3
	if destination != Vector3.ZERO:
		desired = destination
	else:
		desired = global_position + move_dir.normalized() * 30.0

	desired.y = 0
	# 目标偏移超过阈值时重新计算路径
	var target_moved = desired.distance_squared_to(_nav_target) > 4.0
	if target_moved or _nav_path.is_empty():
		_nav_target = desired
		# 调试：记录AI调用A*
		var _t0 := Time.get_ticks_usec()
		_nav_path = PathFinder.find_path(global_position, desired, move_dir.normalized(), team if self is Hero else -1, attack_range, attack_target)
		if debug_show_path and self is Hero and (self as Hero).is_ai:
			_astar_log_cd -= delta
			if _astar_log_cd <= 0.0:
				_astar_log_cd = 0.1
				var _ms := (Time.get_ticks_usec() - _t0) / 1000.0
				var _side := "己" if team == 0 else "敌"
				var _reason := "目标移动" if target_moved else "路径重算"
				var _atk := " [攻击]" if attack_range > 0.0 else ""
				var _nm := (self as Hero).display_name
				if _nav_path.is_empty():
					print("[A*]%s %s: (%.0f,%.0f)->(%.0f,%.0f) 失败 %s %.1fms%s 标记%d格" % [_side, _nm, global_position.x, global_position.z, desired.x, desired.z, _reason, _ms, _atk, PathFinder.last_marked_count])
				else:
					print("[A*]%s %s: (%.0f,%.0f)->(%.0f,%.0f) 路点%d 终点(%.0f,%.0f) %s %.1fms%s 标记%d格" % [_side, _nm, global_position.x, global_position.z, desired.x, desired.z, _nav_path.size(), _nav_path[_nav_path.size() - 1].x, _nav_path[_nav_path.size() - 1].z, _reason, _ms, _atk, PathFinder.last_marked_count])
		_nav_index = 0
		_update_debug_path_visual()
	# A*失败（返回空路径）：不退化为直线移动，尝试贴墙滑行
	if _nav_path.is_empty():
		_nav_target = Vector3.ZERO
		# 尝试贴墙滑行：检测左右哪侧更空旷
		var perp2 = Vector3(move_dir.z, 0, -move_dir.x).normalized()
		var space_state2 = get_world_3d().direct_space_state
		var origin2 = global_position + Vector3.UP * 0.5
		var left_query2 = PhysicsRayQueryParameters3D.create(origin2, origin2 + perp2 * 3.0, 1)
		var right_query2 = PhysicsRayQueryParameters3D.create(origin2, origin2 - perp2 * 3.0, 1)
		var left_hit2 = space_state2.intersect_ray(left_query2)
		var right_hit2 = space_state2.intersect_ray(right_query2)
		var left_dist2 = left_hit2.get("position", origin2 + perp2 * 3.0).distance_to(origin2) if left_hit2 else 3.0
		var right_dist2 = right_hit2.get("position", origin2 - perp2 * 3.0).distance_to(origin2) if right_hit2 else 3.0
		var wall_slide_dir = perp2 if left_dist2 > right_dist2 else -perp2
		return (wall_slide_dir * 0.6 + move_dir.normalized() * 0.4).normalized()
	# 路径耗尽：若距目标仍远（>5m），强制下次重算（攻击模式除外：截断路径耗尽=已到达攻击位置，重算只会得到同样的死路径）
	if _nav_index >= _nav_path.size():
		# 路径走到尽头：非攻击模式下清空旧路径，让下一帧按当前目标重新 A*；
		# 否则旧路径耗尽后会一直用 move_dir 直线走，容易撞墙/走进敌塔。
		if attack_range <= 0.0:
			_nav_path = PackedVector3Array()
			_nav_index = 0
		return move_dir
	var waypoint = _nav_path[_nav_index]
	var to_waypoint = waypoint - global_position
	to_waypoint.y = 0
	# 到达当前路点，前进到下一个
	if to_waypoint.length() < 1.5:
		_nav_index += 1
		if _nav_index >= _nav_path.size():
			# 已到达终点附近，用原方向微调
			return move_dir
		waypoint = _nav_path[_nav_index]
		to_waypoint = waypoint - global_position
		to_waypoint.y = 0
	return to_waypoint.normalized()
	# A*路径调试可视化：用折线显示当前导航路径（默认开启，F4开关）
func _update_debug_path_visual():
	# 清除旧可视化节点
	for s in _debug_path_nodes:
		if is_instance_valid(s):
			s.queue_free()
	_debug_path_nodes.clear()
	# 死亡期间不重绘（否则周期刷新会在尸体处重现旧折线/红球）
	if is_dead:
		return
	if not debug_show_path:
		return
	# 只显示AI英雄的路径
	if not (self is Hero):
		return
	if not (self as Hero).is_ai:
		return
	var parent = get_parent()
	if not parent:
		return
	var team_color = Color(0.38, 0.66, 0.70) if team == 0 else Color(0.78, 0.52, 0.34)
	# 方针：把调试「霓虹线+发光球」改成贴地的旧地图路标——低饱和队伍色混一点羊皮纸金，
	# 半透明窄带 + 终点圆环，避免亮青/亮橙在绿色地形上像 UI 叠加层。
	var path_color := team_color.lerp(Color(0.72, 0.66, 0.50), 0.45)
	path_color.a = 0.85
	# A*失败/尚未算出路径/当前路径已走到尽头（_nav_index 越界时后面的 pts 只剩起点，画不出折线）：
	# 都退化成英雄→当前导航目标的直线指示，避免完全看不到路径
	if _nav_path.is_empty() or _nav_index >= _nav_path.size():
		var _fallback_end: Vector3 = _nav_target
		if _fallback_end != Vector3.ZERO and global_position.distance_to(_fallback_end) > 1.2:
			var _fp: Array[Vector3] = [global_position + Vector3(0, DEBUG_PATH_Y, 0), _fallback_end + Vector3(0, DEBUG_PATH_Y, 0)]
			var _fmat := StandardMaterial3D.new()
			_fmat.albedo_color = path_color
			_fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_fmat.emission_enabled = true
			_fmat.emission = path_color * 0.12
			_add_path_box(parent, _fp[0], _fp[1], 0.34, _fmat)
			return
		if _fallback_end != Vector3.ZERO:
			# 已经走到目标点附近：正常到达，画终点环，不画“寻路失败”的红环
			_add_debug_end_ring(parent, _fallback_end)
			return
		# 无移动目标：脚边暗红圆环
		var fail_mesh = TorusMesh.new()
		fail_mesh.inner_radius = 0.28
		fail_mesh.outer_radius = 0.38
		fail_mesh.rings = 18
		fail_mesh.ring_segments = 12
		var fail_mat = StandardMaterial3D.new()
		fail_mat.albedo_color = Color(0.62, 0.22, 0.18, 0.62)
		fail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fail_mat.emission_enabled = true
		fail_mat.emission = Color(0.45, 0.12, 0.10)
		var fail_mi = MeshInstance3D.new()
		fail_mi.mesh = fail_mesh
		fail_mi.material_override = fail_mat
		fail_mi.position = global_position + Vector3(0, DEBUG_PATH_Y, 0)
		fail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(fail_mi)
		_debug_path_nodes.append(fail_mi)
		return
	# 贴地窄带：每个 A* 线段生成一个四边形，整体压到脚踝高度，不再悬空 0.4m
	var line_mat = StandardMaterial3D.new()
	line_mat.albedo_color = path_color
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	line_mat.emission_enabled = true
	line_mat.emission = path_color * 0.10
	var pts: Array[Vector3] = [global_position + Vector3(0, DEBUG_PATH_Y, 0)]
	for i in range(_nav_index, _nav_path.size()):
		pts.append(_nav_path[i] + Vector3(0, DEBUG_PATH_Y, 0))
	var has_segment := false
	for i in range(pts.size() - 1):
		if pts[i].distance_squared_to(pts[i + 1]) > 0.0001:
			has_segment = true
			break
	if has_segment:
		# ImmediateMesh 在部分相机/裁剪下整条 ribbon 不显示（只剩终点环），改用逐段 BoxMesh：
		# 每个线段一个薄盒子，AABB/材质/朝向都由 MeshInstance 正常计算，稳定可见。
		for i in range(pts.size() - 1):
			_add_path_box(parent, pts[i], pts[i + 1], 0.34, line_mat)
	# 终点：贴地金铜色圆环（代替高亮黄球）
	if _nav_index < _nav_path.size():
		_add_debug_end_ring(parent, _nav_path[_nav_path.size() - 1])


## 贴地终点金铜环（正常到达/路径终点共用）
func _add_debug_end_ring(parent: Node3D, pos: Vector3) -> void:
	var end_mesh := TorusMesh.new()
	end_mesh.inner_radius = 0.26
	end_mesh.outer_radius = 0.38
	end_mesh.rings = 20
	end_mesh.ring_segments = 14
	var end_mat := StandardMaterial3D.new()
	end_mat.albedo_color = Color(0.88, 0.75, 0.43, 0.78)
	end_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	end_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	end_mat.emission_enabled = true
	end_mat.emission = Color(0.46, 0.35, 0.16)
	var end_mi := MeshInstance3D.new()
	end_mi.mesh = end_mesh
	end_mi.material_override = end_mat
	end_mi.position = Vector3(pos.x, DEBUG_PATH_Y, pos.z)
	end_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(end_mi)
	_debug_path_nodes.append(end_mi)


## 单段路径薄盒：替代 ImmediateMesh ribbon（避免整条折线被裁剪/不可见）
func _add_path_box(parent: Node3D, a: Vector3, b: Vector3, width: float, mat: Material) -> void:
	var d := b - a
	d.y = 0.0
	var ln := d.length()
	if ln < 0.05:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 0.05, ln + 0.02)
	mi.mesh = bm
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	mi.rotation.y = atan2(d.x, d.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_debug_path_nodes.append(mi)


func _add_path_ribbon(imm: ImmediateMesh, a: Vector3, b: Vector3, width: float) -> bool:
	var d := b - a
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return false
	var side := Vector3(-d.z, 0.0, d.x).normalized() * (width * 0.5)
	var p0 := a - side
	var p1 := a + side
	var p2 := b + side
	var p3 := b - side
	for v in [p0, p1, p2, p0, p2, p3]:
		imm.surface_add_vertex(v)
	return true

func die(killer):
	if is_dead:
		return
	is_dead = true
	# 清理调试路径可视化节点
	for s in _debug_path_nodes:
		if is_instance_valid(s):
			s.queue_free()
	_debug_path_nodes.clear()
	# 死亡后清空A*导航状态（防止复活后沿旧路径移动）
	_nav_path = PackedVector3Array()
	_nav_index = 0
	_nav_target = Vector3.ZERO
	var bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	# 死亡视野残留：防御塔 2 秒、小兵 1 秒（单机/联机 host 共用同一份计时）
	if bm != null:
		if self is Turret:
			bm.register_dead_vision("turret", team, global_position)
		elif self is Minion:
			bm.register_dead_vision("minion", team, global_position)
	if (self is Minion or JungleMonster) :
		bm.distribute_experience(self,killer)
		bm.distribute_gold(self,killer)
		# 赛后统计：补刀数
		if killer is Hero and (self is Minion or self is JungleMonster):
			killer.last_hits += 1
	# 立即禁用实体（不再参与碰撞/移动/伤害）
	collision_layer = 0
	collision_mask = 0
	can_move = false
	_play_anim("die")
	NetSession.net_action(self, NetSession.ACT_DIE)   # 联机：死亡动作推给客户端
	emit_signal("died")
	# 等待死亡动画播放完毕再删除节点（death_delay_override>0 时用脚本指定时长，如防御塔倒塌）
	var death_time = 1.0
	if death_delay_override > 0.0:
		death_time = death_delay_override
	elif anim_player:
		if anim_player.has_animation("die"):
			death_time = anim_player.get_animation("die").length
		elif anim_player.has_animation("Death"):
			death_time = anim_player.get_animation("Death").length
	await get_tree().create_timer(death_time).timeout
	queue_free()
func _find_nearest_enemy_hero() -> Hero:
	var nearest: Hero = null
	var best_dist = 12
	for entity in get_tree().get_nodes_in_group("entities"):
		if entity is Hero and entity.team != team :
			var dist = global_position.distance_to(entity.global_position)
			if dist < best_dist:
				best_dist = dist
				nearest = entity
	return nearest

# 递归查找 AnimationPlayer 节点
func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_anim_player(child)
		if found:
			return found
	return null

# 播放动画（同一动画正在播时不重启；否则 play() 会把时间轴拉回 0，导致 walk 卡首帧）
func _play_anim(anim_name: String):
	if anim_player and anim_player.has_animation(anim_name):
		if current_anim == anim_name and anim_player.is_playing():
			return
		anim_player.play(anim_name)
		current_anim = anim_name

# 冰冻染色：遍历所有子节点，对网格应用/移除青蓝色冰冻着色
func _set_freeze_visual(node: Node, frozen: bool) -> void:
	_set_node_alpha(node, 1.0, frozen)

# 递归设置节点及其子网格的透明度和冰冻染色（用于隐身/草丛/冰冻效果）
func _set_node_alpha(node: Node, alpha: float, frozen: bool = false):
	if not node: return
	if node is MeshInstance3D:
		# 角色 rim 叠加层（UnitVisuals，material_overlay 为 ShaderMaterial）：隐身/进草时一起淡出，避免轮廓暴露
		if node.material_overlay is ShaderMaterial:
			var overlay: ShaderMaterial = node.material_overlay
			if overlay.get_shader_parameter("rim_strength") != null:
				overlay.set_shader_parameter("rim_strength", 0.0 if alpha < 0.999 else UnitVisuals.RIM_STRENGTH)
		# 接地阴影（UnitVisuals BlobShadow，material_override 为 ShaderMaterial）：隐身/进草/冰冻时隐藏
		if node.material_override is ShaderMaterial:
			if node.name == "BlobShadow":
				node.visible = alpha > 0.999 and not frozen
		elif node.material_override:
			if frozen:
				node.material_override.albedo_color = Color(0.2, 0.5, 0.95, alpha)
				node.material_override.emission_enabled = true
				node.material_override.emission = Color(0.741, 0.838, 0.986, 1.0)
				node.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			else:
				node.material_override.albedo_color = Color(1, 1, 1, alpha)
				if alpha < 0.999: node.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				node.material_override.emission_enabled = false
				node.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		elif node.mesh:
			for i in range(node.mesh.get_surface_count()):
				var mat = node.get_surface_override_material(i)
				if not mat:
					mat = node.mesh.surface_get_material(i)
				if mat and mat is StandardMaterial3D:
					mat = mat.duplicate()
					if frozen:
						mat.albedo_color = Color(0.2, 0.5, 0.95, alpha)
						mat.emission_enabled = true
						mat.emission = Color(0.741, 0.838, 0.986, 1.0)
						mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					else:
						mat.albedo_color = Color(1, 1, 1, alpha)
						if alpha < 0.999: mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.emission_enabled = false
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
					node.set_surface_override_material(i, mat)
	for child in node.get_children():
		_set_node_alpha(child, alpha, frozen)
