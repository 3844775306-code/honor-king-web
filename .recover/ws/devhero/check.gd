extends Control
const HeroArt = preload("res://scripts/ui/HeroArt.gd")
var done := false
func _draw() -> void:
	var names: Array = HeroArt.MOTIF.keys()
	for i in range(names.size()):
		var x := 60.0 + (i % 6) * 130.0
		var y := 60.0 + (i / 6) * 130.0
		HeroArt.draw_portrait(self, Vector2(x, y), 54.0, str(names[i]), Color(0.3, 0.8, 1.0), false)
		HeroArt.draw_portrait(self, Vector2(x, y + 260.0), 22.0, str(names[i]), Color(1.0, 0.4, 0.3), i % 3 == 0)
		UiKit.text(self, Vector2(x - 40, y + 82), str(names[i]), 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 80.0)
	print("H heroes=", names.size(), " missing=", _missing(names))
	print("H fallback=", HeroArt.accent_of("不存在的英雄") != null)
	print("H done")
	done = true
func _missing(names: Array) -> Array:
	var cfg := preload("res://scripts/core/BattleManager.gd").new()
	var out: Array = []
	for k in cfg.hero_configs.keys():
		if not names.has(k):
			out.append(k)
	cfg.free()
	return out
func _process(_d: float) -> void:
	if done: get_tree().quit()
