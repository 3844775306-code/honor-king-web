extends Node3D
## 临时：验证施法预览着色器能否在真实渲染器编译，并落一张调试图。

func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 14, 14), Vector3.ZERO)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.055, 0.065, 0.085)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.65)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	var r := MeshFactory.create_cast_range(Color(0.32, 0.72, 1.0))
	r.position = Vector3(-6, 0.06, 0)
	r.scale = Vector3(4.0, 1.0, 4.0)
	add_child(r)
	var a := MeshFactory.create_cast_area(Color(0.30, 0.72, 1.0), 0)
	a.position = Vector3(0, 0.06, -4)
	a.scale = Vector3(3.0, 1.0, 3.0)
	add_child(a)
	var t := MeshFactory.create_cast_area(Color(0.36, 0.80, 1.0), 1)
	t.position = Vector3(5, 0.06, -4)
	t.scale = Vector3(2.0, 1.0, 2.0)
	add_child(t)
	var l := MeshFactory.create_cast_line(Color(0.30, 0.72, 1.0))
	l.position = Vector3(0, 0.06, 4)
	l.scale = Vector3(0.9, 1.0, 9.0)
	add_child(l)
	var ret := MeshFactory.create_cast_reticle(Color(0.36, 0.80, 1.0))
	ret.position = Vector3(0, 0.06, 13)
	add_child(ret)

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://scripts/dev/_cast_preview_test.png")
	get_tree().quit()
