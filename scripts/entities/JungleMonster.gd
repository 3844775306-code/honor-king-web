class_name JungleMonster
extends GameEntity
const ActorPresenter = preload("res://scripts/presentation/ActorPresenter.gd")
const MonsterMesh = preload("res://scripts/entities/MonsterMesh.gd")

var buff_type: String = ""

var respawn_time: float = 75.0

var spawn_pos: Vector3
var provoked: bool = false
var returning: bool = false
var revive_count: int = 0
var base_health:float = 0.0
var dmg_by_team: Dictionary = {}   # 史诗怪本轮次存活期间按英雄队伍累计伤害（抢龙判定）

var auto_search_timer: float = 0.0
var activity_ring: MeshInstance3D
var activity_radius: float = 4.0
var activity_ring_center: Vector3 = Vector3.ZERO   # 活动范围圈的世界圆心（营地/巢穴，固定不动）
var activity_ring_radius: float = 0.0              # 圈显示半径（0 = 用 activity_radius）
var last_player_hit_time: float = -9999.0          # 玩家英雄最近一次打这只怪的游戏时间
# 脱战回归：出活动圈 / 无目标 连续 3 秒 → 回营地中心，每秒回 20% 生命，期间不索敌
const LEASH_GRACE: float = 3.0
const LEASH_REGEN_PCT: float = 0.20
var _leash_out_timer: float = 0.0      # 连续在圈外时间
var _no_target_timer: float = 0.0      # 连续无目标时间
var _ring_center_set := false
var _ring_is_red := false
var search_radius: float = 8.0
var monster_phase: int = 0   # 史诗阶段：0普通 1暗影 2风暴（出生时盖戳）
var skill_cds: Dictionary = {}        # 技能剩余冷却 {技能名: 秒}
var windup_timer: float = 0.0         # >0 前摇中（期间不移动不攻击）
var pending_skill: Dictionary = {}    # 前摇结束要执行的技能
var wrath_pending: bool = false       # 原初轰击·怒待释放（Step5 触发）
var wrath_cd: float = 0.0             # 怒的内置CD（防集火连发）
var last_was_skill: bool = false      # 风暴龙王普攻-技能交替标记
var storm_field_timer: float = 0.0    # 雷霆领域剩余持续时间
var storm_field_tick: float = 0.0     # 领域伤害节拍
var _visual_top_cache: float = -1.0   # 史诗血条锚点缓存：视觉模型最高点相对本体的偏移(米)；-1=未测量
var _visual_root: Node3D = null        # 当前程序化视觉根节点（复活时先释放旧的，避免叠加）
var _col_shape: CollisionShape3D = null  # 碰撞形状（复活重建，避免叠加）
var _anim_root: Node3D = null            # 动画挂点（子节点）：程序化 idle/move/attack/die 只动这一个节点
var _anim_state: String = "idle"
var _anim_t: float = 0.0
var _attack_anim_t: float = -1.0
var _death_t: float = -1.0





func _ready():
	add_to_group("jungle_monsters")
	_create_visual()
	collision_layer = 1
	collision_mask = 1
	can_move = false
	spawn_pos = global_position
	# 营地圆心 = 出生点（活动圈/回营都以它为基准，不再等"玩家打它时才定格"）
	activity_ring_center = global_position
	_ring_center_set = true
	

func get_hit_flash_root() -> Node3D:
	return _visual_root if _visual_root != null and is_instance_valid(_visual_root) else self

func setup(config: Dictionary):
	super.setup(config)
	returning = false
	provoked = false
	current_target = null
	_leash_out_timer = 0.0
	_no_target_timer = 0.0
	base_health= max_health
	base_attack = attack
	# 未配置魔抗时野怪默认150（史诗龙由配置指定，不再强制覆写）
	if not config.has("magic_resist"):
		magic_resist = 150
		base_magic_resist = 150

func _create_visual():
	_visual_top_cache = -1.0   # 视觉重建 → 血条头顶锚点重新测量
	# 旧的视觉/碰撞先释放：复活重建时不能叠加（否则动画节点全指向旧模型）
	if _visual_root != null and is_instance_valid(_visual_root):
		if _visual_root.is_inside_tree():
			_visual_root.get_parent().remove_child(_visual_root)
		_visual_root.queue_free()
	if _col_shape != null and is_instance_valid(_col_shape):
		if _col_shape.is_inside_tree():
			_col_shape.get_parent().remove_child(_col_shape)
		_col_shape.queue_free()
	# 旧步态节点仍引用旧模型：先清掉，否则复活后新模型没有步态、旧节点指向已释放节点
	if has_meta("_walk_feel"):
		var old_walk = get_meta("_walk_feel")
		if is_instance_valid(old_walk):
			if old_walk.is_inside_tree():
				old_walk.get_parent().remove_child(old_walk)
			old_walk.queue_free()
		remove_meta("_walk_feel")
	# 程序化野怪模型（替代 model/monster/*.glb）：与地图石雕/石墙同族，主机与联机同源
	_visual_root = MonsterMesh.visual(display_name)
	add_child(_visual_root)
	_anim_root = _visual_root.get_node_or_null("Anim") as Node3D
	_anim_state = "idle"
	_anim_t = 0.0
	_attack_anim_t = -1.0
	_death_t = -1.0
	# 行走质感：野怪步频起伏（体型越大振幅略大）
	WalkFeel.attach(self, _visual_root, ActorPresenter.walk_opts("jungle", str(display_name), _visual_root))
	anim_player = _find_anim_player(_visual_root)
	if anim_player:
		_play_anim("idle")
	_col_shape = CollisionShape3D.new()
	_col_shape.shape = SphereShape3D.new()
	_col_shape.shape.radius = body_radius
	add_child(_col_shape)

func take_damage(amount: float, source: GameEntity = null, is_magic: bool = false,skill_id:int=0,pen: float = 0.0, is_crit_forced: int = -1):
	# 原初羁绊：击杀另一只龙的队伍对本龙伤害降低（阶段0：50%，暗影阶段：60%），
	# 并触发原初轰击·怒反击（2s内置CD；风暴龙王无羁绊）
	if source is Hero and source.team != team and display_name != "storm_dragon":
		var bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm and bm.get_bonded_team(self) == source.team:
			amount *= (0.4 if monster_phase >= 1 else 0.5)
			if wrath_cd <= 0 and not wrath_pending:
				wrath_cd = 2.0
				wrath_pending = true
	super.take_damage(amount, source, is_magic, skill_id,pen, is_crit_forced)
	# 史诗怪：累计各队英雄对龙的输出（关键抢夺判定；羁绊减伤后的实际入账值）
	if is_epic() and source is Hero:
		dmg_by_team[source.team] = dmg_by_team.get(source.team, 0.0) + amount
	if not provoked and source and source.team != team:
		provoked = true
	# 被英雄打中：立刻锁定攻击者反击（不受搜索半径限制），并取消「回营」状态
	# 原逻辑只有 provoked=true，目标要靠 0.5s 一次的 _find_target 在 search_radius(8m) 内找，
	# 且追击到 activity_radius(普通营地 4m) 就脱战回营 → 远程英雄在 6~7.5m 打野时野怪永远够不到、也不追
	if source is Hero and source.team != team and source.health > 0 and source.collision_layer != 0 \
		and global_position.distance_to(source.global_position) <= _leash_radius() + 4.0:
		provoked = true
		returning = false
		current_target = source
		auto_search_timer = 0.0
	# 记录"玩家英雄最近一次打这只怪"的时间：活动圈只在这个时间窗内显示
	if source is Hero and source.team == Config.Team.PLAYER:
		var bm_p = get_tree().get_first_node_in_group("battle_manager")
		if bm_p != null and bm_p.hero == source:
			last_player_hit_time = float(bm_p.game_time)

# 野怪动画名映射（攻击→eat）
func _play_anim(anim_name: String):
	# 联机：野怪攻击动作推给客户端（闸门：仅 HOST 且附近有己方英雄）
	if anim_name == "attack-melee-left":
		NetSession.net_action(self, 0)
	# 程序化模型没有骨骼动画：驱动自制的状态机（idle/move/attack/die）
	if anim_player == null:
		_set_anim_clip(anim_name)
		return
	# 暴君/主宰（旧 GLB 分支保留兼容）
	if display_name in ["tyrant", "dragon", "shadow_tyrant", "shadow_dragon", "storm_dragon"]:
		match anim_name:
			"idle": super._play_anim("CharacterArmature|Flying_Idle")
			"walk": super._play_anim("CharacterArmature|Flying_Idle")
			"attack-melee-left": super._play_anim("CharacterArmature|Punch")
			"die": super._play_anim("CharacterArmature|Death")
			_: super._play_anim(anim_name)
		return
	match anim_name:
		"attack-melee-left": super._play_anim("eat")
		_: super._play_anim(anim_name)

# 动画名 → 程序化状态
func _set_anim_clip(anim_name: String):
	match anim_name:
		"attack-melee-left", "attack", "attack-melee-right":
			if _anim_state != "die":
				_anim_state = "attack"
				_attack_anim_t = 0.0
		"walk", "run", "move":
			if _anim_state == "die":
				return
			if _anim_state == "attack" and _attack_anim_t >= 0.0 and _attack_anim_t < 0.42:
				return
			_anim_state = "move"
		"die", "death":
			if _anim_state != "die":
				_anim_state = "die"
				_death_t = 0.0
		"idle", _:
			if _anim_state == "die":
				return
			if _anim_state == "attack" and _attack_anim_t >= 0.0 and _attack_anim_t < 0.42:
				return
			_anim_state = "idle"

# 程序化动画：只动 _anim_root（外层 root 由 WalkFeel 负责步态起伏，互不冲突）
func _update_anim(delta: float) -> void:
	if _anim_root == null or not is_instance_valid(_anim_root):
		return
	_anim_t += delta
	var ar: Node3D = _anim_root
	match _anim_state:
		"move":
			var ph: float = _anim_t * 9.0
			ar.position = Vector3(0.0, absf(sin(ph)) * 0.06, 0.0)
			ar.rotation = Vector3(-0.05, 0.0, sin(ph) * 0.06)
			ar.scale = Vector3.ONE
		"attack":
			_attack_anim_t += delta
			var pa: float = clampf(_attack_anim_t / 0.42, 0.0, 1.0)
			var ka: float = sin(pa * PI)
			ar.position = Vector3(0.0, 0.0, ka * 0.30)
			ar.rotation = Vector3(-ka * 0.28, 0.0, 0.0)
			ar.scale = Vector3(1.0 + 0.08 * ka, 1.0 - 0.10 * ka, 1.0 + 0.14 * ka)
			if pa >= 1.0:
				_anim_state = "idle"
				_attack_anim_t = -1.0
		"die":
			_death_t += delta
			var pd: float = clampf(_death_t / 0.85, 0.0, 1.0)
			var ed: float = 1.0 - pow(1.0 - pd, 3.0)
			ar.position = Vector3(0.0, -ed * 0.18, ed * 0.10)
			ar.rotation = Vector3(ed * 1.35, 0.0, ed * 0.25)
			ar.scale = Vector3(1.0 + 0.12 * ed, 1.0 - 0.25 * ed, 1.0 + 0.12 * ed)
			if pd >= 1.0 and visible:
				visible = false
		_:
			var pi: float = _anim_t * 2.2
			ar.position = Vector3(0.0, sin(pi) * 0.022, 0.0)
			ar.rotation = Vector3(sin(pi * 0.7) * 0.02, 0.0, 0.0)
			ar.scale = Vector3.ONE

func _process(delta: float) -> void:
	super._process(delta)
	_update_anim(delta)
	_update_activity_ring()


## 活动范围圈：只在「玩家英雄正在攻击这只野怪」时显示；
## 圈固定在营地（不随怪移动），怪走出圈外时变红，否则白色
func _update_activity_ring() -> void:
	if activity_ring == null or not is_instance_valid(activity_ring):
		return
	var show := false
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm != null and bm.hero != null and is_instance_valid(bm.hero):
		var ph = bm.hero
		# 只有"玩家正在攻击这只野怪"才显示：目标是它 + 最近 2 秒内确实挨过玩家的打
		#（仅靠 current_target 会残留：打一下后走开/脱战，圈还挂在那里）
		var recent_hit: bool = float(bm.game_time) - last_player_hit_time <= 2.0
		if health > 0.0 and ph.health > 0.0 and recent_hit and (ph.current_target == self or ph.manual_target == self):
			show = true
	if activity_ring.visible != show:
		activity_ring.visible = show
	if not show:
		return
	if not _ring_center_set:
		activity_ring_center = global_position
		_ring_center_set = true
	if activity_ring_radius <= 0.0:
		activity_ring_radius = maxf(activity_radius, 1.0)
	# 圈贴回固定圆心（圈设为 top_level，自身世界坐标不受怪移动/转向影响）
	activity_ring.global_position = Vector3(activity_ring_center.x,
		activity_ring_center.y + 0.17, activity_ring_center.z)
	# 走出圈外 → 红；仍在圈内 → 白
	var out := global_position.distance_to(activity_ring_center) > activity_ring_radius
	if out != _ring_is_red:
		_ring_is_red = out
		MeshFactory.set_ground_ring_color(activity_ring,
			Color(1.0, 0.22, 0.18, 0.55) if out else Color(1.0, 1.0, 1.0, 0.42))


func _physics_process(delta):
	if is_dead or health <= 0: return
	# 空间之灵：主动攻击正在传送的敌方英雄（召唤师传送/大禹传送）
	if display_name == "spatial_spirit":
		_try_aggro_teleporting_hero()
	# 硬控期间禁止一切行动
	if froze_timer>0 or knockup_timer>0 or stun_timer>0 or suppress_timer>0:return
	if attack_timer > 0:
		attack_timer -= delta

	# 技能冷却递减
	for k in skill_cds.keys():
		skill_cds[k] -= delta
		if skill_cds[k] <= 0:
			skill_cds.erase(k)
	if wrath_cd > 0:
		wrath_cd -= delta

	# 原初轰击·怒（被动，最高优先级，瞬发）
	_try_wrath()

	# 雷霆领域：持续多段法术伤害
	if storm_field_timer > 0:
		storm_field_timer -= delta
		storm_field_tick -= delta
		if storm_field_tick <= 0:
			storm_field_tick = 0.5
			_aoe_damage(global_position, 5.0, attack * 0.8, true, {"skill_id": -60})

	# 前摇阶段：不移动不攻击
	if windup_timer > 0:
		windup_timer -= delta
		if windup_timer <= 0:
			_finish_cast()
		return

	# —— 脱战计时：连续 3 秒出活动圈 或 连续 3 秒无目标 → 回营地中心回血 ——
	var camp := _camp_center()
	var has_target: bool = current_target != null and is_instance_valid(current_target) and current_target.health > 0
	if global_position.distance_to(camp) > _camp_radius():
		_leash_out_timer += delta
	else:
		_leash_out_timer = 0.0
	if has_target:
		_no_target_timer = 0.0
	else:
		_no_target_timer += delta
	if not returning:
		var go_home: bool = _leash_out_timer >= LEASH_GRACE
		if not go_home and _no_target_timer >= LEASH_GRACE and global_position.distance_to(camp) > 1.0:
			go_home = true
		if go_home:
			returning = true
			provoked = false
			current_target = null

	# 搜索敌人（仅当被激怒且未回营；回营途中不再主动找目标）
	if provoked and not returning:
		auto_search_timer -= delta
		if auto_search_timer <= 0:
			auto_search_timer = 0.5
			if current_target == null or not is_instance_valid(current_target) or current_target.health <= 0:
				_find_target()

	# 回营途中：走向营地中心 + 每秒 20% 最大生命回血，不攻击不索敌
	if returning:
		_apply_healing(max_health * LEASH_REGEN_PCT * delta)
		var back: Vector3 = camp - global_position
		if back.length() < 0.6:
			returning = false
			provoked = false
			current_target = null
			_leash_out_timer = 0.0
			_no_target_timer = 0.0
			global_position = camp
			_play_anim("idle")
		else:
			var bdir := _avoid_walls(back.normalized(), delta, camp)
			global_position += bdir.normalized() * maxf(_chase_speed_m(), 1.0) * delta
			rotation.y = atan2(bdir.x, bdir.z)
			_play_anim("walk")
		return

	# 处理当前目标
	if has_target:
		var dist_to_target = global_position.distance_to(current_target.global_position)
		if dist_to_target <= attack_range*0.01:
			# 够得到就先打
			if attack_timer <= 0:
				_perform_attack()
		else:
			# 向目标移动
			var dir = (current_target.global_position - global_position).normalized()
			dir = _avoid_walls(dir, delta, current_target.global_position)
			global_position += dir * _chase_speed_m() * delta
			rotation.y = atan2(dir.x, dir.z)
			_play_anim("walk")
	else:
		current_target = null
		_play_anim("idle")


# ==================== 史诗龙技能系统 ====================

# 各龙技能表（按优先级排列，先可用先放）
func _get_skill_table() -> Array:
	match display_name:
		"tyrant":
			return [
				{"name": "breath", "type": "breath", "cd": 5.0, "windup": 0.4, "dmg_mult": 1.5, "slow_dur": 2.0, "slow_per": 0.3},
			]
		"dragon":
			return [
				{"name": "slam", "type": "aoe", "cd": 6.0, "windup": 0.4, "dmg_mult": 2.5, "radius": 3.2, "knockup": 0.75},
			]
		"shadow_tyrant":
			return [
				{"name": "shadow_burst", "type": "ring", "cd": 8.0, "windup": 0.5, "dmg_mult": 2.0, "radius": 6.0, "knockback": true},
				{"name": "shadow_breath", "type": "breath", "cd": 5.0, "windup": 0.5, "dmg_mult": 1.5, "slow_dur": 2.5, "slow_per": 0.4},
			]
		"shadow_dragon":
			return [
				{"name": "dragon_slam", "type": "aoe", "cd": 6.0, "windup": 0.5, "dmg_mult": 2.5, "radius": 3.2, "knockup": 1.0},
				{"name": "dragon_roar", "type": "ring", "cd": 9.0, "windup": 0.5, "dmg_mult": 2.0, "radius": 7.0, "knockback": true},
			]
		"storm_dragon":
			return [
				{"name": "storm_slam", "type": "aoe", "cd": 7.0, "windup": 0.5, "dmg_mult": 2.5, "radius": 3.5, "knockup": 1.0},
				{"name": "storm_field", "type": "field", "cd": 10.0, "windup": 0.5},
			]
	return []


# 选择一个可用的技能（CD 已好）
func _pick_skill() -> Dictionary:
	for sk in _get_skill_table():
		if skill_cds.get(sk["name"], 0.0) <= 0:
			return sk
	return {}


# 出手决策：风暴龙王严格 普攻-技能 交替；其余龙技能好了就放
func _perform_attack():
	if not is_instance_valid(current_target) or current_target.health <= 0:
		return
	var is_storm = display_name == "storm_dragon"
	if not is_storm or not last_was_skill:
		var sk = _pick_skill()
		if not sk.is_empty():
			last_was_skill = true
			_start_cast(sk)
			return
	last_was_skill = false
	_do_melee_attack()


# 普攻前摇（暗影/风暴阶段0.5s），随后 _finish_cast 执行 "aa"
func _do_melee_attack():
	attack_timer = 1.0 / attack_speed
	if monster_phase >= 1:
		windup_timer = 0.5
		pending_skill = {"type": "aa"}
	else:
		_melee_hit()


# 普攻实际伤害（各龙不同的AOE形态）
func _melee_hit():
	if not is_instance_valid(current_target) or current_target.health <= 0:
		return
	_play_anim("attack-melee-left")
	# 动物攻击音（猪/鸟/虫/狼/蜥蜴/猴/红蓝buff/暴君/主宰/龙王各不同）
	SfxManager.try_jungle_attack_sfx(display_name, global_position)
	if display_name in ["tyrant", "shadow_tyrant"]:
		# 爪击：主目标全额 + 300码溅射30%
		current_target.take_damage(attack, self, false, -60, 0)
		_melee_fx(current_target, 1.2)
		_splash_hit(3.0, attack * 0.3, false, {})
	elif display_name == "storm_dragon":
		# 雷霆爪击：前方扇形AOE
		current_target.take_damage(attack, self, false, -60, 0)
		_melee_fx(current_target, 1.2)
		var facing = (current_target.global_position - global_position).normalized()
		for entity in get_tree().get_nodes_in_group("entities"):
			if entity == self or entity == current_target or entity.health <= 0: continue
			if not (entity is Hero or entity is Minion): continue
			if entity.team == team: continue
			var to_ent = (entity.global_position - global_position).normalized()
			if facing.dot(to_ent) < 0.7: continue   # 约45°扇形
			if global_position.distance_to(entity.global_position) - entity.body_radius <= 3.5:
				entity.take_damage(attack, self, false, -60, 0)
				_melee_fx(entity, 1.0)
	else:
		# 巨爪挥击：主目标 + 320码全向AOE
		current_target.take_damage(attack, self, false, -60, 0)
		_melee_fx(current_target, 1.4)
		_splash_hit(3.2, attack, false, {})


# 野怪普攻命中特效（爪击尘土 + 火花，受击方按类型区分）
func _melee_fx(t: GameEntity, sf: float) -> void:
	if t == null or not is_instance_valid(t):
		return
	var tk := "hero"
	if t is Minion:
		tk = "minion"
	elif t is Turret:
		tk = "crystal" if t.display_name == "crystal" else "tower"
	elif t is JungleMonster:
		tk = "monster"
	Vfx.hit_impact(t.global_position + Vector3.UP * 0.6, (t.global_position - global_position).normalized(),
		Color(0.82, 0.66, 0.36), Color(1.0, 0.9, 0.65), sf, tk, "monster")


# 半径内其他敌方英雄/小兵溅射伤害（不含主目标）
func _splash_hit(radius: float, dmg: float, is_magic: bool, opts: Dictionary):
	for entity in get_tree().get_nodes_in_group("entities"):
		if entity == self or entity == current_target or entity.health <= 0: continue
		if not (entity is Hero or entity is Minion): continue
		if entity.team == team: continue
		if global_position.distance_to(entity.global_position) - entity.body_radius <= radius:
			entity.take_damage(dmg, self, is_magic, opts.get("skill_id", -60), 0)


# 施法前摇
func _start_cast(skill: Dictionary):
	windup_timer = skill.get("windup", 0.4)
	pending_skill = skill
	skill_cds[skill["name"]] = skill.get("cd", 5.0)


# 前摇结束：执行技能
func _finish_cast():
	var sk = pending_skill
	pending_skill = {}
	if sk.is_empty():
		return
	if sk.get("type", "") == "aa":
		_melee_hit()
		return
	if not is_instance_valid(current_target) or current_target.health <= 0:
		return   # 目标丢失，技能作废
	match sk.get("type", ""):
		"aoe":
			_aoe_damage(current_target.global_position, sk.get("radius", 3.2), attack * sk.get("dmg_mult", 2.5), sk.get("is_magic", false), sk)
		"ring":
			_aoe_damage(global_position, sk.get("radius", 6.0), attack * sk.get("dmg_mult", 2.0), true, sk)
		"breath":
			var bullet = LinearBullet.new()
			bullet.speed = 15.0
			bullet.damage = attack * sk.get("dmg_mult", 1.5)
			bullet.team = team
			bullet.source = self
			bullet.is_magic = true
			bullet.direction = (current_target.global_position - global_position).normalized()
			bullet.max_distance = 12.0
			bullet.slow_dur = sk.get("slow_dur", 0.0)
			bullet.slow_per = sk.get("slow_per", 0.0)
			bullet.global_position = global_position + Vector3(0, 1.0, 0)
			get_parent().add_child(bullet)
		"field":
			storm_field_timer = 5.0
			storm_field_tick = 0.0
	_play_anim("attack-melee-left")


# 圆形/环形AOE原语：命中范围内敌方英雄与小兵（排除防御塔）
func _aoe_damage(center: Vector3, radius: float, dmg: float, is_magic: bool, opts: Dictionary):
	for entity in get_tree().get_nodes_in_group("entities"):
		if entity == self or entity.health <= 0: continue
		if not (entity is Hero or entity is Minion): continue
		if entity.team == team: continue
		if center.distance_to(entity.global_position) - entity.body_radius > radius: continue
		entity.take_damage(dmg, self, is_magic, opts.get("skill_id", -60), 0)
		if opts.get("knockup", 0) > 0 and entity is Hero:
			entity.knockup_timer = max(entity.knockup_timer, opts["knockup"])
		if opts.get("slow_dur", 0) > 0:
			entity.apply_move_pct_buff("ms_slow", opts["slow_dur"], -opts["slow_per"], true)
		if opts.get("knockback", false):
			var dir = (entity.global_position - center).normalized()
			entity.global_position += dir * 2.5
		if opts.get("debuff", false):
			# 进阶原初轰击：降15%输出3秒
			entity._apply_ak_buff(0, -0.15, 3, false)
			entity._apply_ak_buff(0, -0.15, 3, true)


# 原初轰击·怒（被动：被羁绊者攻击时触发，Step5 设置 wrath_pending）
func _try_wrath():
	if not wrath_pending:
		return
	wrath_pending = false
	wrath_cd = 2.0
	var radius = 8.5 if monster_phase >= 1 else 6.5
	var opts := {"skill_id": -61}
	if monster_phase >= 1:
		opts["debuff"] = true
		# 自身 +20% 双抗 3秒
		_apply_df_buff(0, 0.2, 3, false)
		_apply_df_buff(0, 0.2, 3, true)
	_aoe_damage(global_position, radius, attack * 3.0, true, opts)
	var bm = get_tree().get_first_node_in_group("battle_manager")
	var t = bm.game_time if bm else 0.0
	print("[WRATH] t=%.0f %s 原初轰击·怒 radius=%.1f dmg=%.0f" % [t, display_name, radius, attack * 3.0])



# 脱战上限：被攻击后会追出营地反击，超过该距离才脱战回营
# 普通营地：活动半径 4m → 追击上限 9m（够到 750~825 射程的远程英雄）；史诗龙：8m → 13m
func _leash_radius() -> float:
	return maxf(activity_radius + 5.0, search_radius)


# 营地中心（活动圈圆心）/ 活动圈半径：回营用
func _camp_center() -> Vector3:
	return activity_ring_center if _ring_center_set else spawn_pos


func _camp_radius() -> float:
	# 活动圈半径：优先用正在显示的那个圈，否则用营地配置半径
	if activity_ring_radius > 0.0:
		return activity_ring_radius
	return maxf(activity_radius, 1.0)


# 追击移速（m/s）：营地配置没给 move_speed（=0），旧逻辑写死 1.0 m/s，追人太慢形同不还手
func _chase_speed_m() -> float:
	return maxf(move_speed, 300.0) * 0.01


# 空间之灵：传送中的英雄会被它主动锁定，不再等被攻击后才反击。
# 只在自身脱战追击范围内生效；传送结束后目标仍会按普通仇恨继续追击/攻击。
func _try_aggro_teleporting_hero() -> void:
	if is_dead or health <= 0:
		return
	var best: Hero = null
	var best_dist: float = _leash_radius()
	for h in get_tree().get_nodes_in_group("heroes"):
		if not (h is Hero) or h.team == team or h.health <= 0:
			continue
		if h.collision_layer == 0 or h.is_invisible_to_enemy() or h.is_untargetable_by_enemies():
			continue
		if not (h.is_teleporting or h.dayu_teleport_channeling):
			continue
		var dist: float = global_position.distance_to(h.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = h
	if best == null:
		return
	provoked = true
	returning = false
	current_target = best
	auto_search_timer = 0.0
	_leash_out_timer = 0.0
	_no_target_timer = 0.0


func _find_target():
	var best: GameEntity = null
	var best_dist = _leash_radius()
	for entity in get_tree().get_nodes_in_group("entities"):
		if entity == self or entity.health <= 0: continue
		if entity.team == team: continue
		if entity.collision_layer == 0: continue  # 隐身不可锁定
		if entity is Hero and (entity as Hero).is_invisible_to_enemy(): continue  # 兰陵王隐身(保留碰撞)但不可锁定
		if entity is Hero:
			var dist = global_position.distance_to(entity.global_position)
			if dist < best_dist:
				best_dist = dist
				best = entity
	current_target = best

func die(killer):
	if is_dead:
		return
	is_dead = true
	collision_layer = 0
	# 程序化死亡动画：倒地/塌陷 0.85s 后由 _update_anim 收尾隐藏
	_set_anim_clip("die")
	var bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager

	bm.distribute_experience(self,killer)
	bm.distribute_gold(self,killer)
	# 击杀者回退链：无效/友方 → 最后攻击者 → 最近敌方英雄 → null
	if not is_instance_valid(killer) or not killer is Hero or killer.team == team:
		killer = null
		if is_instance_valid(last_attacker) and last_attacker is Hero and last_attacker.team != team:
			killer = last_attacker
	if not is_instance_valid(killer):
		killer = _find_nearest_enemy_hero()

	# 史诗怪物（暴君/主宰/风暴龙王）：统一交给 BattleManager 处理并立即移除
	if is_epic():
		bm.on_epic_died(self, killer)
		# 死亡动画播完再移除（否则龙一死就瞬间消失）
		await get_tree().create_timer(0.85).timeout
		queue_free()
		return

	if killer is Hero:
		if buff_type == "red": killer.apply_red_buff()
		elif buff_type == "blue": killer.apply_blue_buff()
	# 空间之灵：击杀 → 全队平分50金币 + 开启传送阵（持续到10分钟）
	if display_name == "spatial_spirit":
		if killer is Hero:
			bm.grant_team_split_reward(killer.team, 50)
		bm.open_spatial_teleport(global_position)
		# 4分钟后不再刷新：本次死亡时间 + 刷新间隔 已越过 4:00 → 不再复活
		if bm.game_time + respawn_time > 240.0:
			queue_free()
			return
	# 河道之灵：仅首刷（30秒），死亡后不再复活
	if display_name == "river_spirit":
		queue_free()
		return
	await get_tree().create_timer(respawn_time).timeout
	if is_instance_valid(self):
		revive_count += 1
		_respawn()

func is_epic() -> bool:
	return display_name in ["tyrant", "dragon", "shadow_tyrant", "shadow_dragon", "storm_dragon"]

# 史诗龙血条锚点：应显示在模型头顶上方，而非身体正中央。
# 动态测量视觉模型最高点；无模型/普通野怪时退回旧锚点 半径*2+1
func bar_anchor_height() -> float:
	if not is_epic():
		return body_radius * 2.0 + 1.0
	if _visual_top_cache < 0.0:
		var world_top := _max_mesh_top_y(self)
		_visual_top_cache = (world_top - global_position.y + 1.0) if world_top > -1e9 else (body_radius * 2.0 + 1.0)
	return _visual_top_cache

# 遍历本节点子树，取所有可见网格最高顶点的世界Y（已含实例/祖先的缩放与朝向）
func _max_mesh_top_y(node: Node) -> float:
	var best := -INF
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		var aabb := gi.get_aabb()
		if aabb.size.y > 0.001:
			for k in 8:
				best = maxf(best, (gi.global_transform * aabb.get_endpoint(k)).y)
	for child in node.get_children():
		best = maxf(best, _max_mesh_top_y(child))
	return best

func _respawn():
	is_dead = false
	visible = true
	collision_layer = 1
	health = max_health
	_anim_state = "idle"
	_death_t = -1.0
	_attack_anim_t = -1.0
	current_target = null
	returning = false
	provoked = false
	# 每次复活属性增强 20%
	var bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	var bonus = min(int(bm.game_time / 60.0),15)
	max_health = base_health+int(base_health * 0.2*bonus)
	attack = base_attack+int(base_attack * 0.2*bonus)
	health = max_health
	body_radius = body_radius * 1   # 体积略微变大
	_create_visual()   # 重建视觉以匹配新半径
	global_position = spawn_pos

func _find_nearest_enemy_hero() -> Hero:
	var nearest: Hero = null
	var best_dist = 100.0
	for entity in get_tree().get_nodes_in_group("entities"):
		if entity is Hero and entity.team != team and entity.health > 0:
			var dist = global_position.distance_to(entity.global_position)
			if dist < best_dist:
				best_dist = dist
				nearest = entity
	return nearest
