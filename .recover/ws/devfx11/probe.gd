extends Node

var t := 0
var bm: BattleManager = null
var tur: Turret = null
var dummy: Minion = null
var cam: Camera3D = null
var img_off: Image = null
var a2 := Vector2.ZERO
var b2 := Vector2.ZERO

func _ready() -> void:
	add_child((load("res://scenes/battle.tscn") as PackedScene).instantiate())

func _process(_d: float) -> void:
	t += 1
	if t == 20:
		bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm != null:
			bm._start_game("亚瑟")
	elif t == 320:
		tur = bm.turrets[0] as Turret
		dummy = Minion.new()
		dummy.setup({"name": "melee", "team": 1, "max_health": 9999999, "attack": 1})
		dummy.position = tur.position + Vector3(4.0, 0.0, 0.0)
		dummy.can_move = false
		add_child(dummy)
		tur.current_target = dummy
	elif t == 335:
		cam = Camera3D.new()
		cam.fov = 60.0
		add_child(cam)
		cam.global_position = tur.global_position + Vector3(0.0, 7.0, 11.0)
		cam.look_at(tur.global_position + Vector3(2.0, 3.0, 0.0), Vector3.UP)
		cam.make_current()
	elif t == 360:
		(tur.get("_lock_beam") as Node3D).visible = false
	elif t == 364:
		img_off = get_viewport().get_texture().get_image()
	elif t == 366:
		(tur.get("_lock_beam") as Node3D).visible = true
	elif t == 370:
		a2 = cam.unproject_position(tur.global_position + Vector3(0, 2, 0))
		b2 = cam.unproject_position(dummy.global_position + Vector3(0, 1, 0))
		var img_on := get_viewport().get_texture().get_image()
		print("P img=", img_on.get_width(), "x", img_on.get_height(), " a=", a2, " b=", b2)
		var seg: Vector2 = b2 - a2
		var seg_len: float = seg.length()
		var dir: Vector2 = seg / maxf(seg_len, 0.001)
		var mask := 0
		var diff := 0
		var off_line := 0
		var maxd := 0.0
		var x0: int = int(maxf(0, minf(a2.x, b2.x) - 12))
		var x1: int = int(minf(img_on.get_width() - 1, maxf(a2.x, b2.x) + 12))
		var y0: int = int(maxf(0, minf(a2.y, b2.y) - 12))
		var y1: int = int(minf(img_on.get_height() - 1, maxf(a2.y, b2.y) + 12))
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var pt := Vector2(x + 0.5, y + 0.5)
				var rel: Vector2 = pt - a2
				var proj: float = clampf(rel.dot(dir), 0.0, seg_len)
				var dist: float = rel.distance_to(dir * proj)
				if dist > 6.0:
					continue
				mask += 1
				var c1: Color = img_off.get_pixel(x, y)
				var c2: Color = img_on.get_pixel(x, y)
				var dd: float = absf(c1.r - c2.r) + absf(c1.g - c2.g) + absf(c1.b - c2.b)
				maxd = maxf(maxd, dd)
				if dd > 0.10:
					diff += 1
					if dist > 3.0:
						off_line += 1
		print("P mask=", mask, " diff=", diff, " off_line=", off_line, " maxdiff=", "%.2f" % maxd)
		img_on.save_png("res://devfx11/on.png")
		img_off.save_png("res://devfx11/off.png")
		get_tree().quit()
