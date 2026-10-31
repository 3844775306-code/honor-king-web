extends Node

func _ready() -> void:
	var sm := get_node_or_null("/root/SfxManager")
	var bm := BattleManager.new()
	var heroes := 0
	var aas := 0
	var skills := 0
	var bad := 0
	var keys := {}
	for h in bm.hero_configs.keys():
		heroes += 1
		var cfg: Dictionary = bm.hero_configs[h]
		var ar: float = float(cfg.get("attack_range", 325))
		var ak := "aa:%s:%d" % [h, int(ar)]
		if sm._sfx_stream(ak) == null:
			bad += 1; print("AA_FAIL ", h)
		else:
			aas += 1
			keys[ak] = true
		var ids: Array = cfg.get("skills", [])
		for i in mini(3, ids.size()):
			var sk = SkillDatabase.skills.get(str(ids[i]))
			if sk == null:
				print("MISSING ", ids[i]); bad += 1; continue
			var key: String = sm._skill_sfx_key(h, i, int(sk.type))
			if sm._sfx_stream(key) == null:
				bad += 1; print("SK_FAIL ", h, " ", i, " ", key)
			else:
				skills += 1
				keys[key] = true
	print("PROBE heroes=", heroes, " aas=", aas, " skills=", skills, " unique_keys=", keys.size(), " bad=", bad)
	for k in ["aa:小乔:650", "aa:张飞:325", "sk:李白:2:3", "sk:王昭君:1:1", "sk:狄仁杰:0:0"]:
		var st: AudioStream = sm._sfx_stream(k)
		print("PROBE ", k, " len=", snappedf(st.get_length(), 0.001) if st else -1.0)
	bm.free()
	get_tree().quit()
