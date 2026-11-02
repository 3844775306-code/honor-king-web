extends RefCounted
## 灵宝本地存档：好感度 / 配色 / 名字（user://lingbao.cfg，纯本地不上传）

static func _path() -> String:
	return UserScope.path("lingbao.cfg")
const PATH_DEV := "res://lingbao.cfg"   # user:// 不可写时（沙箱/只读环境）退到工程目录
const COLORS := [
	Color(0.62, 0.86, 1.00),   # 冰蓝
	Color(1.00, 0.78, 0.86),   # 樱粉
	Color(0.78, 1.00, 0.82),   # 薄荷
	Color(1.00, 0.90, 0.62),   # 暖金
	Color(0.86, 0.78, 1.00),   # 紫罗兰
]
const NAME_DEFAULT := "小灵"


static func _load() -> ConfigFile:
	var cf := ConfigFile.new()
	if cf.load(_path()) != OK:
		cf = ConfigFile.new()   # 账号隔离：不再读 res:// 旧兜底，避免新账号继承工程内旧数据
	return cf


static func _save(cf: ConfigFile) -> void:
	if cf.save(_path()) == OK:
		CloudSync.schedule_push()
		return
	cf.save(PATH_DEV)
	CloudSync.schedule_push()


static func name() -> String:
	var n := str(_load().get_value("lingbao", "name", NAME_DEFAULT)).strip_edges()
	return n if n != "" else NAME_DEFAULT


static func set_name(n: String) -> void:
	var cf := _load()
	cf.set_value("lingbao", "name", n.strip_edges())
	_save(cf)


static func affection() -> int:
	return maxi(0, int(_load().get_value("lingbao", "affection", 0)))


static func add_affection(n: int) -> int:
	var cf := _load()
	var v := maxi(0, int(cf.get_value("lingbao", "affection", 0)) + n)
	cf.set_value("lingbao", "affection", v)
	_save(cf)
	return v


static func level() -> int:
	return clampi(1 + affection() / 20, 1, 99)


static func color_index() -> int:
	return int(_load().get_value("lingbao", "color", 0)) % COLORS.size()


static func color() -> Color:
	return COLORS[color_index()]


static func cycle_color() -> int:
	var cf := _load()
	var i := (int(cf.get_value("lingbao", "color", 0)) + 1) % COLORS.size()
	cf.set_value("lingbao", "color", i)
	_save(cf)
	return i



