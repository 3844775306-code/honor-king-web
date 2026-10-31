## 昵称缓存 + AI 随机名库。
## 玩家昵称保存在 user://profile.cfg（缓存文件），下次进游戏自动读取。
class_name NameStore
extends RefCounted

const CFG_PATH := "user://profile.cfg"
const AI_FIRST := ["夜", "风", "云", "月", "星", "雪", "尘", "霜", "雷", "影", "光", "墨", "青", "白", "赤", "玄", "寒", "孤"]
const AI_SECOND := ["行者", "无声", "归客", "长歌", "问天", "逐月", "踏雪", "临渊", "听雨", "断浪", "折戟", "扶摇", "落霞", "惊鸿", "孤舟", "清欢", "流火", "照夜"]

## 读取缓存里的玩家昵称（无则空串）
static func player_name() -> String:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) != OK:
		return ""
	return str(cf.get_value("player", "name", "")).strip_edges()

## 写入缓存（空名忽略；供“取过名就记住”用）
static func save_player_name(n: String) -> void:
	var nm := n.strip_edges()
	if nm == "":
		return
	# 首次运行 user:// 目录可能尚未建立，先补建再写
	var user_dir := ProjectSettings.globalize_path("user://")
	if not DirAccess.dir_exists_absolute(user_dir):
		DirAccess.make_dir_recursive_absolute(user_dir)
	var cf := ConfigFile.new()
	cf.load(CFG_PATH)
	cf.set_value("player", "name", nm)
	cf.save(CFG_PATH)

## 随机 AI 昵称：两字组合池洗牌后取 n 个，避开 exclude（如玩家昵称）
static func random_ai_names(n: int, exclude: Array = []) -> Array:
	var pool: Array = []
	for a in AI_FIRST:
		for b in AI_SECOND:
			pool.append(str(a) + str(b))
	pool.shuffle()
	var used: Dictionary = {}
	for e in exclude:
		var es := str(e).strip_edges()
		if es != "":
			used[es] = true
	var out: Array = []
	for cand in pool:
		if out.size() >= n:
			break
		if used.has(cand):
			continue
		used[cand] = true
		out.append(cand)
	while out.size() < n:
		out.append("影卫%02d" % (out.size() + 1))
	return out
