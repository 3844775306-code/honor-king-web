class_name WalkFeel
extends RefCounted
## 行走质感：给单位模型加「步频驱动」的上下起伏 + 左右摆 + 前倾，并按步点扬尘。
## 只动模型的局部 position/rotation（视觉层），不改实体位移、碰撞、朝向与战斗逻辑。
## 位移由「上一帧世界坐标差」测算，host（CharacterBody3D）与联机客户端视图节点都适用。
## dust=true 仅在 host 用（客户端不生成粒子，避免双端粒子预算翻倍）。

static func attach(unit: Node3D, model_root: Node3D, opts: Dictionary = {}) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if model_root == null or not is_instance_valid(model_root):
		return
	if unit.has_meta("_walk_feel"):
		return
	var w := Walker.new()
	w.name = "WalkFeel"
	w.setup(unit, model_root, opts)
	unit.add_child(w)
	unit.set_meta("_walk_feel", w)


class Walker extends Node:
	var unit: Node3D
	var model: Node3D
	var base_pos := Vector3.ZERO
	var base_rot := Vector3.ZERO
	var last_pos := Vector3.ZERO
	var spd := 0.0
	var phase := 0.0
	var last_step := 0
	var stride := 1.6
	var bob_amp := 0.05
	var sway_amp := 0.03
	var lean_amp := 0.07
	var dust := true
	var dust_col := Color(0.70, 0.64, 0.54)
	var dust_size := 0.22
	var step_cd := 0.0
	var _primed := false
	# 腿部枢轴（可选）：迈步时前后摆动，消除“贴地滑行”感
	var legs: Array = []
	var leg_swing := 0.55
	var leg_base: Array = []

	func setup(u: Node3D, m: Node3D, o: Dictionary) -> void:
		unit = u
		model = m
		base_pos = m.position
		base_rot = m.rotation
		last_pos = u.global_position
		stride = float(o.get("stride", 1.6))
		bob_amp = float(o.get("bob", 0.05))
		sway_amp = float(o.get("sway", 0.03))
		lean_amp = float(o.get("lean", 0.07))
		dust = bool(o.get("dust", true))
		dust_col = o.get("dust_color", Color(0.70, 0.64, 0.54))
		dust_size = float(o.get("dust_size", 0.22))
		legs = o.get("legs", [])
		leg_swing = float(o.get("leg_swing", 0.55))
		for l in legs:
			leg_base.append((l as Node3D).rotation.x)

	func _process(delta: float) -> void:
		if not is_instance_valid(unit) or not is_instance_valid(model):
			queue_free()
			return
		if not unit.is_inside_tree():
			return
		var p := unit.global_position
		if not _primed:
			_primed = true
			last_pos = p
			return
		var moved := Vector2(p.x - last_pos.x, p.z - last_pos.z).length()
		last_pos = p
		var inst := moved / maxf(delta, 0.0001)
		spd = lerpf(spd, minf(inst, 12.0), clampf(delta * 12.0, 0.0, 1.0))
		var f := clampf(spd / 3.6, 0.0, 1.3)

		# 站定：平滑归位（不硬切，避免抖）
		if spd < 0.25:
			var k := clampf(delta * 8.0, 0.0, 1.0)
			model.position = model.position.lerp(base_pos, k)
			model.rotation.x = lerpf(model.rotation.x, base_rot.x, k)
			model.rotation.z = lerpf(model.rotation.z, base_rot.z, k)
			for i in legs.size():
				var l0: Node3D = legs[i]
				if is_instance_valid(l0):
					l0.rotation.x = lerpf(l0.rotation.x, float(leg_base[i]), k)
			if last_step != 0 and dust:
				last_step = 0
				_step_dust(p, 0.6)   # 停下时补一小蓬尘
			return

		step_cd = maxf(0.0, step_cd - delta)
		# 步频：每步距离 stride → 相位推进；上下起伏 2×步频、左右摆 1×
		phase += spd / maxf(stride, 0.2) * TAU * delta
		if phase > TAU * 64.0:
			phase = fmod(phase, TAU)
		model.position.y = base_pos.y + sin(phase) * bob_amp * f
		model.rotation.z = base_rot.z + sin(phase * 0.5) * sway_amp * f
		model.rotation.x = base_rot.x + lean_amp * f
		# 双腿交替前后摆（步频驱动，幅度随速度）
		for i in legs.size():
			var lg: Node3D = legs[i]
			if not is_instance_valid(lg):
				continue
			var sgn := 1.0 if i == 0 else -1.0
			lg.rotation.x = float(leg_base[i]) + sin(phase) * leg_swing * f * sgn

		# 步点扬尘（半步一次；限频，防小兵海刷爆粒子预算）
		var step := int(phase / PI)
		if step != last_step:
			last_step = step
			if dust and step_cd <= 0.0:
				step_cd = 0.26
				_step_dust(p, f)

	func _step_dust(pos: Vector3, f: float) -> void:
		if not dust:
			return
		Vfx.footstep(pos + Vector3(0.0, 0.06, 0.0), dust_col, dust_size, clampf(f, 0.35, 1.3))
