class_name CrystalFinale
extends Node

const DecorMeshScript = preload("res://scripts/entities/DecorMesh.gd")
## 终章水晶爆炸（单机 / 联机客户端 / 回放共用这一份实现，保证三端动画完全一致）。
## 用法：
##   var fx := CrystalFinale.new()
##   host.add_child(fx)
##   fx.on_shake = _camera_shake   # 可选：外部镜头震动（联机/回放用自己的相机）
##   fx.on_flash = _screen_flash   # 可选：外部全屏闪光
##   fx.play(crystal_world_pos, won)
## 序列：蓄能圈/打光 → 碎石喷发 + 双层冲击波 → 4 次递增余爆 → 终章大爆（约 4.6 秒）。

var on_shake: Callable = Callable()
var on_flash: Callable = Callable()


func play(pos: Vector3, won: bool) -> void:
	var root := Node3D.new()
	root.name = "EndCrystalFX"
	root.position = pos
	add_child(root)
	var core: Color = Color(1.0, 0.93, 0.62) if won else Color(0.65, 0.88, 1.0)
	var warm: Color = Color(1.0, 0.98, 0.88) if won else Color(1.0, 0.72, 0.30)
	# 碎石粒子（延迟到光柱打出后才喷）
	var debris := CPUParticles3D.new()
	debris.amount = 90
	debris.one_shot = true
	debris.explosiveness = 1.0
	debris.lifetime = 3.4
	debris.position = Vector3(0, 1.4, 0)
	debris.direction = Vector3.UP
	debris.spread = 180.0
	debris.initial_velocity_min = 4.0
	debris.initial_velocity_max = 17.0
	debris.gravity = Vector3(0, -14, 0)
	debris.scale_amount_min = 0.7
	debris.scale_amount_max = 2.6
	debris.angular_velocity_min = -220.0
	debris.angular_velocity_max = 220.0
	var rock := BoxMesh.new()
	rock.size = Vector3(0.6, 0.6, 0.6)
	debris.mesh = rock
	debris.material_override = DecorMeshScript.rock_material()
	debris.emitting = false
	root.add_child(debris)
	# 地面焦痕（压在水晶青砖之上）
	var scorch := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 6.4
	cyl.bottom_radius = 6.8
	cyl.height = 0.02
	cyl.radial_segments = 48
	scorch.mesh = cyl
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.06, 0.05, 0.05)
	sm.roughness = 1.0
	scorch.material_override = sm
	scorch.position.y = 0.215
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(scorch)

	var tw := root.create_tween()
	# 注意：水晶本身的光柱与零件爆裂由 Turret.play_collapse 的水晶分支在 t≈0.1~0.3s 完成，
	# 这里只负责「镜头聚焦后的余爆与终章」，不重复打光束/碎片，避免两次光柱叠在一起。
	# 1) 蓄能：地面收束环 + 中心亮起来
	tw.tween_callback(func() -> void:
		Vfx.shockwave(pos + Vector3(0, 0.22, 0), 6.0, core, 0.5)
		Vfx._light(pos + Vector3(0, 2.0, 0), core, 6.0, 0.35)
		_shake(0.28, 0.45)
		_flash(Color(1.0, 0.97, 0.9), 0.14))
	# 2) 水晶炸开后的碎石与冲击环
	tw.tween_interval(1.05)
	tw.tween_callback(func() -> void:
		debris.emitting = true
		Vfx.shockwave(pos + Vector3(0, 0.3, 0), 12.0, core, 0.8)
		Vfx.shockwave(pos + Vector3(0, 0.25, 0), 7.5, warm, 0.6)
		Vfx.hit_spark(pos + Vector3(0, 2.0, 0), warm, Vector3.UP, 3.0)
		_shake(0.5, 0.4))
	# 3) 余爆：4 次递增（不再每 0.5s 抖一下，节奏更自然）
	for i in range(4):
		var k: float = float(i + 1) / 4.0
		tw.tween_interval(0.52)
		tw.tween_callback(func() -> void: _burst(pos, 0.35 + 0.65 * k, core, warm))
	# 4) 终章大爆
	tw.tween_interval(0.65)
	tw.tween_callback(func() -> void: _final_blast(pos, core, warm))
	tw.tween_callback(func() -> void: root.queue_free())


func _burst(pos: Vector3, k: float, core: Color, warm: Color) -> void:
	var q: Vector3 = pos + Vector3(randf_range(-1.6, 1.6), randf_range(0.6, 3.2), randf_range(-1.6, 1.6))
	Vfx.shockwave(pos + Vector3(0, 0.25, 0), lerpf(3.0, 13.0, k), core.lerp(warm, k), 0.55)
	Vfx.hit_spark(q, warm, Vector3.UP, 1.2 + 2.4 * k)
	Vfx._light(q, core, 3.0 + 5.0 * k, 0.55)
	_shake(0.10 + 0.45 * k, 0.24)


func _final_blast(pos: Vector3, core: Color, warm: Color) -> void:
	_flash(Color(1.0, 0.96, 0.88), 0.55)
	Vfx.shockwave(pos + Vector3(0, 0.3, 0), 26.0, Color(1.0, 0.86, 0.55), 1.0)
	Vfx.shockwave(pos + Vector3(0, 0.2, 0), 16.0, core, 0.8)
	Vfx.pillar(pos, Color(1.0, 0.92, 0.75), 4.2, 30.0, 1.2)
	_shake(0.85, 1.0)
	Vfx._light(pos + Vector3(0, 3.0, 0), Color(1.0, 0.9, 0.7), 18.0, 1.4)


func _shake(amp: float, dur: float) -> void:
	if on_shake.is_valid():
		on_shake.call(amp, dur)
	else:
		Vfx.camera_shake(amp, dur)


func _flash(col: Color, dur: float) -> void:
	if on_flash.is_valid():
		on_flash.call(col, dur)
	else:
		Vfx.screen_flash(col, dur)

