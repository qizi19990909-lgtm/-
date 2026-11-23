extends SceneTree
## 无界面掉落测试：godot --headless --path . -s res://tools/drop_test.gd
## 每种怪 1000 次击杀（看掉率）+ 1000 次必掉（看稀有度分布），对照《装备数值表》青石村区域表；
## 同时检查：不出紫以上、词条条数/点数/禁出、孔数、品相范围、Boss 保底、强化门槛与曲线。
const EquipDB := preload("res://scripts/equip_db.gd")
const N := 1000

func _init() -> void:
	var db = EquipDB.new()
	db.load_tables()
	var region: String = db.r.region
	var out := PackedStringArray()
	var fails := 0
	out.append("掉落测试  表版本 v%s  区域 %s  每种怪 %d 次" % [db.t.version, region, N])
	var cap: int = db.rarity_idx[db.region_row(region).get("max_rarity", "暗金")]
	for kind in ["normal", "elite", "boss"]:
		var bm: Dictionary = db.t.drop_tables.by_monster[kind]
		# 1) 掉率：1000 次击杀
		var n_items := 0; var n_kills_with := 0
		for i in N:
			var its: Array = db.roll_drop(kind, region, 5, {}, "")
			n_items += its.size()
			if not its.is_empty(): n_kills_with += 1
		var exp_rate: float = float(bm.equip_drop_chance)
		var obs_rate: float = float(n_kills_with) / N
		var se: float = sqrt(maxf(exp_rate * (1.0 - exp_rate), 1e-9) / N)
		var ok_rate: bool = absf(obs_rate - exp_rate) <= 4.0 * se + 1e-9
		out.append("\n[%s] 掉率 期望 %.1f%% 实测 %.1f%%（%d 件）%s" % [bm.name, exp_rate * 100, obs_rate * 100, n_items, "OK" if ok_rate else "FAIL"])
		if not ok_rate: fails += 1
		# 2) 稀有度分布：1000 次必掉
		var w: Array = db.drop_weights(kind, region)
		var cnt := []; cnt.resize(db.rarities.size()); cnt.fill(0)
		var total := 0
		for i in N:
			for it in db.roll_drop(kind, region, 5, {}, "", true):
				cnt[it.rarity] += 1; total += 1
				fails += _check_item(db, it, out)
		var line := "  稀有度  期望% / 实测%："
		var worst := 0.0
		for ri in db.rarities.size():
			var e: float = float(w[ri]) / 100.0
			var o: float = float(cnt[ri]) / total
			var s2: float = sqrt(maxf(e * (1.0 - e), 1e-9) / total)
			worst = maxf(worst, absf(o - e) / maxf(s2, 1e-9) if e > 0 else (999.0 if cnt[ri] > 0 else 0.0))
			line += " %s %.1f/%.1f" % [db.rarity_name(ri), e * 100, o * 100]
		out.append(line)
		var above := 0
		for ri in range(cap + 1, db.rarities.size()): above += cnt[ri]
		out.append("  最大偏差 %.2fσ（<4σ 视为符合）  高于%s的件数 %d  %s" % [worst, db.rarity_name(cap), above, "OK" if worst < 4.0 and above == 0 else "FAIL"])
		if worst >= 4.0 or above > 0: fails += 1
	# 3) Boss 保底：连续未出紫的次数不超过 after_misses
	var pity := {}; var run := 0; var max_run := 0; var forced_ok := true
	var pmin: int = db.rarity_idx[db.r.pity.min_rarity]
	for i in N:
		var before: int = int(pity.get("b", 0))
		var its: Array = db.roll_drop("boss", region, 10, pity, "b")
		var hi := -1
		for it in its: hi = maxi(hi, int(it.rarity))
		if before >= int(db.r.pity.after_misses) and hi < pmin: forced_ok = false
		run = 0 if hi >= pmin else run + 1
		max_run = maxi(max_run, run)
	out.append("\n[Boss 保底] 连续未出%s最多 %d 次（规则 ≤ %d）%s" % [db.r.pity.min_rarity, max_run, int(db.r.pity.after_misses), "OK" if max_run <= int(db.r.pity.after_misses) and forced_ok else "FAIL"])
	if max_run > int(db.r.pity.after_misses) or not forced_ok: fails += 1
	# 4) 强化
	out.append("\n[强化] 方案 %s  单件上限 +%d  全身上限 %d  特效门槛 %s（来源 %s）" % [db.profile_key, db.item_cap, db.total_cap, str(db.fx_thresholds.map(func(x): return int(x))), db.fx_source])
	var cl := "  曲线累计%："
	for lv in range(1, db.item_cap + 1): cl += " +%d=%.1f" % [lv, db.enhance_cum_pct(lv)]
	out.append(cl)
	var ths: Array = db.fx_thresholds.map(func(x): return int(x))
	if db.profile_key == "slice" and (db.item_cap != 10 or ths != [21, 61, 75, 91]):
		out.append("  FAIL：试玩版应为 +10 与 21/61/75/91"); fails += 1
	# 切到正式版方案（只改一个配置键）
	var db2 = EquipDB.new(); db2.load_tables(); db2.r.enhance_profile = "formal"; db2.warnings.clear(); db2._load_enhance()
	out.append("  切换 enhance_profile=formal → 单件 +%d  全身 %d  门槛 %s（来源 %s）" % [db2.item_cap, db2.total_cap, str(db2.fx_thresholds.map(func(x): return int(x))), db2.fx_source])
	# 字段缺失时的兜底：删掉 profiles 与 *_fx_thresholds，只剩 slice_item_cap + thresholds_ratio
	var db3 = EquipDB.new(); db3.load_tables()
	var e3: Dictionary = db3.t.enhance
	e3.erase("profiles"); e3.erase("slice_fx_thresholds"); e3.erase("fx_thresholds")
	db3.warnings.clear(); db3._load_enhance()
	out.append("  兜底（无 profiles / 门槛字段）→ 单件 +%d  全身 %d  门槛 %s（来源 %s）" % [db3.item_cap, db3.total_cap, str(db3.fx_thresholds.map(func(x): return int(x))), db3.fx_source])
	if db3.fx_thresholds.map(func(x): return int(x)) != [21, 61, 75, 91]:
		out.append("  FAIL：兜底门槛不对"); fails += 1
	# 5) v0.4 强化成功率 / 失败规则 / 祝福 / 消耗
	var rl := "  成功率（%s）：" % db.profile_key
	for lv in db.item_cap: rl += " +%d→%d%%" % [lv, int(round(db.enhance_success_rate(lv) * 100))]
	out.append(rl)
	var nodrop := true
	for lv in db.item_cap:
		if db.enhance_fail_level(lv) != lv: nodrop = false
	out.append("  试玩版 +0~+%d 失败不掉级：%s；正式版 +16 失败 → +%d、+20 失败 → +%d（fail_drop/safe_floor）" % [db.item_cap - 1, "OK" if nodrop else "FAIL", db.enhance_fail_level(16), db.enhance_fail_level(20)])
	if not nodrop: fails += 1
	out.append("  祝福：每次失败 +%.0f%%，+9 基础 %d%% → 失败 2 次后 %d%%；+9 白 10 级消耗 %s" % [db.blessing_per_fail() * 100, int(round(db.enhance_success_rate(9) * 100)), int(round(db.enhance_success_rate(9, 2 * db.blessing_per_fail()) * 100)), str(db.enhance_cost({"enhance": 9, "level": 10}))])
	# 6) v0.4 宝石掉落：每种怪 1000 次
	for kind in ["normal", "elite", "boss"]:
		var ng := 0; var tc := {}
		for i in N:
			for gl in db.roll_gems(kind, region):
				ng += 1; tc[gl[0]] = int(tc.get(gl[0], 0)) + 1
		var gd: Dictionary = db.r.gem_drop
		var expv: float = float(gd.chance[kind]) + (float(gd.get("boss_extra_chance", 0.0)) if kind == "boss" else 0.0)
		var ok_g: bool = absf(float(ng) / N - expv) <= 4.0 * sqrt(maxf(expv, 0.01) / N) + 0.01
		out.append("[宝石 %s] 期望每只 %.2f 颗 实测 %.3f 颗 %s  种类分布 %s" % [kind, expv, float(ng) / N, "OK" if ok_g else "FAIL", str(tc)])
		if not ok_g: fails += 1
	# 7) 参数来源（v0.4 覆盖占位）
	var srcs := "\n[参数来源]"
	for k in db.param_source: srcs += "\n  %s ← %s" % [k, db.param_source[k]]
	out.append(srcs)
	for wmsg in db.warnings: out.append("  警告：" + wmsg)
	out.append("\n结论：%s（失败项 %d）" % ["全部通过" if fails == 0 else "有失败", fails])
	var txt := "\n".join(out)
	print(txt)
	var f := FileAccess.open("res://tools/drop_test_result.txt", FileAccess.WRITE)
	if f: f.store_string(txt + "\n")
	quit(0 if fails == 0 else 1)

var _err_shown := 0
func _check_item(db, it: Dictionary, out: PackedStringArray) -> int:
	var ra: Dictionary = db.rarity(it.rarity)
	var s: Dictionary = db.slot_by_id[it.slot]
	var errs: Array = []
	var na: int = it.affixes.size()
	var want: int = int(ra.affix_count)
	if not (na == want or (want == 0 and na <= 1 and float(ra.affix_chance) > 0)):
		errs.append("词条数 %d≠%d" % [na, want])
	for a in it.affixes:
		if a.id in s.get("affix_forbidden", []): errs.append("禁出词条 " + a.id)
		var ad: Dictionary = db.affix_by_id[a.id]
		if a.pts < float(ad.pts_min) - 0.11 or a.pts > float(ad.pts_max) + 0.11: errs.append("点数越界 %s %.1f" % [a.id, a.pts])
	if it.sockets.size() != int(ra.sockets): errs.append("孔数")
	var q: Array = db.r.quality_range
	if it.quality < float(q[0]) or it.quality > float(q[1]): errs.append("品相")
	if not errs.is_empty() and _err_shown < 10:
		_err_shown += 1
		out.append("  物品错误 %s：%s" % [it.name, ", ".join(errs)])
	return 0 if errs.is_empty() else 1
