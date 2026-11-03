class_name Minion
extends GameEntity

const ActorPresenter = preload("res://scripts/presentation/ActorPresenter.gd")
const NetModels = preload("res://scripts/net/NetModels.gd")   # 兵线体型归一化常量（与客户端共用）
const MinionModelScript = preload("res://scripts/entities/MinionModel.gd")

var waypoints: Array = []
var waypoint_index: int = 0
var line: int = 0
var auto_search_timer: float = 0.0
var minion_type: String = "melee"
var visual: Node3D = null   # 模型实例（攻城车等无骨骼动画的兵种靠程序化后坐表现攻击）
var _proc_visual: bool = false
var _ammo_node: MeshInstance3D = null   # 模型上膛的箭（弓兵/攻城车）：射击瞬间隐藏、装填后恢复
var _death_anim_started: bool = false
var _wp_idx_cached: int = -1      # 路点到达半径缓存（塔位路点会被塔基推挤，半径需放宽）
var _wp_reach: float = 1.0
var net_attack_seq: int = 0       # 普攻视觉序号：录像按序号变化补播攻击动作
var teleport_channel_protected := false   # 被选为传送落点：传送引导期间不攻击/不移动/免伤

func _ready():
	add_to_group("minions")
	
	_create_visual()
	collision_layer = 1
	collision_mask = 1
	can_move = true
	vision_range = 8.0
	#print(line)

func _create_visual():
	# 已确认的兵种用程序化甲士模型；龙形先锋仍走旧 GLB（待确认后切 is_applied）
	if MinionModelScript.is_applied(display_name):
		var instance: Node3D = MinionModelScript.build(display_name, team)
		add_child(instance)
		visual = instance
		_proc_visual = true
		_ammo_node = instance.get_node_or_null("ModelPivot/Ammo") as MeshInstance3D
		# 程序化模型：阵营色/金属度已合并进 2 个材质并烘焙到顶点色，跳过逐面材质染色
		WalkFeel.attach(self, instance, _walk_opts())
	else:
		# 根据兵种加载对应模型
		var model_map = {
			"melee":  "res://model/melee/soldier.glb",
			"ranged": "res://model/range/archer.glb",
			"siege":  "res://model/seige/cannon-mobile.glb",
			"super":  "res://model/super/character-orc.glb",
			"dragon": "res://model/dragon/DragonBaby.glb",
			"storm": "res://model/dragon/DragonBaby.glb",
			"shadow_dragon": "res://model/dragon/DragonBaby.glb",
		}
		var path = model_map.get(display_name, "")
		if path != "":
			var model = load(path)
			if model:
				var instance = model.instantiate()
				# 体型归一化：缩放由「目标高度/原始高度」算出，与客户端同一套常量
				var sc: float = NetModels.minion_scale(display_name)
				instance.scale = Vector3(sc, sc, sc)
				add_child(instance)
				visual = instance
				# 队伍色染模型（继承模型材质的贴图/明暗，只做色相偏移）
				UnitVisuals.tint_team(instance, team)
				# 行走质感：小兵步频起伏 + 轻微摆动（去尘量小、限频）
				WalkFeel.attach(self, instance, _walk_opts())
				anim_player = _find_anim_player(instance)
				if anim_player:
					_play_anim("idle")
	if not has_node("CollisionShape3D"):
		var col = CollisionShape3D.new()
		col.shape = SphereShape3D.new()
		# 暗影先锋视觉模型1.5倍缩放，碰撞半径同步放大
		col.shape.radius = body_radius * 1.5 if display_name == "shadow_dragon" else body_radius
		add_child(col)


# 弹道出膛点（世界坐标）：兵种模型自身的箭尖 / 弩口 / 龙嘴，随模型缩放与朝向走
func _attack_muzzle() -> Vector3:
	var local: Vector3 = MinionModelScript.muzzle_local(display_name)
	if visual != null and is_instance_valid(visual):
		var pivot: Node3D = visual.get_node_or_null("ModelPivot")
		var base: Node3D = pivot if pivot != null else visual
		return base.global_transform * local
	return global_position + Vector3(0, 1.2, 0)


func get_hit_flash_root() -> Node3D:
	return visual if visual != null and is_instance_valid(visual) else self

# 血条锚点：跟随放大后的模型高度（模型2倍，碰撞半径保持不变）
func bar_anchor_height() -> float:
	var model_h := MinionModelScript.target_height(display_name) * MinionModelScript.VISUAL_SCALE + 0.3
	return maxf(body_radius * 2.0 + 1.0, model_h)

# 行走质感按体型调整：龙兵双翼扇动 + 更大起伏
func _walk_opts() -> Dictionary:
	# 三端共享行走参数（ActorPresenter）：甲士双腿摆动 / 攻城车低起伏 / 龙兵扇翼，host 与联机/回放同源
	return ActorPresenter.walk_opts("minion", display_name, visual)

func _model_lunge() -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var pivot: Node3D = visual.get_node_or_null("ModelPivot")
	if pivot == null:
		return
	var old: Tween = pivot.get_meta("atk_tween", null)
	if old != null and old.is_valid():
		old.kill()
	# 兵种手感：远程拉弓后弹射、超级兵重砸、龙兵俯冲冲撞、近战兵刺击
	var p := {"back": 0.12, "fwd": 0.36, "up": 0.18, "down": 0.18, "twist": 0.26, "dip": 0.05,
		"windup": 0.09, "strike": 0.10, "settle": 0.30}
	if display_name == "ranged":
		p = {"back": 0.17, "fwd": 0.09, "up": 0.11, "down": 0.12, "twist": 0.15, "dip": 0.04,
			"windup": 0.13, "strike": 0.07, "settle": 0.26}
	elif display_name == "super":
		p = {"back": 0.19, "fwd": 0.52, "up": 0.32, "down": 0.36, "twist": 0.46, "dip": 0.11,
			"windup": 0.13, "strike": 0.12, "settle": 0.36}
	elif display_name in ["dragon", "storm", "shadow_dragon"]:
		p = {"back": 0.13, "fwd": 0.38, "up": 0.12, "down": 0.24, "twist": 0.0, "dip": 0.06,
			"windup": 0.10, "strike": 0.12, "settle": 0.30}
	var base_pos := pivot.position
	var base_rot := pivot.rotation
	var base_scl := pivot.scale
	# 个体差异：每个兵的攻击节奏/幅度略有不同，整排兵同帧出手也不会像复制粘贴
	var seed_v: int = absi(get_instance_id() % 89)
	var rnd: float = float(seed_v) / 89.0
	var side_dir: float = 1.0 if (seed_v % 2 == 0) else -1.0
	var back: float = float(p.back) * (0.85 + 0.30 * rnd)
	var fwd: float = float(p.fwd) * (0.90 + 0.20 * rnd)
	var up: float = float(p.up) * (0.85 + 0.30 * rnd)
	var down: float = float(p.down) * (0.85 + 0.30 * rnd)
	var twist: float = float(p.twist) * (0.80 + 0.40 * rnd)
	var dip: float = float(p.dip) * (0.85 + 0.30 * rnd)
	var windup: float = float(p.windup) * (0.85 + 0.30 * rnd)
	var strike: float = float(p.strike) * (0.85 + 0.30 * rnd)
	var settle: float = float(p.settle) * (0.90 + 0.20 * rnd)
	# 横向挥砍 + 身体侧倾：近战/超级兵是「砍」不是「戳」，远程/龙兵只做轻微摆动
	var swing: float = 0.0
	var roll: float = 0.0
	if display_name in ["melee", "super"]:
		var heavy: float = 1.6 if display_name == "super" else 1.0
		swing = (0.16 + 0.12 * rnd) * side_dir * heavy
		roll = (0.10 + 0.08 * rnd) * side_dir * heavy
	elif display_name in ["dragon", "storm", "shadow_dragon"]:
		swing = 0.06 * side_dir
	var hop: float = up * 0.22 if display_name in ["melee", "super"] else 0.0
	var tw := create_tween()
	pivot.set_meta("atk_tween", tw)
	# 1) 蓄力：重心后坐、上身抬起、反向拧腰 + 纵向压扁（挤压感）
	tw.tween_property(pivot, "position:z", base_pos.z - back, windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "rotation:x", base_rot.x + up, windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "rotation:y", base_rot.y + twist, windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "position:x", base_pos.x - swing * 0.45, windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "rotation:z", base_rot.z + roll * 0.4, windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "position:y", base_pos.y - dip * 0.35, windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "scale", Vector3(base_scl.x * 1.05, base_scl.y * 0.93, base_scl.z * 1.05), windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 2) 出手：前冲 + 横砍 + 压身 + 顺向拧腰（TRANS_BACK 过冲），拉伸变形 + 轻微腾空
	tw.tween_property(pivot, "position:z", base_pos.z + fwd, strike).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "position:x", base_pos.x + swing, strike).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "position:y", base_pos.y - dip + hop, strike).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(pivot, "rotation:x", base_rot.x - down, strike).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(pivot, "rotation:y", base_rot.y - twist * 1.5, strike).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(pivot, "rotation:z", base_rot.z - roll, strike).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(pivot, "scale", Vector3(base_scl.x * 0.94, base_scl.y * 1.10, base_scl.z * 0.94), strike).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 3) 收势：先回到前冲一半再缓落（避免直线弹回），带一点反向过冲
	tw.tween_property(pivot, "position:z", base_pos.z + fwd * 0.25, settle * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(pivot, "position:x", base_pos.x + swing * 0.3, settle * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "rotation:x", base_rot.x + up * 0.2, settle * 0.45)
	tw.parallel().tween_property(pivot, "scale", Vector3(base_scl.x * 1.02, base_scl.y * 0.97, base_scl.z * 1.02), settle * 0.45)
	tw.tween_property(pivot, "position:z", base_pos.z, settle * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "position:x", base_pos.x, settle * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "position:y", base_pos.y, settle * 0.55)
	tw.parallel().tween_property(pivot, "rotation:x", base_rot.x, settle * 0.55)
	tw.parallel().tween_property(pivot, "rotation:y", base_rot.y, settle * 0.55)
	tw.parallel().tween_property(pivot, "rotation:z", base_rot.z, settle * 0.55)
	tw.parallel().tween_property(pivot, "scale", base_scl, settle * 0.55)

# 本地英雄附近才生成刀光（远处小兵不占特效预算）
func _near_local_hero(radius: float) -> bool:
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm == null or bm.hero == null or not is_instance_valid(bm.hero):
		return false
	return global_position.distance_to(bm.hero.global_position) <= radius


# 无骨骼模型死亡：停掉行走起伏，侧倒/坠地
func _proc_death() -> void:
	if not _proc_visual or visual == null or not is_instance_valid(visual) or _death_anim_started:
		return
	_death_anim_started = true
	var walker := get_node_or_null("WalkFeel")
	if walker:
		walker.set_process(false)
	var base := visual.position
	var tw := create_tween()
	tw.set_parallel(true)
	if display_name in ["dragon", "storm", "shadow_dragon"]:
		tw.tween_property(visual, "rotation:x", 0.55, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(visual, "position:y", base.y - 0.55, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		var dir := 1.0 if (get_instance_id() % 2 == 0) else -1.0
		tw.tween_property(visual, "rotation:z", dir * 1.35, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(visual, "position:y", base.y - 0.12, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# 为特定兵种映射动画名称（主宰先锋使用 DragonBaby 模型的动画名）
func _play_anim(anim_name: String):
	# 联机：小兵攻击动作推给客户端（非 HOST 由 net_action 直接忽略；
	# 「附近有己方英雄」的闸门在 NetSession.push_net_action 里，不会刷远端小兵战）
	if anim_name == "attack-melee-left":
		net_attack_seq += 1
		NetSession.net_action(self, 0)
	if display_name in ["dragon", "storm", "shadow_dragon"]:
		match anim_name:
			"idle": super._play_anim("CharacterArmature|Flying_Idle")
			"walk": super._play_anim("CharacterArmature|Flying_Idle")
			"attack-melee-left": super._play_anim("CharacterArmature|Punch")
			"die": super._play_anim("CharacterArmature|Death")
			_: super._play_anim(anim_name)
	else:
		super._play_anim(anim_name)

# 攻城车开炮后坐：模型沿本地 -Z 后坐再回位 + 炮口闪光（该模型没有 AnimationPlayer）
func _siege_recoil() -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var recoil_node: Node3D = visual.get_node_or_null("ModelPivot")
	var dist := 0.45
	if recoil_node != null:
		dist = 0.20
	else:
		recoil_node = visual
	var base := recoil_node.position
	var base_rot := recoil_node.rotation
	var tw := create_tween()
	# 后坐 + 炮口上跳（0.06s 打出后坐，0.28s 缓慢回位）
	tw.tween_property(recoil_node, "position:z", base.z - dist, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(recoil_node, "rotation:x", base_rot.x - 0.075, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(recoil_node, "position:z", base.z, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(recoil_node, "rotation:x", base_rot.x, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	var fwd := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	# 出膛瞬间：炮口焰 + 火光球（弩箭同时由 _fire_ammo 从模型上隐藏）
	Vfx.muzzle(_attack_muzzle(), fwd, Color(1.0, 0.72, 0.35), Color(1.0, 0.95, 0.8))
	Vfx.cast_glow(_attack_muzzle() + fwd * 0.22, Color(1.0, 0.55, 0.2), 0.65, 0.2)

# 箭已离弦：隐藏模型上膛的箭（弓兵/攻城车共用），按射击间隔装填后重新出现
func _fire_ammo() -> void:
	if _ammo_node == null or not is_instance_valid(_ammo_node):
		return
	_ammo_node.visible = false
	var interval: float = 1.0 / maxf(attack_speed, 0.15)
	var reload: float = clampf(interval * 0.75, 0.3, 1.8)
	var t := get_tree().create_timer(reload)
	t.timeout.connect(func() -> void:
		if is_instance_valid(_ammo_node) and health > 0.0:
			_ammo_node.visible = true)

## 传送锚点状态：被选中的小兵在引导期间站定、停手并免疫伤害
func set_teleport_channel_protected(on: bool) -> void:
	if teleport_channel_protected == on:
		return
	teleport_channel_protected = on
	# 同时关闭碰撞推挤，否则其他单位仍能把它挤离落点
	can_move = not on
	if on:
		current_target = null
		attack_timer = 0.0
		velocity = Vector3.ZERO
		_play_anim("idle")


func _physics_process(delta):
	if health <= 0: return
	if teleport_channel_protected:
		current_target = null
		velocity = Vector3.ZERO
		return
	# 攻击冷却
	if attack_timer > 0:
		attack_timer -= delta
	if froze_timer>0:return
	# 每0.5秒搜索敌人
	auto_search_timer -= delta
	if current_target:
		
		var dist = global_position.distance_to(current_target.global_position) 
		if current_target.health <=0 or dist > vision_range:
			current_target = null
	if auto_search_timer <= 0 and not current_target:
		auto_search_timer = 0.5
		_find_target()

	# 如果有目标且在视野内，追击或攻击
	if current_target and is_instance_valid(current_target) and current_target.health > 0:
		var dist = global_position.distance_to(current_target.global_position) 
		# 塔基半径 3.2：以塔基边缘判定攻击距离（塔基是障碍，否则近战兵永远够不到塔心）
		var reach: float = attack_range*0.01 + (3.2 if current_target is Turret else 0.0)
		if dist <= reach:
			# 进入攻击范围：始终面向目标（近战/远程/攻城车一致，不再只朝移动方向）
			var to_t: Vector3 = current_target.global_position - global_position
			rotation.y = lerp_angle(rotation.y, atan2(to_t.x, to_t.z), clampf(delta * 10.0, 0.0, 1.0))
			# 攻击范围内 → 攻击，停止移动
			if attack_timer <= 0:
				var _tgt_pos: Vector3 = current_target.global_position
				if attack_range*0.01 > 1.0:
					var bullet = Bullet.new()
					bullet.speed = 10.0
					bullet.damage = attack
					if display_name in ["dragon", "storm"]:
						bullet.damage_range = 2.0
						bullet.scale = Vector3(3.0, 3.0, 3.0)
					elif display_name == "shadow_dragon":
						bullet.damage_range = 2.5
						bullet.scale = Vector3(3.5, 3.5, 3.5)
					bullet.team = team
					bullet.target = current_target
					bullet.source = self
					bullet.global_position = _attack_muzzle()
					get_parent().add_child(bullet)
					_fire_ammo()   # 箭已离弦：藏起模型上膛的箭，装填后恢复
				else:
					var tp := current_target.global_position   # 先取坐标：这一击可能击杀目标，之后 current_target 变 null
					rotation.y = atan2((tp - global_position).normalized().x, (tp - global_position).normalized().z)
					var _mtgt := current_target
					current_target.take_damage(attack, self)
					# 近战兵/超级兵命中特效（远程兵/攻城车走 Bullet.on_hit）
					var _tk := "hero"
					if _mtgt is Minion:
						_tk = "minion"
					elif _mtgt is Turret:
						_tk = "crystal" if _mtgt.display_name == "crystal" else "tower"
					elif _mtgt is JungleMonster:
						_tk = "monster"
					Vfx.hit_impact(tp + Vector3.UP * 0.6, (tp - global_position).normalized(),
						Vfx.team_color(team), Color(1.0, 0.95, 0.85), 0.6 if display_name != "super" else 0.85, _tk, "minion")
				anim_atk_seq += 1
				attack_timer = 1.0 / attack_speed
				# 兵种攻击音（近战/远程/炮车/超级兵/龙兵各不同，仅本地英雄附近）
				SfxManager.try_minion_attack_sfx(display_name, global_position)
				_play_anim("attack-melee-left")
				if display_name == "siege":
					_siege_recoil()   # 攻城车模型无骨骼动画 → 程序化开炮后坐
				elif _proc_visual:
					_model_lunge()    # 程序化甲士模型无骨骼动画 → 普攻前刺
					if display_name in ["melee", "super"] and _near_local_hero(20.0):
						var swing_from: Vector3 = global_position + Vector3.UP * (0.85 if display_name == "melee" else 1.25)
						var side_off: Vector3 = to_t.normalized().rotated(Vector3.UP, 0.6) * (0.5 if display_name == "melee" else 0.9)
						Vfx.weapon_hit(swing_from - side_off, _tgt_pos + Vector3.UP * (0.55 if display_name == "melee" else 0.9), Vfx.team_color(team), Color(1.0, 0.96, 0.86), 0.9 if display_name == "melee" else 1.45)
			# 停步
			return
		elif ( _is_on_lane_or_high_ground(current_target.global_position)):

			# 在视野内但攻击范围外 → 向目标移动
			var dir = (current_target.global_position - global_position).normalized()
			dir = _avoid_walls(dir, delta, current_target.global_position)
			global_position += dir * move_speed * delta*0.01
			rotation.y = atan2(dir.x, dir.z)
			_play_anim("walk")
			# 边界格（世界坐标 |v| >= 60）是实心墙：留 1m 余量，站进实心格会让 A* 起点变成墙体而卡死
			var half = Config.MAP_SIZE / 2.0 - 1.0
			
			global_position.x = clamp(global_position.x, -half, half)
			global_position.z = clamp(global_position.z, -half, half)
			return
		else:
			current_target = null
	else:
		current_target = null
		

	# 无有效目标 → 沿路点移动
	if waypoint_index < waypoints.size():
		var target_pos = waypoints[waypoint_index]
		# 塔位路点：塔基会把单位推开，永远站不到路点中心 → 放宽到达半径，避免绕塔打转
		if waypoint_index != _wp_idx_cached:
			_wp_idx_cached = waypoint_index
			_wp_reach = 1.0
			for tu in get_tree().get_nodes_in_group("turrets"):
				if is_instance_valid(tu) and tu.global_position.distance_to(target_pos) < 3.4:
					_wp_reach = 3.4
					break
			if _wp_reach <= 1.0:
				for st in get_tree().get_nodes_in_group("tower_stumps"):
					if is_instance_valid(st) and st.global_position.distance_to(target_pos) < 3.4:
						_wp_reach = 3.4
						break
		var dir = (target_pos - global_position).normalized()
		dir = _avoid_walls(dir, delta, target_pos)
		global_position += dir * move_speed*0.01 * delta
		rotation.y = atan2(dir.x, dir.z)
		_play_anim("walk")
		if global_position.distance_to(target_pos) < _wp_reach:
			waypoint_index += 1
	# 边界格（世界坐标 |v| >= 60）是实心墙：留 1m 余量，站进实心格会让 A* 起点变成墙体而卡死
	var half = Config.MAP_SIZE / 2.0 - 1.0
	global_position.x = clamp(global_position.x, -half, half)
	global_position.z = clamp(global_position.z, -half, half)
	


## 拆塔中小兵被敌方小兵攻击：重新做一次「最近目标」搜索；若防御塔仍最近则继续打塔
func _retarget_on_minion_hit() -> void:
	current_target = null
	_find_target()


func _find_target():
	var best: GameEntity = null
	var best_dist = vision_range
	for entity in get_tree().get_nodes_in_group("entities"):
		if entity == self or entity.health <= 0: continue
		if entity is JungleMonster:continue
		if entity is Tripod: continue   # 小兵不会主动攻击大禹的鼎
		if entity.collision_layer == 0: continue  # 隐身不可锁定
		if entity is Hero and entity.hidden_in_bush: continue
		if entity is Hero and entity.wd_timer>0:continue
		if entity is Hero and (entity as Hero).is_invisible_to_enemy(): continue  # 兰陵王隐身(保留碰撞)但不可锁定
		if entity is Hero and not _is_on_lane_or_high_ground(entity.global_position): continue
		if entity.team == team: continue
		var dist = global_position.distance_to(entity.global_position) 
		if dist < best_dist:
			best_dist = dist
			best = entity
	current_target = best

func _is_on_lane_or_high_ground(pos: Vector3) -> bool:
	# 轴对齐分路平面
	if pos.x >= -63 and pos.x <= -47 and pos.z >= -40 and pos.z <= 40: return true
	if pos.x >= 47 and pos.x <= 63 and pos.z >= -40 and pos.z <= 40: return true
	if pos.x >= -40 and pos.x <= 40 and pos.z >= 47 and pos.z <= 63: return true
	if pos.x >= -40 and pos.x <= 40 and pos.z >= -63 and pos.z <= -47: return true
	# 中路（旋转-45度）— 将点反向旋转+45度后再判断
	var mid_centers = [Vector3(-30, 0, 30), Vector3(30, 0, -30)]
	for mc in mid_centers:
		var local = pos - mc
		var angle = deg_to_rad(45)
		var rx = local.x * cos(angle) - local.z * sin(angle)
		var rz = local.x * sin(angle) + local.z * cos(angle)
		if rx >= -40 and rx <= 40 and rz >= -8 and rz <= 8: return true
	# 高地扇形（以地图顶点为圆心）
	var high_centers = [Vector3(-60, 0, 60), Vector3(60, 0, -60)]
	var high_radius = 35.0
	for hc in high_centers:
		var dx = pos.x - hc.x; var dz = pos.z - hc.z
		if dx * dx + dz * dz > high_radius * high_radius: continue
		var ang = rad_to_deg(atan2(dz, dx))
		if hc.x < 0:
			if ang >= -90 and ang <= 0: return true
		else:
			if ang >= 90 and ang <= 180: return true
	# 河道（对角线 z = -x，宽度 ~20，|x+z| ≤ 15）abs(wx - wz) / sqrt(2.0)
	if abs(pos.x - pos.z) <= 15.0:
		return true
	return false

func take_damage(amount: float, source: GameEntity = null, is_magic: bool = false,skill_id:int=0,pen: float = 0.0, is_crit_forced: int = -1):
	# 传送锚点引导期间免疫一切伤害（含真伤/塔伤/AoE）
	if teleport_channel_protected:
		return
	if source:
		if source is Minion:
			# 正在拆塔的小兵被敌方小兵攻击：重新锁定最近的敌方小兵（主宰先锋除外）
			if current_target is Turret and is_instance_valid(source) and source.team != team \
					and source.health > 0.0 and display_name not in ["dragon", "storm", "shadow_dragon"]:
				_retarget_on_minion_hit()
			amount*= 1.25
			if source.display_name == "super" or source.display_name == "siege":
				amount *= 1.2
			if source.display_name == "dragon":
				amount *= 1.6
		super.take_damage(amount, source, is_magic,skill_id,pen, is_crit_forced) 

func die(killer):
	# 主宰先锋/风暴先锋/暗影先锋被击杀：本地玩家附近才响（敌我音色不同）
	if not is_dead and display_name in ["dragon", "storm", "shadow_dragon"]:
		SfxManager.try_vanguard_down_sfx(team, global_position)
	if not is_dead:
		_proc_death()
		_start_sink_away()
	super.die(killer)


# 倒地后缓缓沉入地面再消失（不再是一落地就被 queue_free 掉）
func _start_sink_away() -> void:
	var depth: float = 2.4 if display_name in ["dragon", "storm", "shadow_dragon"] else 1.5
	var fall: float = 0.62
	var sink: float = 0.88
	# 延长节点存活时间到「倒地 + 下沉」结束之后
	death_delay_override = fall + sink + 0.06
	var tw := create_tween()
	tw.tween_interval(fall)
	tw.tween_property(self, "position:y", global_position.y - depth, sink) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
