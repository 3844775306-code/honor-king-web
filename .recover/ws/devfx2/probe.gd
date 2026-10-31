extends Control

const MD = preload("res://scripts/ui/MinimapDraw.gd")

class DrawHost extends Control:
	func _draw() -> void:
		var md = preload("res://scripts/ui/MinimapDraw.gd")
		var types := ["outer", "inner", "high", "crystal"]
		for i in range(types.size()):
			md.draw_turret(self, Vector2(50 + i * 70, 50), 0.75, Color(0.0, 0.886, 1.0), types[i], true)
		var kinds := ["red_buff", "blue_buff", "spatial_spirit", "", "tyrant", "dragon", "storm_dragon"]
		for i in range(kinds.size()):
			md.draw_jungle(self, Vector2(50 + i * 70, 150), kinds[i], true)
			md.draw_jungle(self, Vector2(50 + i * 70, 200), kinds[i], false)
		md.draw_bush(self, Vector2(50, 260), 4.0)
		md.draw_wall(self, Vector2(120, 260), 0.6, 24.0, 4.0)
		md.draw_health_pack(self, Vector2(190, 260), true)
		md.draw_hero(self, Vector2(250, 260), Vector2(0, -1), Color(0.0, 0.886, 1.0), 0.7, true)
		md.draw_hero(self, Vector2(320, 260), Vector2(1, 0), Color(1.0, 0.33, 0.264), 0.2, false, true, 12.0)
		md.draw_dragon(self, Vector2(390, 260), Color(0.6, 0.8, 1.0), "storm")
		md.draw_elite_minion(self, Vector2(450, 260), Color(0.8, 0.8, 0.8), "super")
		md.draw_clusters(self, md.cluster([Vector2(510, 260), Vector2(512, 261), Vector2(530, 270)], 3.0), Color(0.0, 0.886, 1.0), 3.0)

var t := 0
var bm: BattleManager = null
var sv: SubViewport = null
var stats_done := false

func _ready() -> void:
	var scn: PackedScene = load("res://scenes/battle.tscn")
	if scn != null:
		add_child(scn.instantiate())
	sv = SubViewport.new()
	sv.size = Vector2i(600, 320)
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var host := DrawHost.new()
	host.size = Vector2(600, 320)
	sv.add_child(host)

func _process(_d: float) -> void:
	t += 1
	if t == 20:
		bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm != null:
			bm._start_game("亚瑟")
	elif t == 40 and not stats_done:
		stats_done = true
		var img: Image = sv.get_texture().get_image()
		if img == null:
			print("V no image")
		else:
			img.save_png("res://devfx2/draw.png")
			var names := ["outer", "inner", "high", "crystal"]
			for i in range(4):
				var cnt := 0
				var lum := 0.0
				for y in range(30, 72):
					for x in range(50 + i * 70 - 16, 50 + i * 70 + 16):
						var c := img.get_pixel(x, y)
						if c.a > 0.25:
							cnt += 1
							lum += (c.r + c.g + c.b) / 3.0
				print("V turret ", names[i], " px=", cnt, " lum=", "%.2f" % (lum / maxf(float(cnt), 1.0)))
			var jl := 0.0
			var jc := 0
			for i in range(7):
				for y in range(140, 162):
					for x in range(50 + i * 70 - 10, 50 + i * 70 + 10):
						var c2 := img.get_pixel(x, y)
						if c2.a > 0.25:
							jl += (c2.r + c2.g + c2.b) / 3.0
							jc += 1
			print("V jungle seen lum=", "%.2f" % (jl / maxf(float(jc), 1.0)), " px=", jc)
			var tex: ImageTexture = MD.terrain_texture(256, 120.0)
			print("V terrain=", tex.get_width(), "x", tex.get_height())
	elif t == 340:
		UiManager.toggle_hero_detail()
		print("V roster_visible=", UiManager.hero_detail_visible, " blocks=", UiManager.blocks_gameplay_input())
	elif t == 380:
		get_tree().quit()
