extends Node
var f := 0
func _ready() -> void:
	add_child(load("res://scenes/battle.tscn").instantiate())
func _process(_delta: float) -> void:
	f += 1
	if f == 30:
		var a := CanvasLayer.new(); a.layer = 2
		var r1 := ColorRect.new(); r1.color = Color(0,1,0,1); r1.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(a); a.add_child(r1)
		var b := CanvasLayer.new(); b.layer = 50
		var r2 := ColorRect.new(); r2.color = Color(0,0,1,1); r2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(b); b.add_child(r2)
		print("[RECTS] added layer2 green + layer50 blue")
	if f == 180:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://_shot_rects.png")
		get_tree().quit()
