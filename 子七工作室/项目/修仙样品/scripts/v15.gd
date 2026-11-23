extends RefCounted
## 词条池 v1.5 / 基础装备表 v1.0 试玩覆盖层。
## 装备数字以官方表为准；怪物为临时数值。

const ELEMENTS := ["fire", "ice", "thunder", "poison", "dark"]
const ELEM_ZH := {"fire": "火", "ice": "冰", "thunder": "雷", "poison": "毒", "dark": "暗"}
const RARITY_NAMES := ["白", "绿", "蓝", "紫", "橙", "红", "暗金"]
const AFFIX_COUNTS := [0, 1, 2, 3, 4, 4, 5]
const QUALITY_MULT := [1.00, 1.06, 1.12, 1.18, 1.24, 1.30, 1.38]
const TIER_W := {"普通": 70, "高级": 25, "稀有": 5}
const JEWELRY := ["title", "necklace", "earring", "ring"]
const MIN_SET_RARITY := 4

var db
var base := {}
var pool := {}
var skills := {}
var skill_by_id := {}
var sets_doc := {}
var mon_doc := {}
var affixes: Array = []
var loaded := false


func setup(p_db) -> void:
	db = p_db
	base = _load_json("res://data/equip_base_v1.json")
	pool = _load_json("res://data/affix_pool_v15.json")
	skills = _load_json("res://data/skill_pool_v15.json")
	sets_doc = _load_json("res://data/sets_v15.json")
	mon_doc = _load_json("res://data/monsters_temp_v15.json")
	affixes = pool.get("affixes", [])
	for s in skills.get("skills", []):
		skill_by_id[str(s.get("id", ""))] = s
	_apply_rarity()
	loaded = true


func _load_json(path: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(path)
	var v = JSON.parse_string(raw)
	if typeof(v) != TYPE_DICTIONARY:
		push_error("读取失败：" + path)
		return {}
	return v


func _apply_rarity() -> void:
	var rar: Array = db.t.get("rarities", [])
	for i in mini(rar.size(), 7):
		rar[i]["mult"] = QUALITY_MULT[i]
		rar[i]["affix_count"] = AFFIX_COUNTS[i]
		if i < 4:
			rar[i]["can_be_set"] = false
		else:
			rar[i]["can_be_set"] = true
	db.rarities = rar


func iround(x: float) -> int:
	return int(floor(x + 0.5))


func lerp_num(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


func _bracket(levels: Array, lv: int, key := "item_level") -> Array:
	var lo = null
	var hi = null
	for row in levels:
		var n: int = int(row.get(key, row.get("level", 0)))
		if n == lv:
			return [row, row, 0.0]
		if n <= lv and (lo == null or n > int(lo.get(key, lo.get("level", 0)))):
			lo = row
		if n >= lv and (hi == null or n < int(hi.get(key, hi.get("level", 0)))):
			hi = row
	if lo == null:
		lo = hi
	if hi == null:
		hi = lo
	if lo == null:
		return [null, null, 0.0]
	var a: int = int(lo.get(key, lo.get("level", 0)))
	var b: int = int(hi.get(key, hi.get("level", 0)))
	var t: float = 0.0 if b == a else float(lv - a) / float(b - a)
	return [lo, hi, t]


func official_white(slot_id: String, level: int) -> Dictionary:
	var tiers: Array = base.get("tiers", [])
	var br: Array = _bracket(tiers, level, "item_level")
	if br[0] == null:
		return {}
	var lo: Dictionary = br[0]
	var hi: Dictionary = br[1]
	var t: float = float(br[2])
	var a: Dictionary = (lo.get("white", {}) as Dictionary).get(slot_id, {})
	var b: Dictionary = (hi.get("white", {}) as Dictionary).get(slot_id, {})
	var out := {}
	var keys := {}
	for k in a:
		keys[k] = true
	for k in b:
		keys[k] = true
	for k in keys:
		out[k] = iround(lerp_num(float(a.get(k, 0)), float(b.get(k, 0)), t))
	return out


func official_darkgold(slot_id: String, level: int) -> Dictionary:
	var tiers: Array = base.get("tiers", [])
	var br: Array = _bracket(tiers, level, "item_level")
	if br[0] == null:
		return official_white(slot_id, level)
	var t: float = float(br[2])
	var a: Dictionary = (br[0].get("darkgold", {}) as Dictionary).get(slot_id, {})
	var b: Dictionary = (br[1].get("darkgold", {}) as Dictionary).get(slot_id, {})
	var out := {}
	var keys := {}
	for k in a:
		keys[k] = true
	for k in b:
		keys[k] = true
	for k in keys:
		out[k] = iround(lerp_num(float(a.get(k, 0)), float(b.get(k, 0)), t))
	return out


func main_stats_for(slot_id: String, ri: int, level: int) -> Dictionary:
	if ri >= 6:
		var dg := official_darkgold(slot_id, level)
		if not dg.is_empty():
			return _norm_main(dg)
	var w := official_white(slot_id, level)
	var out := {}
	var m: float = QUALITY_MULT[clampi(ri, 0, 6)]
	for k in w:
		if k in ["aspd", "ms", "crit", "critdmg"]:
			out[db.norm_key(k)] = iround(float(w[k]) * m)
		else:
			out[db.norm_key(k)] = iround(float(w[k]) * m)
	return out


func _norm_main(st: Dictionary) -> Dictionary:
	var out := {}
	for k in st:
		out[db.norm_key(k)] = int(st[k])
	return out


func official_name(slot_id: String, wtype: String, level: int) -> String:
	var tiers: Array = base.get("tiers", [])
	var br: Array = _bracket(tiers, level, "item_level")
	if br[0] == null:
		return ""
	# 用较近的那一档名称，不在两档之间造名字。
	var row: Dictionary = br[0] if float(br[2]) < 0.5 else br[1]
	var names: Dictionary = row.get("names", {})
	if slot_id == "weapon":
		return str(names.get(wtype, names.get("sword", "")))
	return str(names.get(slot_id, ""))


func hero_base(level: int) -> Dictionary:
	var rows: Array = base.get("character_bases", [])
	var br: Array = _bracket(rows, level, "level")
	var out := {"hp": 1875.0, "atk": 120.0, "def": 90.0, "acc_pct": 0.0, "eva_pct": 0.0, "crit_rate_pct": 5.0, "crit_dmg_pct": 150.0, "crit_res": 0.0, "crit_def": 0.0, "res_pct": {}}
	if br[0] == null:
		return out
	var a: Dictionary = br[0]
	var b: Dictionary = br[1]
	var t: float = float(br[2])
	out.hp = lerp_num(float(a.hp), float(b.hp), t)
	out.atk = lerp_num(float(a.atk), float(b.atk), t)
	out.def = lerp_num(float(a.get("defense", a.get("def", 0))), float(b.get("defense", b.get("def", 0))), t)
	out.crit_rate_pct = lerp_num(float(a.get("crit_rate", 5)), float(b.get("crit_rate", 5)), t)
	out.crit_dmg_pct = lerp_num(float(a.get("crit_dmg", 150)), float(b.get("crit_dmg", 150)), t)
	out.crit_res = lerp_num(float(a.get("crit_res", 0)), float(b.get("crit_res", 0)), t)
	out.crit_def = lerp_num(float(a.get("crit_def", 0)), float(b.get("crit_def", 0)), t)
	return out


func monster_stats(id: String, level: int) -> Dictionary:
	var pack: Dictionary = (mon_doc.get("monsters", {}) as Dictionary).get(id, {})
	if pack.is_empty():
		return {}
	var row = null
	for lr in pack.get("levels", []):
		if int(lr.level) == level:
			row = lr
			break
	if row == null and not pack.get("levels", []).is_empty():
		var lvls: Array = pack["levels"]
		row = lvls[clampi(level - 1, 0, lvls.size() - 1)]
	if row == null:
		return {}
	var out := {"kind": pack.get("kind", "normal"), "name": pack.get("name", id), "skill": pack.get("skill", {}), "temporary": true, "level": level}
	for k in ["hp", "atk", "def", "acc_pct", "eva_pct", "res", "attack_interval_s", "crit_res", "crit_def", "dr_pct", "def_ignore_pct", "dodge_cap_pct"]:
		out[k] = row.get(k, pack.get(k, 0))
	return out


func white_weapon_atk(level: int) -> int:
	return int(official_white("weapon", level).get("atk", 1))


func white_chest_hp(level: int) -> int:
	return int(official_white("chest", level).get("hp", 1))


func white_chest_def(level: int) -> int:
	return int(official_white("chest", level).get("def", 1))


func affix_key(ad: Dictionary) -> String:
	var fam: String = str(ad.get("family", ad.get("id", "")))
	var table := {
		"atk_flat": "atk", "hp_flat": "hp", "def_flat": "def",
		"atk_pct": "atk_pct", "hp_pct": "hp_pct", "def_pct": "def_pct",
		"aspd": "aspd", "ms": "ms", "hit": "acc", "dodge": "eva",
		"crit": "crit", "crit_dmg": "critdmg", "crit_res": "crit_res", "crit_def": "crit_def",
		"generic_dmg": "dmg_pct", "elite_dmg": "elite_dmg", "boss_dmg": "boss_dmg",
		"def_pen": "def_pen", "ele_pen": "ele_pen", "dr": "dr_pct",
		"cdr": "cdr", "heal_bonus": "heal_bonus", "stun_res": "stun_res",
		"tenacity": "tenacity", "shield_str": "shield_str", "life_drain": "life_drain",
		"all_elem_res": "all_elem_res",
		"fire_dmg": "elem_fire", "ice_dmg": "elem_ice", "thunder_dmg": "elem_thunder",
		"poison_dmg": "elem_poison", "dark_dmg": "elem_dark",
		"fire_res": "res_fire", "ice_res": "res_ice", "thunder_res": "res_thunder",
		"poison_res": "res_poison", "dark_res": "res_dark",
	}
	if table.has(fam):
		return table[fam]
	# 固定增益技能词条：映射到对应属性
	if fam.begins_with("fixed_skill_"):
		return "fixed_" + fam.substr(13)
	return fam


func _quality_range(ad: Dictionary, ri: int) -> Array:
	var bq: Dictionary = ad.get("by_quality", {})
	var nm: String = RARITY_NAMES[clampi(ri, 0, 6)]
	if bq.has(nm):
		return bq[nm]
	# 白装不出词条；若缺，用相邻档
	for i in range(ri, 7):
		if bq.has(RARITY_NAMES[i]):
			return bq[RARITY_NAMES[i]]
	for i in range(ri, -1, -1):
		if bq.has(RARITY_NAMES[i]):
			return bq[RARITY_NAMES[i]]
	return [1.0, 1.0]


func roll_affix_value(ad: Dictionary, ri: int, level: int) -> Dictionary:
	var rg: Array = _quality_range(ad, ri)
	var lo: float = float(rg[0])
	var hi: float = float(rg[mini(1, rg.size() - 1)])
	var steps: int = maxi(1, iround((hi - lo) * 10.0))
	var coeff: float = lo + float(db.rng.randi_range(0, steps)) / 10.0
	coeff = clampf(coeff, lo, hi)
	var scale: String = str(ad.get("scale", "quality_percent"))
	var val: float = coeff
	if scale == "flat_atk":
		val = float(iround(float(white_weapon_atk(level)) * coeff / 100.0))
	elif scale == "flat_hp":
		val = float(iround(float(white_chest_hp(level)) * coeff / 100.0))
	elif scale == "flat_def":
		val = float(iround(float(white_chest_def(level)) * coeff / 100.0))
	var is_max: bool = is_equal_approx(coeff, hi) or coeff >= hi - 0.0001
	return {"value": val, "coeff": coeff, "is_max": is_max}


func _affix_ok(ad: Dictionary, slot_id: String, ri: int, is_slot5: bool) -> bool:
	if bool(ad.get("slot5_only", false)) and not is_slot5:
		return false
	if bool(ad.get("darkgold_only", false)) and ri < 6:
		return false
	if str(ad.get("id", "")) == "life_drain":
		return ri >= 6 and slot_id == "weapon" and is_slot5
	var slots: Array = ad.get("slots", [])
	if not slots.is_empty() and not slots.has(slot_id):
		return false
	# 固定增益技能建议只出在武器、衣服、裤子，每件最多 1 条（投放时另判）
	return true


func _is_fixed_skill(ad: Dictionary) -> bool:
	return str(ad.get("category", "")).find("固定") >= 0 or str(ad.get("family", "")).begins_with("fixed_skill") or bool(ad.get("timed_trigger", false))


func pick_affixes(slot_id: String, ri: int, level: int) -> Array:
	var cnt: int = AFFIX_COUNTS[clampi(ri, 0, 6)]
	var out: Array = []
	var has_fixed := false
	for i in cnt:
		var is_slot5: bool = (i == 4 and ri >= 6)
		# 第 5 栏：武器有 35% 概率出汲取
		if is_slot5 and slot_id == "weapon" and db.rng.randf() < 0.35:
			var drain_ad = _affix_by_id("life_drain")
			if not drain_ad.is_empty():
				out.append(_make_affix_roll(drain_ad, ri, level, is_slot5))
				continue
		var picked := _weighted_pick(slot_id, ri, is_slot5, has_fixed, out)
		if picked.is_empty():
			continue
		if _is_fixed_skill(picked):
			has_fixed = true
		out.append(_make_affix_roll(picked, ri, level, is_slot5))
	return out


func _affix_by_id(aid: String) -> Dictionary:
	for a in affixes:
		if str(a.get("id", "")) == aid:
			return a
	return {}


func _weighted_pick(slot_id: String, ri: int, is_slot5: bool, has_fixed: bool, already: Array) -> Dictionary:
	# 先抽层级，再在该层合法词条里按 weight 抽。可重复。
	for _try in 8:
		var tname := "普通"
		var r: float = db.rng.randf() * 100.0
		if r < 70.0:
			tname = "普通"
		elif r < 95.0:
			tname = "高级"
		else:
			tname = "稀有"
		var cand: Array = []
		var wsum := 0
		for a in affixes:
			if str(a.get("tier", "")) != tname:
				continue
			if not _affix_ok(a, slot_id, ri, is_slot5):
				continue
			if _is_fixed_skill(a) and has_fixed:
				continue
			if _is_fixed_skill(a) and not slot_id in ["weapon", "chest", "legs"]:
				continue
			var w: int = maxi(1, int(a.get("weight", 10)))
			cand.append([a, w])
			wsum += w
		if wsum <= 0:
			continue
		var pick: int = db.rng.randi_range(1, wsum)
		var acc := 0
		for c in cand:
			acc += int(c[1])
			if pick <= acc:
				return c[0]
	return {}


func _make_affix_roll(ad: Dictionary, ri: int, level: int, is_slot5: bool) -> Dictionary:
	var rolled := roll_affix_value(ad, ri, level)
	return {
		"id": str(ad.get("id", "")),
		"key": affix_key(ad),
		"name": str(ad.get("name", ad.get("id", ""))),
		"pts": rolled.value,
		"value": rolled.value,
		"is_max": rolled.is_max,
		"slot5": is_slot5,
	}


func bake_exclusive_skill(sid: String, ri: int) -> Dictionary:
	var sd: Dictionary = skill_by_id.get(sid, {})
	if sd.is_empty():
		return {}
	var stage_n: int = 1 if ri >= 4 else 0
	if ri >= 5:
		stage_n = 2
	if ri >= 6:
		stage_n = 3
	if stage_n <= 0:
		return {}
	var stages: Array = sd.get("stages", [])
	var desc_parts: PackedStringArray = PackedStringArray()
	var runtime := {}
	for i in mini(stage_n, stages.size()):
		var st: Dictionary = stages[i]
		desc_parts.append(str(st.get("desc", "")))
		runtime = st.get("runtime", runtime)
	return {
		"id": str(sd.get("id", sid)),
		"name": str(sd.get("name", sid)),
		"trigger": str(sd.get("trigger", runtime.get("type", "auto"))),
		"cd": int(runtime.get("cd", sd.get("cd", 0))),
		"chance": float(runtime.get("chance", 100)),
		"desc": "".join(desc_parts) if false else " ".join(desc_parts),
		"runtime": runtime,
		"stage": stage_n,
		"exclusive": true,
	}


func pick_exclusive_skill(slot_id: String, wtype: String, ri: int, force_id := "") -> Dictionary:
	if ri < 4:
		return {}
	if force_id != "" and skill_by_id.has(force_id):
		return bake_exclusive_skill(force_id, ri)
	var cand: Array = []
	var wsum := 0
	for s in skills.get("skills", []):
		var slots: Array = s.get("slots", [])
		var wtypes: Array = s.get("weapon_types", [])
		var ok := false
		if slot_id == "weapon":
			ok = slots.has("weapon") and (wtypes.is_empty() or wtypes.has(wtype))
		else:
			ok = slots.has(slot_id)
		if not ok:
			continue
		var wb: Dictionary = s.get("weight_by_slot", {})
		var w: int = 10
		if slot_id == "weapon" and wb.has(wtype):
			w = int(wb[wtype])
		elif wb.has(slot_id):
			w = int(wb[slot_id])
		w = maxi(1, w)
		cand.append([s, w])
		wsum += w
	if wsum <= 0:
		return {}
	var pick: int = db.rng.randi_range(1, wsum)
	var acc := 0
	for c in cand:
		acc += int(c[1])
		if pick <= acc:
			return bake_exclusive_skill(str(c[0].get("id", "")), ri)
	return {}


func roll_set_id(slot_id: String, ri: int) -> String:
	if ri < MIN_SET_RARITY:
		return ""
	if slot_id in JEWELRY:
		return ""
	var chance: float = float(sets_doc.get("drop_convert_chance", 0.45))
	if db.rng.randf() >= chance:
		return ""
	var opts: Array = []
	for k in sets_doc.get("sets", {}):
		var s: Dictionary = sets_doc["sets"][k]
		if slot_id in s.get("slots", []):
			opts.append(str(s.get("id", k)))
	if opts.is_empty():
		return ""
	return str(opts[db.rng.randi() % opts.size()])


func set_bonus(equip: Dictionary) -> Dictionary:
	var out := {"groups": {}, "stats": {}, "triggers": [], "leech": 0, "skill_leech": 0, "hit_heal": 0, "life_drain": 0.0}
	var packs: Dictionary = sets_doc.get("sets", {})
	for set_id in packs.keys():
		var defn: Dictionary = packs[set_id]
		var slots: Array = defn.get("slots", [])
		var pieces: Array = []
		for sid in slots:
			var it = equip.get(str(sid), null)
			if it == null:
				continue
			if str(it.get("set_id", "")) != str(set_id):
				continue
			if int(it.get("rarity", 0)) < MIN_SET_RARITY:
				continue
			pieces.append(it)
		var n: int = pieces.size()
		var got: Array = []
		var best := 0
		for b in defn.get("breaks", []):
			if n >= int(b):
				got.append(int(b))
				best = maxi(best, int(b))
		out.groups["%s:%s" % [set_id, "main"]] = {"count": n, "breaks": got, "set_id": set_id, "name": defn.get("name", set_id)}
		if best <= 0:
			continue
		var bonus: Dictionary = defn.get("bonus", {})
		var row = bonus.get(str(best), {})
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("type", "")) == "life_drain":
			out.life_drain += float(row.get("value", 0))
		elif str(row.get("type", "")) == "stat":
			var k: String = str(row.get("stat", "atk_pct"))
			out.stats[k] = float(out.stats.get(k, 0)) + float(row.get("value", 0))
	return out


func set_display_name(set_id: String) -> String:
	var s: Dictionary = (sets_doc.get("sets", {}) as Dictionary).get(set_id, {})
	return str(s.get("name", set_id))


func set_def(set_id: String) -> Dictionary:
	return (sets_doc.get("sets", {}) as Dictionary).get(set_id, {})


func apply_make_item(it: Dictionary, slot_id: String, ri: int, level: int, wtype: String, force_skill := "") -> Dictionary:
	it["main"] = main_stats_for(slot_id, ri, level)
	it["affixes"] = pick_affixes(slot_id, ri, level)
	it["skills"] = []
	it["set_id"] = roll_set_id(slot_id, ri)
	if slot_id == "weapon":
		it.wtype = wtype if wtype != "" else str(db.r.get("default_weapon_type", "sword"))
	if ri >= 4:
		var sk := pick_exclusive_skill(slot_id, str(it.get("wtype", wtype)), ri, force_skill)
		if not sk.is_empty():
			it.skills.append(sk)
	var nm := official_name(slot_id, str(it.get("wtype", "")), level)
	if nm != "":
		it["base_name"] = nm
		it.name = nm
	else:
		it.name = db.item_name(it)
	if str(it.get("set_id", "")) != "":
		# 名称仍用部位名，套装在卡片上显示
		pass
	it["v15"] = true
	return it


func refresh_item_on_upgrade(it: Dictionary) -> void:
	var slot_id: String = str(it.get("slot", ""))
	var ri: int = int(it.get("rarity", 0))
	var level: int = int(it.get("level", 1))
	it.main = main_stats_for(slot_id, ri, level)
	var want: int = AFFIX_COUNTS[clampi(ri, 0, 6)]
	while it.affixes.size() < want:
		var is_slot5: bool = it.affixes.size() == 4 and ri >= 6
		if is_slot5 and slot_id == "weapon" and db.rng.randf() < 0.35:
			var drain_ad = _affix_by_id("life_drain")
			if not drain_ad.is_empty():
				it.affixes.append(_make_affix_roll(drain_ad, ri, level, true))
				continue
		var picked := _weighted_pick(slot_id, ri, is_slot5, _item_has_fixed(it), it.affixes)
		if picked.is_empty():
			break
		it.affixes.append(_make_affix_roll(picked, ri, level, is_slot5))
	if ri >= 4:
		if it.skills.is_empty():
			var sk := pick_exclusive_skill(slot_id, str(it.get("wtype", "")), ri)
			if not sk.is_empty():
				it.skills.append(sk)
		else:
			# 升品：按新品阶重烘焙同一技能的已解锁段
			var sid: String = str(it.skills[0].get("id", ""))
			var baked := bake_exclusive_skill(sid, ri)
			if not baked.is_empty():
				it.skills[0] = baked
	var nm := official_name(slot_id, str(it.get("wtype", "")), level)
	if nm != "":
		it["base_name"] = nm
		it.name = nm


func _item_has_fixed(it: Dictionary) -> bool:
	for a in it.get("affixes", []):
		var ad := _affix_by_id(str(a.get("id", "")))
		if _is_fixed_skill(ad):
			return true
	return false


func compute_damage(src, tgt, mult: float, is_skill: bool) -> Dictionary:
	# 命中（命中-闪避属性，与高防闪避分开）
	var acc: float = float(src.acc) if "acc" in src else 0.0
	var eva: float = float(tgt.eva) if "eva" in tgt else 0.0
	var hit_rate: float = clampf(0.95 + acc / 100.0 - eva / 100.0, 0.2, 1.0)
	if db.rng.randf() >= hit_rate:
		return {"hit": false, "dodge": false, "miss": true, "dmg": 0, "crit": false, "rate": hit_rate}

	var atk: float = maxf(0.0, float(src.atk) * mult)
	var def0: float = maxf(0.0, float(tgt.def))
	var shred: float = 0.0
	if "def_shred" in tgt:
		shred = maxf(shred, float(tgt.def_shred))
	if "def_pen" in src:
		shred = maxf(shred, float(src.def_pen))
	# 精英/首领无视防御：攻击方若是精英/首领，或目标是精英/首领时，取目标侧的无视（打怪时用怪的 def_ignore）
	var ignore: float = 0.0
	if "def_ignore_pct" in tgt:
		ignore = float(tgt.def_ignore_pct)
	if "def_ignore_pct" in src:
		ignore = maxf(ignore, float(src.def_ignore_pct))
	var eff_def: float = def0 * (1.0 - clampf(ignore, 0.0, 90.0) / 100.0)
	eff_def *= (1.0 - clampf(shred, 0.0, 90.0) / 100.0)
	eff_def = maxf(0.0, eff_def)

	# 高防闪避
	var cap: float = 0.0
	if "dodge_cap_pct" in tgt:
		cap = float(tgt.dodge_cap_pct)
	else:
		var kind := "normal"
		if "mkind" in tgt:
			kind = str(tgt.kind_rank) if "kind_rank" in tgt else "normal"
		if "kind_rank" in tgt:
			kind = str(tgt.kind_rank)
		match kind:
			"elite":
				cap = 25.0
			"boss":
				cap = 15.0
			_:
				cap = 50.0 if str(tgt.team) == "enemy" else 0.0
	if cap > 0.0 and atk > 0.0 and eff_def > 1.5 * atk:
		var chance: float = minf(cap, (eff_def / atk - 1.5) * 100.0)
		if db.rng.randf() * 100.0 < chance:
			return {"hit": false, "dodge": true, "miss": false, "dmg": 0, "crit": false, "rate": hit_rate, "dodge_chance": chance}

	var base_d: float = 0.0 if atk <= 0.0 else (atk * atk) / (atk + eff_def)

	# 会心：有效会心率 = 会心率 - 会心抵抗，不设上限；有效会伤 = max(120, 会伤-会防)
	var c_res: float = float(tgt.crit_res) if "crit_res" in tgt else 0.0
	var c_def: float = float(tgt.crit_def) if "crit_def" in tgt else 0.0
	var eff_crate: float = maxf(0.0, float(src.crit) - c_res)
	if "next_must_crit" in src and bool(src.next_must_crit):
		eff_crate = 100.0
	var crit: bool = db.rng.randf() * 100.0 < eff_crate
	var eff_cdmg: float = maxf(120.0, float(src.critdmg) - c_def)
	var cm: float = eff_cdmg / 100.0 if crit else 1.0

	# 每种增伤单独计算再合计
	var inc: float = 0.0
	inc += float(src.dmg_pct) / 100.0 if "dmg_pct" in src else 0.0
	var tkind := "normal"
	if "kind_rank" in tgt:
		tkind = str(tgt.kind_rank)
	if tkind == "elite" and "elite_dmg" in src:
		inc += float(src.elite_dmg) / 100.0
	if tkind == "boss" and "boss_dmg" in src:
		inc += float(src.boss_dmg) / 100.0
	if is_skill and "skill" in src:
		inc += float(src.skill) / 100.0
	if "next_hit_pct" in src:
		inc += float(src.next_hit_pct) / 100.0

	# 属性：有附着才生效。保底 P（不受抗）+ (S+词条-抗性)
	var ele_inc: float = 0.0
	var attached: String = str(src.attached_elem) if "attached_elem" in src else ""
	if attached != "" and attached in ELEMENTS:
		var p: float = float(src.elem_p) if "elem_p" in src else 0.0
		var s_plus: float = 0.0
		if "elem" in src and src.elem.has(attached):
			s_plus += float(src.elem[attached])
		if "ele_pen" in src:
			s_plus += float(src.ele_pen)
		var resist: float = 0.0
		if "res" in tgt and tgt.res.has(attached):
			resist = float(tgt.res[attached])
		# 易伤
		if "vuln" in tgt and tgt.vuln.has(attached):
			s_plus += float(tgt.vuln[attached])
		ele_inc += p / 100.0
		ele_inc += (s_plus - resist) / 100.0

	var raw: float = base_d * (1.0 + inc + ele_inc) * cm
	var dr: float = 0.0
	if "dr_pct" in tgt:
		dr = float(tgt.dr_pct)
	raw *= maxf(0.0, 1.0 - dr / 100.0)
	var dmg: int = iround(raw)  # 可以为 0，不设保底
	return {"hit": true, "dodge": false, "miss": false, "dmg": dmg, "crit": crit, "rate": hit_rate, "base": base_d}


func attached_element_of(stats: Dictionary, equip: Dictionary) -> Dictionary:
	# 武器孔里的属性石视为附着。P/S 按暗金建议临时：无品质信息时 P=10、S 来自宝石值。
	var out := {"elem": "", "p": 0.0, "s": 0.0}
	var it = equip.get("weapon", null) if equip != null else null
	if it == null:
		return out
	for gm in it.get("sockets", []):
		if gm == null:
			continue
		var gid: String = str(gm.get("id", ""))
		for e in ELEMENTS:
			if gid.find(e) >= 0 or gid.find({"fire":"fire","ice":"frost","thunder":"lightning","poison":"poison","dark":"shadow"}[e]) >= 0:
				out.elem = e
				out.p = 10.0
				out.s = 10.0
				return out
		if gid.find("frost") >= 0 or gid.find("ice") >= 0:
			out.elem = "ice"; out.p = 10.0; out.s = 10.0; return out
		if gid.find("lightning") >= 0 or gid.find("thunder") >= 0:
			out.elem = "thunder"; out.p = 10.0; out.s = 10.0; return out
		if gid.find("shadow") >= 0 or gid.find("dark") >= 0:
			out.elem = "dark"; out.p = 10.0; out.s = 10.0; return out
		if gid.find("fire") >= 0:
			out.elem = "fire"; out.p = 10.0; out.s = 10.0; return out
	return out
