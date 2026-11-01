class_name AIDebugFormat
extends RefCounted
## AI 思考过程文本格式化（单机 F3 覆盖层 / 回放 F3 覆盖层共用）

static func hero(s: Dictionary) -> String:
	if s == null or s.is_empty():
		return ""
	var lines: Array = []
	var name := str(s.get("name", "?"))
	var role := str(s.get("role", ""))
	var team := "蓝" if int(s.get("team", 0)) == 0 else "红"
	var hp := int(s.get("hp", 0))
	var hpm := maxi(1, int(s.get("hp_max", 1)))
	lines.append("【%s】%s %s Lv%d  HP %d/%d (%d%%)   KDA %d/%d/%d" % [
		name, team, role, int(s.get("lvl", 1)), hp, hpm, int(round(float(hp) / float(hpm) * 100.0)),
		int(s.get("k", 0)), int(s.get("d", 0)), int(s.get("a", 0))])
	lines.append("  状态=%s  分路=%s  意图=%s  思考余=%.2fs  score=%.2f" % [
		str(s.get("state", "")), str(s.get("lane", "")), str(s.get("intent", "")),
		float(s.get("think", 0.0)), float(s.get("score", 0.0))])
	var pv := _vec(s.get("pos", Vector2.ZERO))
	lines.append("  位置=(%.1f, %.1f)  移动目标=%s  锁定=%s  追杀=%s" % [
		pv.x, pv.y, _vec_txt(s.get("move", Vector2.ZERO)), str(s.get("manual", "")), str(s.get("chase", ""))])
	var p: Dictionary = s.get("perception", {})
	lines.append("  感知: 敌英雄[%s] 敌兵[%s] 敌塔[%s] 友塔[%s] 野[%s] 血包[%s]" % [
		str(p.get("near_enemy_hero", "")), str(p.get("near_enemy_minion", "")), str(p.get("near_enemy_turret", "")),
		str(p.get("near_friendly_turret", "")), str(p.get("near_jungle", "")), str(p.get("near_health_pack", ""))])
	lines.append("  人数: 6m 友%d/敌%d   12m 友%d/敌%d   20m 友%d/敌%d" % [
		int(p.get("allies6", 0)), int(p.get("enemies6", 0)), int(p.get("allies12", 0)), int(p.get("enemies12", 0)),
		int(p.get("allies20", 0)), int(p.get("enemies20", 0))])
	var c: Dictionary = s.get("combat", {})
	var sk := ""
	for row in c.get("skills", []):
		sk += " %d(Lv%d,CD%.1f)" % [int(row.get("lv", 0)), int(row.get("lv", 0)), float(row.get("cd", 0.0))]
	lines.append("  战斗: 技能%s  强化=%s  回城=%.1f 传送=%.1f 回城中=%s 卡墙=%.1f 移动锁=%.1f" % [
		sk, str(c.get("enhanced", false)), float(c.get("recall", 0.0)), float(c.get("teleport", 0.0)),
		str(c.get("is_recalling", false)), float(c.get("stuck", 0.0)), float(c.get("move_lock", 0.0))])
	var t: Dictionary = s.get("tactics", {})
	var it: Dictionary = s.get("items", {})
	var su: Dictionary = s.get("summoner", {})
	lines.append("  战术: 连招 %d/%d target=%s wait=%.1f feed=%.1f  道具=%s  召唤师=%s  brain=%s" % [
		int(t.get("combo_step", 0)), int(t.get("combo_len", 0)), str(t.get("combo_target", "")),
		float(t.get("combo_wait", 0.0)), float(t.get("feed", 0.0)), str(it.get("last", "")), str(su.get("last", "")),
		str(s.get("brain", ""))])
	var st: Dictionary = s.get("strategy", {})
	lines.append("  策略: 分路[%s]  打野[%s]" % [str(st.get("lane", "")), str(st.get("jungle", ""))])
	var logs: Array = s.get("log", [])
	if not logs.is_empty():
		var start: int = maxi(0, logs.size() - 8)
		var log_txt := "  日志: "
		for i in range(start, logs.size()):
			var e: Dictionary = logs[i]
			log_txt += "[%.1fs]%s  " % [float(e.get("t", 0.0)), str(e.get("s", ""))]
		lines.append(log_txt)
	return "\n".join(lines)


static func _vec(v) -> Vector2:
	if v is Vector2:
		return v
	if v is Dictionary:
		var a = v.get("__v2", [0.0, 0.0])
		if a is Array and (a as Array).size() >= 2:
			return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


static func _vec_txt(v) -> String:
	var p := _vec(v)
	if p == Vector2.ZERO:
		return "无"
	return "(%.1f, %.1f)" % [p.x, p.y]


static func all(snaps: Array, title: String = "", time_txt: String = "") -> String:
	var out: Array = []
	if title != "":
		var head := "==== %s ====" % title
		if time_txt != "":
			head += "  " + time_txt
		out.append(head)
	if snaps.is_empty():
		out.append("（当前没有 AI 思考数据）")
	for s in snaps:
		out.append(hero(s))
	return "\n\n".join(out)
