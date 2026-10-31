class_name HeroBuildStore
extends RefCounted
## 备战方案本地存储：每个英雄最多 6 套自定义出装方案（名称 + 装备 id 列表），
## 存到 user://hero_builds.json（不可写时退回项目内 res://saves/hero_builds.json）；
## 选人页可把某套方案设为「本局推荐出装」。
## 文件结构：{ "英雄名": [ {"name": "方案名", "items": ["id1", ...]} ] }

const SAVE_PATH := "user://hero_builds.json"
const FALLBACK_PATH := "res://saves/hero_builds.json"
const MAX_SLOTS := 6
const MAX_SCHEMES := 6

static var _data: Dictionary = {}
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for p in [SAVE_PATH, FALLBACK_PATH]:
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var txt := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(txt)
		if parsed is Dictionary:
			_data = parsed
			return


static func _flush() -> void:
	var txt := JSON.stringify(_data, "\t")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(txt)
		f.close()
		return
	# 受限环境（如编辑器沙箱）user:// 不可写 → 退回项目内 saves/
	DirAccess.make_dir_recursive_absolute("res://saves")
	var f2 := FileAccess.open(FALLBACK_PATH, FileAccess.WRITE)
	if f2 != null:
		f2.store_string(txt)
		f2.close()


## 某英雄已保存的方案列表：[{ "name": String, "items": Array }]
static func get_builds(hero_name: String) -> Array:
	_ensure_loaded()
	var list: Array = _data.get(hero_name, [])
	var out: Array = []
	for b in list:
		if b is Dictionary:
			out.append({"name": str(b.get("name", "")), "items": (b.get("items", []) as Array).duplicate()})
	return out


## 保存/覆盖同名方案；返回 "" 表示成功，否则为错误提示
static func save_build(hero_name: String, build_name: String, items: Array) -> String:
	_ensure_loaded()
	var clean_name := build_name.strip_edges()
	if hero_name == "":
		return "未选择英雄"
	if clean_name == "":
		return "方案名不能为空"
	var clean_items: Array = []
	for it in items:
		var id := str(it)
		if id != "" and not clean_items.has(id):
			clean_items.append(id)
	if clean_items.is_empty():
		return "方案里还没有装备"
	if clean_items.size() > MAX_SLOTS:
		clean_items = clean_items.slice(0, MAX_SLOTS)
	var list: Array = _data.get(hero_name, [])
	var idx := -1
	for i in list.size():
		if str((list[i] as Dictionary).get("name", "")) == clean_name:
			idx = i
			break
	if idx >= 0:
		list[idx] = {"name": clean_name, "items": clean_items}
	elif list.size() >= MAX_SCHEMES:
		return "该英雄最多保存 %d 套方案" % MAX_SCHEMES
	else:
		list.append({"name": clean_name, "items": clean_items})
	_data[hero_name] = list
	_flush()
	return ""


static func delete_build(hero_name: String, build_name: String) -> void:
	_ensure_loaded()
	var list: Array = _data.get(hero_name, [])
	for i in range(list.size() - 1, -1, -1):
		if str((list[i] as Dictionary).get("name", "")) == build_name:
			list.remove_at(i)
	if list.is_empty():
		_data.erase(hero_name)
	else:
		_data[hero_name] = list
	_flush()


## 是否存在某英雄的任何方案
static func has_builds(hero_name: String) -> bool:
	return not get_builds(hero_name).is_empty()
