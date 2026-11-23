extends RefCounted
## 装备数据库：读 data/equipment.json（创意部《装备数值表》）+ data/equipment_rules.json（文字公式转数字 / 占位）。
## 生成装备、算属性、算伤害。这里不写任何数值，全部从两张表读；换同结构的新表直接生效。

var t := {}            # 装备数值表
var r := {}            # 规则补充
var rarities: Array = []
var rarity_idx := {}   # "白"/"white" -> index
var slots: Array = []  # 按表顺序
var slot_by_id := {}
var affix_by_id := {}
var affix_by_name := {}
var gem_by_id := {}
var special_by_id := {}
var curve_rows: Array = []
var elements: Array = []          # ["frost","fire","lightning","shadow"]
var elem_names := {}
var stat_names := {}
var profile_key := "slice"
var item_cap := 10
var total_cap := 100
var fx_thresholds: Array = []
var fx_source := ""
var enh_curve: Array = []
var warnings: Array = []
var rarity_boost := {}        # 仅模拟用：稀有度下标 -> 占比倍数（main 在 --sim-drop-boost 下设置）
var param_source := {}        # 参数键 -> "equipment.json:路径" 或 "equipment_rules.json（占位）"
var next_uid := 1
var rng := RandomNumberGenerator.new()
var v15 = null          # 词条池 v1.5 / 基础装备表 v1.0 覆盖层

func iround(x: float) -> int:
	return int(floor(x + 0.5))


func is_v13() -> bool:
	return str(t.get("version", "")) == "1.3" or t.has("combat_v13")


func enhance_cap_for(it: Dictionary) -> int:
	var e: Dictionary = t.get("enhance", {})
	if int(it.get("level", 1)) < 30:
		return int(e.get("cap_below_30", 10))
	return int(e.get("cap_at_or_above_30", 20))


func white_weapon_atk(level: int) -> int:
	if v15 != null and v15.loaded:
		return v15.white_weapon_atk(level)
	for row in curve_rows:
		if int(row.item_level) == level and row.has("white_weapon_atk"):
			return int(row.white_weapon_atk)
	# 相邻等级线性再取整
	var lo = null
	var hi = null
	for row in curve_rows:
		var lv: int = int(row.item_level)
		if lv <= level:
			lo = row
		if lv >= level and hi == null:
			hi = row
	if lo == null:
		return 6
	if hi == null or lo == hi:
		return int(lo.get("white_weapon_atk", 6))
	var a: int = int(lo.item_level)
	var b: int = int(hi.item_level)
	var wa: float = float(lo.white_weapon_atk)
	var wb: float = float(hi.white_weapon_atk)
	return iround(wa + (wb - wa) * float(level - a) / float(b - a))


func enhance_total_atk(level: int, plus: int) -> int:
	var capn: int = 10 if level < 30 else 20
	var n: int = mini(maxi(0, plus), capn)
	if n <= 0:
		return 0
	var w: float = float(white_weapon_atk(level))
	var t1: float = (10.0 / 240.0) * w
	var t2: float = (15.0 / 240.0) * w
	var t3: float = (20.0 / 240.0) * w
	var raw: float
	if n <= 10:
		raw = t1 * n
	elif n <= 15:
		raw = 10.0 * t1 + t2 * (n - 10)
	else:
		raw = 10.0 * t1 + 5.0 * t2 + t3 * (n - 15)
	return iround(raw)


func enhance_step_atk(level: int, plus: int) -> int:
	if plus <= 0:
		return 0
	return enhance_total_atk(level, plus) - enhance_total_atk(level, plus - 1)


func gem_flat_atk(level: int) -> int:
	return maxi(1, iround(float(white_weapon_atk(level)) * 0.10))


func skill_unlock_slots(ri: int) -> Array:
	var un: Dictionary = t.get("skill_unlock_by_rarity", {})
	var key: String = rarity_name(ri)
	var v = un.get(key, null)
	if str(v) == "all" or ri >= 6:
		var alls: Array = []
		for s in slots:
			alls.append(s.id)
		return alls
	if typeof(v) == TYPE_ARRAY:
		return v
	if ri <= 0:
		return ["chest", "weapon"]
	return ["chest", "weapon"]


func skill_def(id: String) -> Dictionary:
	for a in t.get("skill_affixes", []):
		if str(a.get("id", "")) == id:
			return a
	return {}


func bake_skill(sd: Dictionary, level: int) -> Dictionary:
	var rt: Dictionary = sd.get("runtime", {}).duplicate(true)
	if rt.has("hit_heal"):
		rt.hit_heal = maxi(int(rt.get("hit_heal", 0)), iround(float(white_weapon_atk(level)) * 0.45))
	var desc := str(sd.get("desc", ""))
	for k in rt.keys():
		desc = desc.replace("{%s}" % str(k), str(rt[k]))
	return {
		"id": str(sd.get("id", "")),
		"name": str(sd.get("name", sd.get("id", ""))),
		"desc": desc,
		"runtime": rt,
		"trigger": str(sd.get("trigger", "auto")),
		"cd": int(sd.get("cd", 8)),
		"chance": int(sd.get("chance", 100)),
	}


func load_tables(table_path := "res://data/equipment.json", rules_path := "res://data/equipment_rules.json") -> bool:
	var tt = JSON.parse_string(FileAccess.get_file_as_string(table_path))
	var rr = JSON.parse_string(FileAccess.get_file_as_string(rules_path))
	if typeof(tt) != TYPE_DICTIONARY or typeof(rr) != TYPE_DICTIONARY:
		push_error("装备表读取失败")
		return false
	t = tt; r = rr
	rng.randomize()
	_apply_table_params()
	rarities = t.get("rarities", [])
	for i in rarities.size():
		var ra: Dictionary = rarities[i]
		rarity_idx[ra.get("name", "")] = i
		rarity_idx[ra.get("id", "")] = i
	slots = t.get("slots", [])
	for s in slots:
		slot_by_id[s.id] = s
	for a in t.get("affixes", []):
		affix_by_id[a.id] = a
		affix_by_name[a.name] = a
	for g in t.get("gems", []):
		gem_by_id[g.id] = g
	for sp in t.get("special_affixes", []):
		special_by_id[sp.id] = sp
	for st in t.get("stats", []):
		stat_names[st.id] = st.name
	curve_rows = t.get("level_curve", [])
	elements = (t.get("formula", {}).get("elements", {}) as Dictionary).keys()
	if elements.is_empty():
		elements = (r.elements.names as Dictionary).keys()
	elem_names = r.elements.names
	_load_enhance()
	v15 = load("res://scripts/v15.gd").new()
	v15.setup(self)
	elements = v15.ELEMENTS.duplicate()
	elem_names = v15.ELEM_ZH.duplicate()
	if r.has("element_names") and typeof(r.element_names) == TYPE_DICTIONARY:
		for k in r.element_names:
			elem_names[k] = r.element_names[k]
	return true

## v0.4 起表里有数字字段：一律以表为准，覆盖 rules 里的同名占位；表里没有的才用 rules
func _take(key: String, val, path: String) -> void:
	if val == null:
		if r.has(key):
			param_source[key] = "equipment_rules.json（占位）"
		return
	r[key] = val
	param_source[key] = "equipment.json:" + path

func _dig(path: String):
	var cur = t
	for k in path.split("."):
		if typeof(cur) != TYPE_DICTIONARY or not cur.has(k):
			return null
		cur = cur[k]
	return cur

func _apply_table_params() -> void:
	for k in ["g_curve", "hero_base", "def_k", "hit", "crit", "level_mod", "variance"]:
		_take(k, _dig("formula." + k), "formula." + k)
	for k in ["quality_range", "budget_roll", "affix_weight_range"]:
		_take(k, _dig("formula.roll." + k), "formula.roll." + k)
	# 属性：叠层参数 formula.element_stack + 各属性 formula.elements.<e>；显示名表里没有，留 rules
	var es = _dig("formula.element_stack")
	var fe = _dig("formula.elements")
	if es != null and fe != null:
		var er := {"names": r.get("element_names", r.get("elements", {}).get("names", {}))}
		for k in es: er[k] = es[k]
		for e in fe: er[e] = fe[e]
		if not er.has("lightning") or not er.lightning.has("dmg_taken_per_stack"):
			er.lightning = er.get("lightning", {}); er.lightning.dmg_taken_per_stack = _dig("formula.damage.lightning_vuln_per_stack")
		r.elements = er
		param_source["elements"] = "equipment.json:formula.element_stack + formula.elements"
	else:
		r.elements = r.get("elements", {}); r.elements.names = r.get("element_names", r.elements.get("names", {}))
	var pity = _dig("drop_tables.pity")
	_take("pity", pity if typeof(pity) == TYPE_DICTIONARY else null, "drop_tables.pity")
	_take("gem_merge_count", _dig("gem_merge_count"), "gem_merge_count")
	_take("gem_drop", _dig("gem_drop"), "gem_drop")
	_take("starter_gems", _dig("starter_gems"), "starter_gems")
	_take("starter_gear", _dig("starter_gear"), "starter_gear")
	_take("hero_level", _dig("qingshi.sample.hero_level"), "qingshi.sample.hero_level")
	_take("farm_item_levels", _dig("qingshi.sample.farm_item_levels"), "qingshi.sample.farm_item_levels")

## 角色基础：heroes.levels 里该等级那一行；没有就用 formula.hero_base × g(等级)
func hero_base_row(level: int) -> Dictionary:
	if v15 != null and v15.loaded:
		var row: Dictionary = v15.hero_base(level)
		# 兼容旧字段名
		row["crit_rate_pct"] = row.get("crit_rate_pct", 5)
		row["crit_dmg_pct"] = row.get("crit_dmg_pct", 150)
		return row
	for row2 in _dig_arr("heroes.levels"):
		if int(row2.level) == level:
			return row2
	var hb: Dictionary = r.hero_base
	var gl := g(level)
	return {"hp": float(hb.hp) * gl, "atk": float(hb.atk) * gl, "def": float(hb.def) * gl, "acc_pct": hb.get("acc_pct", 0), "eva_pct": hb.get("eva_pct", 0),
		"crit_rate_pct": hb.get("crit_rate_pct", r.crit.base_rate_pct), "crit_dmg_pct": hb.get("crit_dmg_pct", r.crit.base_dmg_pct), "res_pct": hb.get("res_pct", {})}

func _dig_arr(path: String) -> Array:
	var v = _dig(path)
	return v if typeof(v) == TYPE_ARRAY else []

## 怪物数值：monsters.<id>.levels 里该等级那一行；没有就 coef × g(等级)（monster_formula）
func monster_stats(id: String, level: int) -> Dictionary:
	if v15 != null and v15.loaded:
		var vms: Dictionary = v15.monster_stats(id, level)
		if not vms.is_empty():
			return vms
	var m = _dig("monsters." + id)
	if m == null:
		return {}
	var out := {"kind": m.get("kind", "normal"), "name": m.get("name", id), "skill": m.get("skill", {})}
	var row = null
	for lr in m.get("levels", []):
		if int(lr.level) == level:
			row = lr
	if row == null:
		var gl := g(level)
		row = {"hp": float(m.coef.hp) * gl, "atk": float(m.coef.atk) * gl, "def": float(m.coef.def) * gl, "acc_pct": m.get("acc_pct", 0), "eva_pct": m.get("eva_pct", 0), "res": m.get("res", {}), "attack_interval_s": m.get("attack_interval_s", 1.0)}
	for k in ["hp", "atk", "def", "acc_pct", "eva_pct", "res", "attack_interval_s", "bind_silver"]:
		out[k] = row.get(k, m.get(k, 0))
	out.level = level
	return out

## 卖价（占位，config.bag.sell_price × V(等级)；数值表没有出售价）
func sell_price(it: Dictionary, bag_cfg: Dictionary) -> int:
	var sp: Dictionary = bag_cfg.get("sell_price", {})
	return int(round(float(sp.get(rarity_name(int(it.rarity)), 1)) * V(int(it.level))))

func _load_enhance() -> void:
	var e: Dictionary = t.get("enhance", {})
	profile_key = str(r.get("enhance_profile", "slice"))
	var profs: Dictionary = e.get("profiles", {})
	var p: Dictionary = profs.get(profile_key, {})
	var n_slots: int = int(e.get("slots_counted", slots.size()))
	# v1.3：上限按装备等级（<30 为 +10，否则 +20）。item_cap 只作默认显示。
	if is_v13():
		item_cap = int(e.get("cap_below_30", 10))
	elif p.has("item_cap"):
		item_cap = int(p.item_cap)
	elif profile_key == "slice" and e.has("slice_item_cap"):
		item_cap = int(e.slice_item_cap)
	else:
		item_cap = int(e.get("item_cap", 10))
	total_cap = int(p.get("total_cap", item_cap * n_slots))
	# 门槛：<key>_fx_thresholds（slice_fx_thresholds）→ profiles.<key>.fx_thresholds → 正式版 fx_thresholds → 按 thresholds_ratio 算
	var key_field := "fx_thresholds" if profile_key == "formal" else profile_key + "_fx_thresholds"
	if e.has(key_field):
		fx_thresholds = e[key_field]; fx_source = "enhance." + key_field
	elif p.has("fx_thresholds"):
		fx_thresholds = p.fx_thresholds; fx_source = "enhance.profiles.%s.fx_thresholds" % profile_key
	elif e.has("thresholds_ratio"):
		fx_thresholds = []
		for k in e.thresholds_ratio:
			fx_thresholds.append(int(floor(float(k) * total_cap)) + 1)
		fx_source = "floor(thresholds_ratio × %d) + 1" % total_cap
	# 自检：与比例公式不一致时提醒
	if e.has("thresholds_ratio"):
		for i in mini(fx_thresholds.size(), (e.thresholds_ratio as Array).size()):
			var calc: int = int(floor(float(e.thresholds_ratio[i]) * total_cap)) + 1
			if calc != int(fx_thresholds[i]):
				warnings.append("全身特效门槛 %d：表值 %d ≠ 公式 %d" % [i + 1, int(fx_thresholds[i]), calc])
	enh_curve = e.get("curve", [])

# ---------- 查表 ----------
func rarity(i: int) -> Dictionary:
	return rarities[clampi(i, 0, rarities.size() - 1)]

func rarity_color(i: int) -> Color:
	return Color(rarity(i).color)

func rarity_name(i: int) -> String:
	return rarity(i).name

func V(level: int) -> float:
	var best = null
	for row in curve_rows:
		if int(row.item_level) == level:
			return float(row.V)
		if int(row.item_level) <= level:
			best = row
	return float(best.V) if best != null else 1.0

func g(level: float) -> float:
	var gc: Dictionary = r.g_curve
	return pow(float(gc.base), (level - float(gc.ref_level)) / float(gc.div))

func enhance_cum_pct(lv: int) -> float:
	if lv <= 0:
		return 0.0
	for row in enh_curve:
		if int(row.level) == lv:
			if row.has("cum_pct"):
				return float(row.cum_pct)
			return (float(row.get("main_stat_mult", 1.0)) - 1.0) * 100.0
	# 曲线缺失时退回：逐级累加 per_level_pct
	var s := 0.0
	for row in enh_curve:
		if int(row.level) <= lv:
			s += float(row.get("per_level_pct", 0.0))
	return s

## 成功率：profiles.<方案>.success_rates → <方案>_success_rates → success_rates → rules 占位
func enhance_rates() -> Array:
	var e: Dictionary = t.get("enhance", {})
	var p: Dictionary = e.get("profiles", {}).get(profile_key, {})
	if p.has("success_rates"): return p.success_rates
	if e.has(profile_key + "_success_rates"): return e[profile_key + "_success_rates"]
	if e.has("success_rates"): return e.success_rates
	return r.get("enhance_success", {}).get("rates", [1.0])

func enhance_success_rate(lv: int, blessing := 0.0) -> float:
	var rates: Array = enhance_rates()
	return minf(1.0, float(rates[clampi(lv, 0, rates.size() - 1)]) + blessing)

func _idx_val(key: String, lv: int, def_val):
	var e: Dictionary = t.get("enhance", {})
	var v = e.get(key, r.get("enhance_" + key, def_val))
	if typeof(v) == TYPE_ARRAY:
		return v[clampi(lv, 0, v.size() - 1)] if not v.is_empty() else def_val
	return v

## 失败后的等级：掉 fail_drop[lv] 级，但不低于安全线 safe_floor[lv]（index 0 = 从 +0 强到 +1）
func enhance_fail_level(lv: int) -> int:
	var drop: int = int(_idx_val("fail_drop", lv, 1))
	var floor_lv: int = int(_idx_val("safe_floor", lv, 0))
	return maxi(lv - drop, mini(lv, floor_lv))

func blessing_per_fail() -> float:
	return float(t.get("enhance", {}).get("blessing_per_fail", 0.0))

func blessing_reset_on_success() -> bool:
	return bool(t.get("enhance", {}).get("blessing_reset_on_success", true))

## 消耗（试玩版只显示，不扣：样品还没有货币系统）
func enhance_cost(it: Dictionary) -> Dictionary:
	var c = _dig("enhance.cost")
	if c == null:
		return {}
	var lv: int = int(it.enhance)
	var mult: Array = c.get("bind_silver_mult", [1])
	var st: Array = c.get("refine_stones", [0])
	return {"silver": int(round(float(c.get("bind_silver_base", 0)) * V(int(it.level)) * float(mult[clampi(lv, 0, mult.size() - 1)]))), "stones": int(st[clampi(lv, 0, st.size() - 1)])}

func fx_tier(total: int) -> int:
	var n := 0
	for th in fx_thresholds:
		if total >= int(th):
			n += 1
	return n

func is_pct_key(k: String) -> bool:
	if k.ends_with("_pct"):
		return true
	if k in ["crit", "critdmg", "crit_res", "crit_def", "ms", "aspd", "acc", "eva", "leech", "skill_leech", "life_drain", "def_pen", "ele_pen", "dmg_pct", "elite_dmg", "boss_dmg", "heal_bonus", "stun_res", "tenacity", "cdr"]:
		return true
	if k.begins_with("elem_") or k.begins_with("res_"):
		return true
	return affix_by_id.has(k) and str(affix_by_id[k].get("type", "")) == "pct"

## 统一属性键：main_stats 里的 "ms_pct"/"acc_pct" → 与词条同名的 "ms"/"acc"
func norm_key(k: String) -> String:
	if k.ends_with("_pct") and not affix_by_id.has(k) and affix_by_id.has(k.trim_suffix("_pct")):
		return k.trim_suffix("_pct")
	return k

func stat_label(k: String) -> String:
	if k.begins_with("elem_"):
		return "%s属性增伤" % elem_names.get(k.substr(5), k)
	if k.begins_with("res_"):
		return "%s抗性" % elem_names.get(k.substr(4), k)
	var aliases := {
		"life_drain": "生命汲取", "dmg_pct": "增伤", "elite_dmg": "对精英增伤", "boss_dmg": "对首领增伤",
		"def_pen": "无视防御", "ele_pen": "属性穿透", "crit_res": "会心抵抗", "crit_def": "会心防御",
		"dr_pct": "减伤", "heal_bonus": "治疗效果", "stun_res": "眩晕抗性", "cdr": "冷却缩减",
		"atk": "攻击", "hp": "生命", "def": "防御", "aspd": "攻速", "ms": "移速",
		"crit": "会心率", "critdmg": "会心伤害", "acc": "命中", "eva": "闪避",
	}
	if aliases.has(k):
		return aliases[k]
	if affix_by_id.has(k):
		return affix_by_id[k].name
	return stat_names.get(k, k)

# ---------- 掉落 ----------
func region_row(region: String) -> Dictionary:
	for row in t.drop_tables.get("region_cap", []):
		if row.region == region:
			return row
	return {}

## 某怪物类型在某区域的稀有度权重（已按区域上限删档并归一化）
func drop_weights(kind: String, region: String) -> Array:
	var dt: Dictionary = t.drop_tables
	var row := region_row(region)
	var w: Array = []
	if not row.is_empty() and row.has(kind):
		w = (row[kind] as Array).duplicate()
	else:
		w = (dt.by_monster[kind].weights as Array).duplicate()
	var cap := rarities.size() - 1
	if not row.is_empty() and rarity_idx.has(row.get("max_rarity", "")):
		cap = rarity_idx[row.max_rarity]
	for i in w.size():
		if i > cap:
			w[i] = 0.0
	var s := 0.0
	for x in w: s += float(x)
	for i in w.size():
		w[i] = float(w[i]) * 100.0 / s if s > 0 else 0.0
	# 仅模拟用（--sim-drop-boost，默认空、游戏数据不变）：指定稀有度占比 × 倍数，其余档按比例缩小补足 100%
	if not rarity_boost.is_empty():
		var bs := 0.0; var os := 0.0
		for i in w.size():
			if rarity_boost.has(i): bs += float(w[i]) * float(rarity_boost[i])
			else: os += float(w[i])
		if bs < 100.0 and os > 0.0:
			for i in w.size():
				w[i] = float(w[i]) * float(rarity_boost[i]) if rarity_boost.has(i) else float(w[i]) * (100.0 - bs) / os
	return w

func _pick_weighted(w: Array) -> int:
	var s := 0.0
	for x in w: s += float(x)
	var k := rng.randf() * s
	for i in w.size():
		k -= float(w[i])
		if k < 0.0 and float(w[i]) > 0.0:
			return i
	for i in range(w.size() - 1, -1, -1):
		if float(w[i]) > 0.0:
			return i
	return 0

## 掉落：每只怪独立判定，无保底。pity 参数保留兼容，v1.3 不使用。
func roll_drop(kind: String, region: String, item_level: int, pity: Dictionary, pity_key := "", force := false) -> Array:
	var out: Array = []
	var band := _drop_band(kind, item_level)
	if band.is_empty():
		return out
	if not force and rng.randf() >= float(band.get("any", 0.0)):
		return out
	var n: int = int(band.get("count", 1))
	var w: Array = (band.get("weights", []) as Array).duplicate()
	for i in n:
		var ri: int = _pick_weighted(w)
		out.append(make_item(random_slot(), ri, item_level))
	return out


func _drop_band(kind: String, item_level: int) -> Dictionary:
	var dt: Dictionary = t.get("drop_tables", {})
	if dt.has("by_band"):
		var km: Dictionary = dt.get("kind_map", {})
		var bucket: String = str(km.get(kind, kind))
		if bucket != "normal" and bucket != "elite" and bucket != "boss":
			bucket = "normal"
		var band_name := "below_30" if item_level < 30 else "mid"
		var pack: Dictionary = dt.by_band.get(band_name, {})
		return pack.get(bucket, {})
	# 旧表回退
	if dt.has("by_monster") and dt.by_monster.has(kind):
		var bm: Dictionary = dt.by_monster[kind]
		return {"any": float(bm.get("equip_drop_chance", 0.0)), "count": int(bm.get("count", 1)), "weights": drop_weights(kind, "")}
	return {}

func random_slot() -> String:
	var ok: Array = slots.filter(func(s): return s.get("in_slice", true))
	return ok[rng.randi() % ok.size()].id

## 宝石掉落：返回 [[gem_id, 等级], ...]。Boss 另有 boss_extra_chance 再掉 1 颗；种类按 type_weights
func roll_gems(kind: String, region: String) -> Array:
	var gd: Dictionary = r.gem_drop
	var out: Array = []
	var n := 0
	if rng.randf() < float(gd.chance.get(kind, 0.0)): n += 1
	if kind == "boss" and rng.randf() < float(gd.get("boss_extra_chance", 0.0)): n += 1
	for i in n:
		out.append([pick_gem_type(), gem_drop_level(region)])
	return out

func pick_gem_type() -> String:
	var tw: Dictionary = r.gem_drop.get("type_weights", {})
	var ids: Array = []; var ws: Array = []
	for id in gem_by_id:
		ids.append(id); ws.append(float(tw.get(id, 1.0 if tw.is_empty() else 0.0)))
	return ids[_pick_weighted(ws)]

func gem_drop_level(region: String) -> int:
	var gd: Dictionary = r.gem_drop
	var lr = gd.get("level_by_region", {}).get(region, null)
	if lr != null:
		return rng.randi_range(int(lr[0]), int(lr[1]))
	return int(gd.get("slice_level", gd.get("level", 1)))

# ---------- 生成装备 ----------
func white_base(slot_id: String, level: int) -> Dictionary:
	if v15 != null and v15.loaded:
		return v15.official_white(slot_id, level)
	for row in curve_rows:
		if int(row.item_level) == level and row.has("white_base") and row.white_base.has(slot_id):
			var raw = row.white_base[slot_id]
			var out := {}
			for k in raw:
				out[k] = int(raw[k])
			return out
	var s: Dictionary = slot_by_id[slot_id]
	var src: Dictionary = s.get("base_white_lv10", s.get("base_white_lv5", {}))
	var out := {}
	var scale: float = float(white_weapon_atk(level)) / 32.0
	for k in src:
		if is_pct_key(k) or k in ["crit", "critdmg", "ms", "aspd", "acc", "eva"]:
			out[k] = iround(float(src[k]))
		else:
			out[k] = iround(float(src[k]) * scale)
	return out

func make_item(slot_id: String, ri: int, level: int, wtype := "") -> Dictionary:
	var s: Dictionary = slot_by_id[slot_id]
	var ra := rarity(ri)
	var it := {"uid": next_uid, "slot": slot_id, "rarity": ri, "level": level, "quality": 1.0, "enhance": 0, "xp": 0, "main": {}, "affixes": [], "skills": [], "sockets": [], "special": "", "set_id": "", "wtype": "", "blessing": 0.0}
	next_uid += 1
	if v15 != null and v15.loaded:
		v15.apply_make_item(it, slot_id, ri, level, wtype)
		var ns0: int = int(ra.get("sockets", t.get("sockets_by_rarity", {}).get(ra.name, 0)))
		# 孔数按旧规则，先保持试玩可用
		for i in ns0:
			it.sockets.append(null)
		if slot_id == "weapon" and str(it.get("wtype", "")) == "":
			it.wtype = wtype if wtype != "" else str(r.get("default_weapon_type", "sword"))
		if str(it.get("name", "")) == "":
			it.name = item_name(it)
		return it
	var wb := white_base(slot_id, level)
	for k in wb:
		# 品质倍率乘完四舍五入，无品相随机，避免小数
		it.main[norm_key(k)] = iround(float(wb[k]) * float(ra.mult))
	# 套装：掉落时按概率转成套装，已有职业套（体修、法修）各占一半
	var set_cfg: Dictionary = t.get("sets", {})
	var conv: float = float(set_cfg.get("drop_convert_chance", 0.0))
	if conv > 0.0 and rng.randf() < conv:
		var class_ids: Array = []
		for k in set_cfg.keys():
			var sv = set_cfg[k]
			if typeof(sv) == TYPE_DICTIONARY and sv.has("groups"):
				class_ids.append(str(k))
		if not class_ids.is_empty():
			it.set_id = str(class_ids[rng.randi() % class_ids.size()])
	# 词条数
	var cnt: int = int(ra.get("affix_count", 0))
	var max_skill: int = 1 if it.set_id != "" else 2
	if ri == 0 and slot_id in skill_unlock_slots(0):
		# 白装衣服/武器可出 1 条技能
		if rng.randf() < 0.55:
			cnt = 1
			max_skill = 1
	var stat_pool: Array = []
	for a in s.get("affix_pool", []):
		if affix_by_id.has(a) and _affix_allowed_on_item(affix_by_id[a], slot_id, ri):
			stat_pool.append(a)
	stat_pool.shuffle()
	var skill_pool: Array = []
	if slot_id in skill_unlock_slots(ri) or str(t.get("skill_unlock_by_rarity", {}).get(rarity_name(ri), "")) == "all":
		for sid in s.get("skill_pool", s.get("special_pool", [])):
			var sd0 := skill_def(sid)
			if not sd0.is_empty() and _skill_allowed_on_item(sd0, ri):
				skill_pool.append(sid)
	skill_pool.shuffle()
	var n_skill: int = 0
	var n_stat: int = 0
	# 前 2 条（套装 1 条）优先给技能，其余给属性
	for i in cnt:
		if n_skill < max_skill and not skill_pool.is_empty() and (i < max_skill):
			# 有技能池时，技能条以较高概率出现，保证试玩能见到装备技能
			var want_skill := skill_pool.size() > 0 and (ri == 0 or rng.randf() < 0.7)
			if want_skill:
				var sid: String = skill_pool.pop_back()
				var sd := skill_def(sid)
				var baked: Dictionary = bake_skill(sd, level)
				it.skills.append(baked)
				n_skill += 1
				continue
		if not stat_pool.is_empty():
			var aid: String = stat_pool.pop_back()
			var ad: Dictionary = affix_by_id[aid]
			var key: String = ad.id
			if ad.id == "elem" or ad.id == "res":
				key = "%s_%s" % [ad.id, elements[rng.randi() % elements.size()]]
			# 整数词条：固定值约等于该级白武器的一小部分，百分比为整数
			var val: int
			if ad.get("type", "") == "pct" or is_pct_key(key) or key in ["crit", "critdmg", "ms", "aspd", "acc", "eva"]:
				val = maxi(1, 2 + ri)  # 3%~8% 左右
			elif key == "leech" or key == "skill_leech":
				val = maxi(3, 4 + ri)  # 4%~10%，整数
			else:
				var base_v: int = 1
				if key == "atk":
					base_v = maxi(1, iround(float(white_weapon_atk(level)) * 0.06))
				elif key == "hp":
					base_v = maxi(1, iround(float(white_weapon_atk(level)) * 0.8))
				elif key == "def":
					base_v = maxi(1, iround(float(white_weapon_atk(level)) * 0.05))
				elif key == "regen":
					base_v = maxi(4, iround(float(white_weapon_atk(level)) * 0.45))
				elif key == "hit_heal":
					base_v = maxi(8, iround(float(white_weapon_atk(level)) * 0.50))
				val = base_v
			it.affixes.append({"id": aid, "key": key, "pts": val, "value": val})
			n_stat += 1
	var ns: int = int(ra.get("sockets", t.get("sockets_by_rarity", {}).get(ra.name, 0)))
	for i in ns:
		it.sockets.append(null)
	if slot_id == "weapon":
		it.wtype = wtype if wtype != "" else str(r.get("default_weapon_type", "blade"))
	it.name = item_name(it)
	return it


func _affix_allowed_on_item(ad: Dictionary, slot_id: String, ri: int) -> bool:
	if bool(ad.get("darkgold_weapon_only", false)):
		return ri >= 6 and slot_id == "weapon"
	return true


func _skill_allowed_on_item(sd: Dictionary, ri: int) -> bool:
	if bool(sd.get("darkgold_only", false)):
		return ri >= 6
	return true


func _is_heal_skill(sk: Dictionary) -> bool:
	if str(sk.get("id", "")) == "chengyuan_shu":
		return true
	var typ: String = str(sk.get("runtime", {}).get("type", ""))
	return typ == "heal_pct" or typ == "heal_lowest_pct"


## 仅法杖：保证带上澄源术，不超出该品质技能数上限。不强制噬魄。
func _ensure_staff_chengyuan(it: Dictionary) -> void:
	for sk in it.skills:
		if str(sk.get("id", "")) == "chengyuan_shu":
			return
	var sd := skill_def("chengyuan_shu")
	if sd.is_empty():
		return
	var baked: Dictionary = bake_skill(sd, int(it.get("level", 10)))
	var max_skill: int = 1 if str(it.get("set_id", "")) != "" else 2
	if it.skills.size() < max_skill:
		it.skills.append(baked)
	elif not it.skills.is_empty():
		it.skills[it.skills.size() - 1] = baked
	else:
		it.skills.append(baked)


## 剑/大刀：若随到澄源术等治疗技能，换成武器池里尚未拥有的非治疗技能。
func _replace_heal_skills_with_normal(it: Dictionary) -> void:
	var have := {}
	for sk in it.skills:
		have[str(sk.get("id", ""))] = true
	var replacements: Array = []
	for sid in ["kaishan_yubo", "jinglei_za"]:
		if have.get(sid, false):
			continue
		var sd := skill_def(sid)
		if not sd.is_empty():
			replacements.append(bake_skill(sd, int(it.get("level", 10))))
	var out: Array = []
	var ri := 0
	for sk in it.skills:
		if _is_heal_skill(sk):
			if ri < replacements.size():
				out.append(replacements[ri])
				ri += 1
			# 没有可替换技能时丢掉治疗条，不另造词条
		else:
			out.append(sk)
	it.skills = out


## 开局测试用：按正常 10 级暗金掉落规则生成武器（基础属性、词条、技能、插槽、命名均走 make_item）。
## 只有法杖保证带澄源术；剑和大刀若随到治疗技能则换成非治疗技能。噬魄是否出现完全按暗金词条池投。
## 固定种子保证每次开局三把武器一致，便于试玩对照。
func make_starter_leech_weapon(wtype: String, level := 10, _leech_pct := -1) -> Dictionary:
	var prev_state: int = rng.state
	var seeds := {"sword": 2026112101, "blade": 2026112102, "staff": 2026112103}
	rng.seed = int(seeds.get(wtype, 2026112101))
	var it := make_item("weapon", 6, level, wtype)
	if wtype == "staff":
		_ensure_staff_chengyuan(it)
	else:
		_replace_heal_skills_with_normal(it)
	it["test_leech"] = true
	it["starter_kit"] = "playtest_v15"
	it.name = item_name(it)
	rng.state = prev_state
	return it


## 试玩赠送：橙色苍溟套一件，便于体验套装汲取。
func make_starter_set_piece(slot_id: String, ri := 4, level := 10, set_id := "cangming", force_skill := "") -> Dictionary:
	var prev_state: int = rng.state
	var seeds := {"head": 2026112201, "chest": 2026112202, "legs": 2026112203, "inner": 2026112204, "cloak": 2026112205}
	rng.seed = int(seeds.get(slot_id, 2026112299))
	var it := make_item(slot_id, ri, level)
	it.set_id = set_id
	it["playtest_gift"] = true
	it["starter_kit"] = "playtest_v15"
	if force_skill != "" and v15 != null:
		var baked: Dictionary = v15.pick_exclusive_skill(slot_id, "", ri, force_skill)
		if not baked.is_empty():
			it.skills = [baked]
	it.name = item_name(it)
	rng.state = prev_state
	return it


## 试玩赠送：暗金武器第 5 栏固定生命汲取 3.0%，便于对照套装。
func make_starter_drain_weapon(wtype := "sword", level := 10, drain_pct := 3.0) -> Dictionary:
	var it := make_starter_leech_weapon(wtype, level)
	if v15 != null:
		var drain_ad: Dictionary = v15._affix_by_id("life_drain")
		var row := {"id": "life_drain", "key": "life_drain", "name": "生命汲取", "pts": drain_pct, "value": drain_pct, "is_max": drain_pct >= 5.0, "slot5": true}
		var replaced := false
		for i in it.affixes.size():
			if bool(it.affixes[i].get("slot5", false)) or str(it.affixes[i].get("key", "")) == "life_drain" or i == 4:
				it.affixes[i] = row
				replaced = true
				break
		if not replaced:
			it.affixes.append(row)
	it["playtest_gift"] = true
	it.name = item_name(it)
	return it


func _clamp_points(pts: Array, ids: Array) -> Array:
	# 单条限制在 pts_min~pts_max，超出部分分给其他词条（§5.1）
	for _iter in 6:
		var extra := 0.0; var free: Array = []
		for i in pts.size():
			var a: Dictionary = affix_by_id[ids[i]]
			if pts[i] > float(a.pts_max):
				extra += pts[i] - float(a.pts_max); pts[i] = float(a.pts_max)
			elif pts[i] < float(a.pts_min):
				extra -= float(a.pts_min) - pts[i]; pts[i] = float(a.pts_min)
			else:
				free.append(i)
		if absf(extra) < 0.01 or free.is_empty():
			break
		for i in free:
			pts[i] += extra / free.size()
	for i in pts.size():
		pts[i] = float(roundi(pts[i] * 10.0)) / 10.0
	return pts

func item_name(it: Dictionary) -> String:
	if str(it.get("base_name", "")) != "":
		var plus0: int = int(it.get("enhance", 0))
		return str(it.base_name) + (" +%d" % plus0 if plus0 > 0 else "")
	if v15 != null and v15.loaded:
		var onm: String = v15.official_name(str(it.slot), str(it.get("wtype", "")), int(it.get("level", 1)))
		if onm != "":
			var plus1: int = int(it.get("enhance", 0))
			return onm + (" +%d" % plus1 if plus1 > 0 else "")
	var lst: Array = t.names.by_slot.get(it.slot, [])
	var nm := ""
	for e in lst:
		if rarity_idx.get(e.rarity, -1) == it.rarity:
			nm = e.zh
	if nm == "":
		nm = rarity_name(it.rarity) + slot_by_id[it.slot].name
	var bwt = t.names.get("by_weapon_type", {}).get(it.wtype, null) if it.slot == "weapon" else null
	if bwt != null:
		for e in bwt:
			if rarity_idx.get(e.rarity, -1) == it.rarity:
				nm = e.zh
	elif it.slot == "weapon" and it.wtype != "":
		var def_zh := ""; var new_zh := ""
		for wt in t.names.get("weapon_types", []):
			if wt.id == str(r.default_weapon_type): def_zh = wt.zh
			if wt.id == it.wtype: new_zh = wt.zh
		if def_zh != "" and new_zh != "" and nm.ends_with(def_zh):
			nm = nm.trim_suffix(def_zh) + new_zh
	if str(it.get("set_id", "")) == "tixiu":
		if not nm.ends_with("（体修）"):
			nm = nm + "（体修）"
	elif it.set_id != "":
		var sets_v = t.get("sets", {})
		if typeof(sets_v) == TYPE_ARRAY:
			for st in sets_v:
				if st.set_id == it.set_id:
					nm = "【%s】%s" % [st.name_zh, nm]
		elif typeof(sets_v) == TYPE_DICTIONARY and sets_v.has(it.set_id):
			nm = nm + "（%s）" % sets_v[it.set_id].get("class", it.set_id)
	return nm

func weapon_type_name(id: String) -> String:
	for wt in t.names.get("weapon_types", []):
		if wt.id == id: return wt.zh
	return id

# ---------- 属性 ----------
## 一件装备提供的属性（含强化、宝石）
func item_stats(it: Dictionary) -> Dictionary:
	var out := {}
	var plus: int = int(it.get("enhance", 0))
	var lv: int = int(it.get("level", 1))
	var add: int = enhance_total_atk(lv, plus)
	var watk: int = maxi(1, white_weapon_atk(lv))
	for k in it.main:
		var base_v: int = iround(float(it.main[k]))
		var extra: int = 0
		if plus > 0:
			if k == "atk":
				extra = iround(float(add) * float(white_base(it.slot, lv).get("atk", 0)) / float(watk)) if it.slot != "weapon" else add
				if it.slot == "weapon":
					extra = add
			elif k == "hp":
				extra = iround(float(add) * 496.0 / 22.0 * float(white_base(it.slot, lv).get("hp", 0)) / maxf(1.0, 108.0 * float(watk) / 32.0))
				# 更直观：生命部位按「该部位白装生命 / 白武器攻击」折算
				extra = iround(float(add) * float(white_base(it.slot, lv).get("hp", 0)) / float(watk))
			elif k == "def":
				extra = iround(float(add) * float(white_base(it.slot, lv).get("def", 0)) / float(watk))
		out[k] = int(out.get(k, 0)) + base_v + extra
	for a in it.affixes:
		out[a.key] = float(out.get(a.key, 0)) + float(a.value)
	var cat: String = slot_by_id[it.slot].get("category", "")
	for gm in it.sockets:
		if gm == null:
			continue
		var gk := gem_stat(gm.id, cat)
		var glev: int = int(gm.get("lv", lv))
		# v1.3：一颗攻击石 = 石头等级对应白武器 10%；生命/防御按比例
		var flat: int = gem_flat_atk(glev)
		if gk == "hp":
			flat = maxi(1, iround(float(flat) * 496.0 / 38.0))
		elif gk == "def":
			flat = maxi(1, iround(float(flat) * 29.7 / 38.0))
		elif is_pct_key(gk) or str(gk).begins_with("res_") or str(gk).begins_with("elem_"):
			flat = maxi(1, iround(float(flat) * 0.15))
		out[gk] = int(out.get(gk, 0)) + flat
	# 平坦属性取整，百分比和汲取保留一位小数
	for k in out:
		if is_pct_key(str(k)) or str(k) == "life_drain":
			out[k] = float(out[k])
		else:
			out[k] = int(iround(float(out[k])))
	return out

## 宝石加什么：数值石按 stat 名对上词条；属性石镶武器/饰品加属性伤害，镶防具加抗性（§6.2）
func gem_stat(gid: String, category: String) -> String:
	var gd: Dictionary = gem_by_id[gid]
	if affix_by_name.has(gd.stat):
		return affix_by_name[gd.stat].id
	for e in elements:
		if gid.ends_with(e):
			return ("res_" if category == "防具" else "elem_") + e
	return gd.stat

func gem_value(gid: String, lv: int, category: String) -> float:
	var gd: Dictionary = gem_by_id[gid]
	var arr: Array = gd.levels
	if gem_stat(gid, category).begins_with("res_") and gd.has("res_levels"):
		arr = gd.res_levels
	return float(arr[clampi(lv - 1, 0, arr.size() - 1)])

func gem_max_level(gid: String) -> int:
	return (gem_by_id[gid].levels as Array).size()

## 英雄总属性。equip: slot_id -> item 或 null
func hero_stats(equip: Dictionary, level: int) -> Dictionary:
	var hb := hero_base_row(level)
	var sum := {}
	for sid in equip:
		var it = equip[sid]
		if it == null:
			continue
		var st := item_stats(it)
		for k in st:
			sum[k] = sum.get(k, 0.0) + st[k]
	var cr: Dictionary = r.get("crit", {})
	var o := {}
	# 百分比线性加算在裸属性上，不连乘，不设装备侧上限
	var bare_atk: float = float(hb.atk) + sum.get("atk", 0.0)
	var bare_hp: float = float(hb.hp) + sum.get("hp", 0.0)
	var bare_def: float = float(hb.def) + sum.get("def", 0.0)
	o.atk = iround(bare_atk * (1.0 + sum.get("atk_pct", 0.0) / 100.0))
	o.hp = iround(bare_hp * (1.0 + sum.get("hp_pct", 0.0) / 100.0))
	o.def = iround(bare_def * (1.0 + sum.get("def_pct", 0.0) / 100.0))
	o.aspd = float(sum.get("aspd", 0.0))
	o.ms = float(sum.get("ms", 0.0))
	o.crit = float(hb.get("crit_rate_pct", cr.get("base_rate_pct", 5))) + sum.get("crit", 0.0)
	o.critdmg = float(hb.get("crit_dmg_pct", cr.get("base_dmg_pct", 150))) + sum.get("critdmg", 0.0)
	o.acc = float(hb.get("acc_pct", 0.0)) + sum.get("acc", 0.0)
	o.eva = float(hb.get("eva_pct", 0.0)) + sum.get("eva", 0.0)
	o.skill = sum.get("skill", 0.0)
	o.regen = sum.get("regen", 0.0)
	o.crit_res = float(hb.get("crit_res", 0.0)) + sum.get("crit_res", 0.0)
	o.crit_def = float(hb.get("crit_def", 0.0)) + sum.get("crit_def", 0.0)
	o.dmg_pct = float(sum.get("dmg_pct", 0.0))
	o.elite_dmg = float(sum.get("elite_dmg", 0.0))
	o.boss_dmg = float(sum.get("boss_dmg", 0.0))
	o.def_pen = float(sum.get("def_pen", 0.0))
	o.ele_pen = float(sum.get("ele_pen", 0.0))
	o.dr_pct = float(sum.get("dr_pct", 0.0))
	o.heal_bonus = float(sum.get("heal_bonus", 0.0))
	o.stun_res = float(sum.get("stun_res", 0.0))
	o.cdr = float(sum.get("cdr", 0.0))
	o.life_drain = float(sum.get("life_drain", 0.0))
	for e in elements:
		o["elem_" + e] = sum.get("elem_" + e, 0.0)
		o["res_" + e] = float(hb.get("res_pct", {}).get(e, 0.0)) + sum.get("res_" + e, 0.0) + sum.get("all_elem_res", 0.0)
	# 特效：同名不叠加，只取最强一件（按稀有度 special_scale）
	var sp := {}
	for sid in equip:
		var it = equip[sid]
		if it != null and it.special != "":
			var sc: float = float(rarity(it.rarity).get("special_scale", 1.0))
			if sc > float(sp.get(it.special, 0.0)):
				sp[it.special] = sc
	o.specials = sp
	var tot := 0
	for sid in equip:
		if equip[sid] != null:
			tot += int(equip[sid].enhance)
	o.enhance_total = tot
	o.fx_tier = fx_tier(tot)
	var skills: Array = []
	for sid in equip:
		var it2 = equip[sid]
		if it2 != null:
			for sk in it2.get("skills", []):
				skills.append(sk)
	o.gear_skills = skills
	o.set_bonus = _set_bonus(equip)
	var sb: Dictionary = o.set_bonus.get("stats", {})
	if not sb.is_empty():
		# 套装百分比同样线性加在裸属性上
		o.atk = iround(bare_atk * (1.0 + (sum.get("atk_pct", 0.0) + float(sb.get("atk_pct", 0))) / 100.0))
		o.hp = iround(bare_hp * (1.0 + (sum.get("hp_pct", 0.0) + float(sb.get("hp_pct", 0))) / 100.0))
		o.def = iround(bare_def * (1.0 + (sum.get("def_pct", 0.0) + float(sb.get("def_pct", 0))) / 100.0))
		o.regen = float(o.regen) + float(sb.get("regen", 0))
	o.leech = 0
	o.skill_leech = 0
	o.hit_heal = 0
	o.life_drain = float(o.get("life_drain", 0.0)) + float(o.set_bonus.get("life_drain", 0.0))
	var att := {"elem": "", "p": 0.0, "s": 0.0}
	if v15 != null and v15.loaded:
		att = v15.attached_element_of(o, equip)
	o.attached_elem = str(att.get("elem", ""))
	o.elem_p = float(att.get("p", 0.0))
	if o.attached_elem != "":
		o["elem_" + o.attached_elem] = float(o.get("elem_" + o.attached_elem, 0.0)) + float(att.get("s", 0.0))
	return o


func _set_bonus(equip: Dictionary) -> Dictionary:
	if v15 != null and v15.loaded:
		return v15.set_bonus(equip)
	var out := {"groups": {}, "stats": {}, "triggers": [], "leech": 0, "skill_leech": 0, "hit_heal": 0, "life_drain": 0.0}
	var set_ids: Dictionary = {}
	for sid in equip:
		var it0 = equip[sid]
		if it0 != null and str(it0.get("set_id", "")) != "":
			set_ids[str(it0.set_id)] = true
	for set_id in set_ids.keys():
		var pack_root: Dictionary = t.get("sets", {}).get(set_id, {})
		var groups: Dictionary = pack_root.get("groups", {})
		for g in groups:
			var gdef: Dictionary = groups[g]
			var slots: Array = gdef.get("slots", [])
			var pieces: Array = []
			for sid in slots:
				var it = equip.get(str(sid), null)
				if it != null and str(it.get("set_id", "")) == set_id:
					pieces.append(it)
			pieces.sort_custom(func(a, b): return int(a.rarity) > int(b.rarity))
			var n: int = pieces.size()
			var got: Array = []
			for b in gdef.get("breaks", []):
				if n >= int(b):
					got.append(int(b))
			out.groups["%s:%s" % [set_id, g]] = {"count": n, "breaks": got, "set_id": set_id}
			var bonus: Dictionary = gdef.get("bonus", {})
			for b in got:
				var defn = bonus.get(str(int(b)), {})
				if defn.is_empty():
					defn = bonus.get(str(b), {})
				if defn.is_empty():
					continue
				var nth: int = mini(int(b), pieces.size()) - 1
				var rq: int = int(pieces[nth].rarity) if nth >= 0 else 0
				var typ: String = str(defn.get("type", ""))
				if typ == "stat":
					var k: String = str(defn.get("stat", "atk_pct"))
					out.stats[k] = int(out.stats.get(k, 0)) + int(defn.get("value", 0))
				elif typ == "on_hit_lifesteal":
					out.leech = int(out.leech) + int(defn.get("value", 0))
				elif typ == "skill_lifesteal":
					out.skill_leech = int(out.skill_leech) + int(defn.get("value", 0))
				elif typ == "on_hit_heal":
					var lv_ref: int = 10
					if not pieces.is_empty():
						lv_ref = int(pieces[0].get("level", 10))
					var hv: int = maxi(int(defn.get("value", 0)), iround(float(white_weapon_atk(lv_ref)) * 0.40))
					out.hit_heal = int(out.hit_heal) + hv
					if defn.has("lifesteal"):
						out.leech = int(out.leech) + int(defn.get("lifesteal", 0))
				else:
					var ch: Array = defn.get("chance_by_rarity", [])
					var chance: int = 100
					if not ch.is_empty():
						chance = int(ch[clampi(rq, 0, ch.size() - 1)])
					out.triggers.append({"group": g, "break": b, "def": defn, "chance": chance, "rarity": rq, "set_id": set_id})
	return out

const SHOW_KEYS := ["hp", "atk", "def", "aspd", "ms", "crit", "critdmg", "crit_res", "acc", "eva", "skill", "regen", "life_drain", "dmg_pct", "elite_dmg", "boss_dmg"]

func total_keys() -> Array:
	var ks: Array = SHOW_KEYS.duplicate()
	for e in elements:
		ks.append("elem_" + e)
	for e in elements:
		ks.append("res_" + e)
	return ks

func fmt_val(k: String, v: float) -> String:
	var pct := is_pct_key(k)
	if k == "life_drain" or (pct and absf(v - float(iround(v))) > 0.04):
		return "%.1f%%" % v
	if pct:
		return "%d%%" % iround(v)
	return str(iround(v))

# ---------- 伤害公式（§1.1） ----------
## src/tgt 需要字段：atk def level acc eva crit critdmg skill_pct elem{} res{} stacks{} hit_down
func compute_damage(src, tgt, mult: float, is_skill: bool) -> Dictionary:
	if v15 != null and v15.loaded:
		return v15.compute_damage(src, tgt, mult, is_skill)
	var h: Dictionary = r.hit
	var ld: float = float(src.level - tgt.level)
	var shadow: float = float(src.stacks.get("shadow", 0))
	var hit_rate: float = clampf(float(h.base) + src.acc / 100.0 - tgt.eva / 100.0 - shadow * float(h.shadow_per_stack) - src.hit_down + ld * float(h.per_level_diff), float(h.min), float(h.max))
	if rng.randf() >= hit_rate:
		return {"hit": false, "dmg": 0.0, "crit": false, "rate": hit_rate}
	var atk_i: int = iround(float(src.atk) * mult)
	var def_i: int = iround(float(tgt.def))
	var floor_r: float = float(t.get("combat_v13", {}).get("dmg_floor", 0.45))
	var phys: int = maxi(1, maxi(iround(float(atk_i) * floor_r), atk_i - def_i))
	var el := 0
	for e in src.elem:
		var ev: float = src.elem[e]
		if ev > 0.0:
			el += iround(ev * mult * (1.0 - float(tgt.res.get(e, 0.0)) / 100.0))
	var crit: bool = rng.randf() < src.crit / 100.0
	var cm: float = src.critdmg / 100.0 if crit else 1.0
	var inc: float = 1.0 + (src.skill_pct / 100.0 if is_skill else 0.0)
	var shock: float = 1.0 + float(r.elements.lightning.dmg_taken_per_stack) * float(tgt.stacks.get("lightning", 0))
	var dmg: int = maxi(1, iround(float(phys + el) * cm * inc * shock))
	return {"hit": true, "dmg": dmg, "crit": crit, "rate": hit_rate, "defred": 0.0}


func inherent_xp(it: Dictionary) -> int:
	var tab: Array = t.get("advance", {}).get("inherent_xp_by_rarity", [8, 12, 18, 28, 42, 60, 0])
	var ri: int = int(it.get("rarity", 0))
	return int(tab[clampi(ri, 0, tab.size() - 1)]) + int(it.get("xp", 0))


## 吞噬：同部位。材料的进阶经验加到目标，强化和石头不跟着走（石头消失）。
func devour(dst: Dictionary, src: Dictionary) -> Dictionary:
	if str(dst.slot) != str(src.slot):
		return {"ok": false, "msg": "只能吞噬同一部位"}
	if int(dst.rarity) >= 6:
		return {"ok": false, "msg": "暗金只能掉落，不能再升品阶"}
	if int(dst.rarity) >= 5 and int(src.rarity) < 5:
		# 红是可刷上限，继续吃只加经验但不能升暗金
		pass
	var got: int = inherent_xp(src)
	dst.xp = int(dst.get("xp", 0)) + got
	var bar: int = int(t.get("advance", {}).get("bar_xp", 100))
	var ups: int = 0
	var unlocked: Array = []
	while int(dst.rarity) < 5 and int(dst.xp) >= bar:
		dst.xp = int(dst.xp) - bar
		dst.rarity = int(dst.rarity) + 1
		ups += 1
		# 升品：底子略增，解锁新词条（重随解锁的那一条）
		var wb := white_base(dst.slot, int(dst.level))
		var ra := rarity(int(dst.rarity))
		for k in wb:
			dst.main[norm_key(k)] = iround(float(wb[k]) * float(ra.mult))
		# 孔数增加到新品阶
		var ns: int = int(ra.get("sockets", 0))
		while dst.sockets.size() < ns:
			dst.sockets.append(null)
		unlocked.append(rarity_name(int(dst.rarity)))
	if v15 != null and v15.loaded:
		v15.refresh_item_on_upgrade(dst)
	dst.name = item_name(dst)
	return {"ok": true, "xp_gained": got, "upgrades": ups, "unlocked": unlocked, "gems_destroyed": _socketed_count(src)}


func _socketed_count(it: Dictionary) -> int:
	var n := 0
	for gm in it.get("sockets", []):
		if gm != null:
			n += 1
	return n
