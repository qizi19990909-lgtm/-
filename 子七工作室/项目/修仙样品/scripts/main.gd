extends Node2D
## 修仙小队样品：主控（地图、波次、输入、HUD、装备面板、自测）。

const UiScale := preload("res://scripts/ui_scale.gd")
const UnitScript := preload("res://scripts/unit.gd")
const ProjScript := preload("res://scripts/projectile.gd")
const EquipDB := preload("res://scripts/equip_db.gd")
const LootScript := preload("res://scripts/loot.gd")
const BagUI := preload("res://scripts/inventory_ui.gd")
const SAVE_PATH := "user://save_equip_v13.json"
const FIELD := Rect2(40, 250, 1200, 380)   # 可走区域

var cfg := {}
var font: Font
var warrior_frames: SpriteFrames
var warrior_size := Vector2.ONE
var warrior_weapon_frames: SpriteFrames   # 战士武器层（与身体同帧）
const WEAPON_PAD := 24.0                  # 武器层图片四周留边，见 tools/extract_weapon_layers.py
# 剑修（战士）七品阶外观：每档整身图 + 剑层，见 assets/swordsman_tiers/ 和 scripts/swordsman_rig.gd
var sw_tex := {}                         # "front_body"/"front_sword"/"side_body"/"side_sword" -> 7 张贴图
var sw_body: Array = []                  # 兼容：非空表示剑修贴图已加载
var sw_meta := {}
var fx_dot_tex: Texture2D                # 特效用的软圆点
var fx_star_tex: Texture2D               # 特效用的四角闪光
var world: Node2D
var fx_layer: Node2D
var units: Array = []
var wave_idx := -1
var wave_timer := 1.0
var state := "playing"     # playing / win / lose
var selected = null
var autotest := false
var elapsed := 0.0
var shots := 0

# HUD
var hud: CanvasLayer
var wave_label: Label
var banner: Label
var banner_t := 0.0
var hint_label: Label
var result_panel: Panel
var result_label: Label
var portrait_btns := []
# 装备系统
var db                       # scripts/equip_db.gd
var bag: Array = []          # 背包里的装备（已穿戴的不在这里）
var gems := {}               # "gem_id:等级" -> 数量
var pity := {}               # Boss 保底计数
var region := "青石村"
var pending_spawn: Array = []   # 同屏上限：还没刷出来的 [kind, wave]
var spawn_cd := 0.0
var wave_times: Array = []       # 每波用时（秒）
var cleared_set := {}            # 本局打完的波次下标
var max_wave := 1                # 已解锁的最高波次（打到过的，1 起），随存档保存
var boss_killed := false         # 头目真正被击杀过（存档）；没杀过时挑战波不解锁、不出「再来一波」
var start_panel: Panel
var start_entry: VBoxContainer
var start_modes: VBoxContainer
var start_campaign: VBoxContainer
var endless := false
var endless_wave := 0
var endless_best := 0
var farm_hint: Label
var retry_box: HFlowContainer
var retry_btn: Button
var retry_first_btn: Button
var mode_select_btn: Button
# 难度模拟「重打战役」：输了从最高波次重打、自动换装，统计打到首杀头目 / 通关挑战波要几局
var camp_attempts := 1
var _sim_boost := {}             # 仅模拟：--sim-drop-boost=3 → 前 3 波蓝/紫掉落占比 ×2（不写进配置）
var _sim_boost_waves := 0
var camp_boss := {}
var camp_ch := {}
var silver := 0                  # 绑银（出售所得 + 怪物 bind_silver）
var bag_full_t := 0.0
var farm_loops := 0          # 刷怪轮数（胜利后「再来一波」）
var bag_ui: Control
var bag_btn: Button
var debug_panel: VBoxContainer
var farm_btn: Button
var drop_log: Array = []     # 自测用：本局掉落记录
var play_kills := {"normal": 0, "elite": 0, "boss": 0}
var play_drops := {"白": 0, "绿": 0, "蓝": 0, "紫": 0, "橙": 0, "红": 0, "暗金": 0}
var play_stats_lbl: Label
var no_save := false
var sim_preset := ""        # 无界面难度模拟：--sim=white / mixed / purple10（见 tools/sim_difficulty.py）

func _ready() -> void:
	randomize()
	autotest = "--autotest" in OS.get_cmdline_user_args()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sim="):
			sim_preset = a.substr(6)
		if a.begins_with("--sim-drop-boost="):
			_sim_boost_waves = int(a.substr(17))
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/config.json"))
	font = load("res://assets/fonts/NotoSansSC-Subset.otf")
	db = EquipDB.new()
	db.load_tables()
	if _sim_boost_waves > 0:
		_sim_boost = {int(db.rarity_idx["蓝"]): 2.0, int(db.rarity_idx["紫"]): 2.0}
	region = str(db.r.get("region", region))
	for w in db.warnings:
		push_warning(w)
	no_save = autotest or sim_preset != "" or "--nosave" in OS.get_cmdline_user_args() or "--shot-tooltip" in OS.get_cmdline_user_args()
	_load_swordsman_tiers()
	world = Node2D.new(); world.y_sort_enabled = true; add_child(world)
	fx_layer = Node2D.new(); fx_layer.z_index = 10; add_child(fx_layer)
	_build_hud()
	var starts := [Vector2(600, 430), Vector2(500, 360), Vector2(500, 500)]
	for i in cfg.heroes.size():
		var u = UnitScript.new()
		world.add_child(u)
		u.position = starts[i]
		u.setup_hero(cfg.heroes[i], self)
		units.append(u)
	if no_save or not _load_game():
		_new_game()
	if sim_preset != "":
		_apply_sim_gear(sim_preset)
	elif autotest:
		# 自测要跑完 5 波 + 挑战波 + 再来一波，开局白装（v0.4 starter_gear 只有 3 件 1 级）打不过第 2 波，所以自测用全紫 +10
		_apply_sim_gear("purple10")
	_bag_badge()
	_select(units[0])
	if "--test-retry" in OS.get_cmdline_user_args() and not Engine.has_meta("retry_tested"):
		Engine.set_meta("retry_tested", true)
		max_wave = 3; bag.append(db.make_item("ring", 2, 10, ""))
		print("RETRYTEST before: max_wave=%d bag=%d" % [max_wave, bag.size()])
		retry_from.call_deferred(3)
		return
	if Engine.has_meta("retry_from"):
		var n: int = int(Engine.get_meta("retry_from"))
		if "--test-retry" in OS.get_cmdline_user_args():
			print("RETRYTEST after reload: max_wave=%d bag=%d hp=%s start=%d" % [max_wave, bag.size(), str(heroes().map(func(h): return "%d/%d" % [int(h.hp), int(h.max_hp)])), n])
			get_tree().quit.call_deferred()
		Engine.remove_meta("retry_from")
		_start_at(n)
		_show_banner("从第 %d 波重打" % n)
	elif Engine.has_meta("retry_endless"):
		Engine.remove_meta("retry_endless")
		_start_endless()
	elif Engine.has_meta("open_mode_select"):
		Engine.remove_meta("open_mode_select")
		_show_start_panel("modes")
	elif sim_preset == "" and not autotest and not ("--shot-starter" in OS.get_cmdline_user_args()) and not ("--shot-tooltip" in OS.get_cmdline_user_args()) and not ("--shot-retry" in OS.get_cmdline_user_args()) and not ("--shot-free-equip" in OS.get_cmdline_user_args()) and not ("--test-clean-defeat" in OS.get_cmdline_user_args()):
		_show_start_panel()
	if autotest:
		Engine.time_scale = 3.0
		print("AUTOTEST start")
	if "--shot-starter" in OS.get_cmdline_user_args():
		_shot_starter()
	if "--shot-retry" in OS.get_cmdline_user_args():
		_shot_retry()
	if "--shot-free-equip" in OS.get_cmdline_user_args():
		_shot_free_equip()
	if "--shot-tooltip" in OS.get_cmdline_user_args():
		_shot_tooltip()
	if "--test-clean-defeat" in OS.get_cmdline_user_args():
		Engine.time_scale = 4.0
		if start_panel.visible: _start_at(max_wave)

func _load_warrior_frames() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/warrior/frames.json"))
	warrior_size = Vector2(meta._size[0], meta._size[1])
	warrior_frames = SpriteFrames.new()
	warrior_frames.remove_animation("default")
	for anim in ["idle", "run", "attack", "hit", "death"]:
		warrior_frames.add_animation(anim)
		var durs: Array = meta[anim]
		var avg := 0.0
		for d in durs: avg += d
		avg /= durs.size()
		warrior_frames.set_animation_speed(anim, 1000.0 / avg)
		warrior_frames.set_animation_loop(anim, anim == "idle" or anim == "run")
		for i in durs.size():
			warrior_frames.add_frame(anim, load("res://assets/warrior/%s_%d.png" % [anim, i]), durs[i] / avg)
	warrior_weapon_frames = SpriteFrames.new()
	warrior_weapon_frames.remove_animation("default")
	for anim in ["idle", "run", "attack", "hit", "death"]:
		warrior_weapon_frames.add_animation(anim)
		warrior_weapon_frames.set_animation_loop(anim, false)
		for i in (meta[anim] as Array).size():
			warrior_weapon_frames.add_frame(anim, load("res://assets/warrior/weapon/%s_%d.png" % [anim, i]))
	warrior_frames.set_animation_speed("attack", warrior_frames.get_animation_speed("attack") * 1.6)
	warrior_frames.set_animation_speed("hit", warrior_frames.get_animation_speed("hit") * 1.5)

func _load_swordsman_tiers() -> void:
	sw_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/swordsman_tiers/meta.json"))
	for v in ["front", "side"]:
		for kind in ["body", "sword"]:
			var arr := []
			for i in sw_meta[v].size():
				arr.append(load("res://assets/swordsman_tiers/%s_%s_%d.png" % [v, kind, i]))
			sw_tex[v + "_" + kind] = arr
	sw_body = sw_tex.side_body
	# 特效贴图用代码生成（不占素材）
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var dot := GradientTexture2D.new()
	dot.gradient = g; dot.width = 48; dot.height = 48
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5); dot.fill_to = Vector2(1.0, 0.5)
	fx_dot_tex = dot
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var dx := absf(x - 15.5) / 15.5; var dy := absf(y - 15.5) / 15.5
			var v := maxf(maxf(0.0, 1.0 - dx * 6.0) * (1.0 - dy), maxf(0.0, 1.0 - dy * 6.0) * (1.0 - dx))
			v = maxf(v, maxf(0.0, 1.0 - sqrt(dx * dx + dy * dy) * 2.2))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(v, 0.0, 1.0)))
	fx_star_tex = ImageTexture.create_from_image(img)

func tier_color(i: int) -> Color:
	return db.rarity_color(i)

func tier_name(i: int) -> String:
	return db.rarity_name(i)

func clamp_to_field(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, FIELD.position.x, FIELD.end.x), clampf(p.y, FIELD.position.y, FIELD.end.y))

func heroes() -> Array:
	return units.filter(func(u): return u.team == "hero" and not u.dead)

func enemies() -> Array:
	return units.filter(func(u): return u.team == "enemy" and not u.dead)

func _foes(of) -> Array:
	return enemies() if of.team == "hero" else heroes()

func nearest_enemy(of):
	var best = null; var bd := INF
	for e in _foes(of):
		var d: float = of.position.distance_squared_to(e.position)
		if d < bd:
			bd = d; best = e
	return best

func nearest_hero(of):
	var best = null
	var bd := INF
	for h in heroes():
		if h.dead:
			continue
		var d: float = of.position.distance_squared_to(h.position)
		if d < bd:
			bd = d
			best = h
	return best

func enemies_sorted(of) -> Array:
	var l := _foes(of)
	l.sort_custom(func(a, b): return of.position.distance_squared_to(a.position) < of.position.distance_squared_to(b.position))
	return l

func enemies_in_radius(of, p: Vector2, r: float) -> Array:
	return _foes(of).filter(func(e): return e.position.distance_to(p) <= r + e.radius)

## 伤害：《装备数值表》§1.1 公式（见 equip_db.compute_damage）。proc=true 表示特效/爆炸，不叠层（§1.1 no_chain）
func deal_damage(src, tgt, mult: float, is_skill := false, proc := false) -> void:
	if tgt == null or not is_instance_valid(tgt) or tgt.dead or src == null or not is_instance_valid(src):
		return
	var r: Dictionary = db.compute_damage(src, tgt, mult, is_skill)
	if not r.hit:
		spawn_text(tgt.position + Vector2(0, tgt._head_y() - 18), "闪避", Color(0.8, 0.9, 1.0), 18)
		return
	tgt.take_damage(r.dmg, r.crit)
	# 续航：百分比吸血 + 每次攻击固定回血。吸血合计上限 12%，单次回复不超过生命上限 6%，避免无敌
	if src.team == "hero" and int(r.dmg) > 0:
		var lp: int = src.leech_pct(is_skill)
		var flat: int = src.hit_heal_value()
		if lp > 0 or flat > 0:
			var healed: int = db.iround(float(r.dmg) * float(lp) / 100.0) + flat
			var cap: int = maxi(1, db.iround(float(src.max_hp) * 0.06))
			healed = mini(healed, cap)
			if healed >= 1:
				src.heal(float(healed))
	# v1.3 仇恨：记在怪物身上。英雄输出按职业倍率，英雄承伤按承伤倍率。
	if src.team == "hero" and tgt.team == "enemy":
		tgt.add_threat(src, float(r.dmg) * src.threat_deal())
		src.on_dealt_hit(tgt, r, proc)
	elif src.team == "enemy" and tgt.team == "hero":
		src.add_threat(tgt, float(r.dmg) * tgt.threat_taken())
	if tgt.dead and src.team == "hero":
		src.on_kill(tgt)
	if proc or tgt.dead:
		return
	# 属性叠层：概率 = 基础 + 属性伤害/攻击，有上限（§1.2）
	var er: Dictionary = db.r.elements
	for e in src.elem:
		var ev: float = src.elem[e]
		if ev <= 0.0:
			continue
		var ch: float = minf(float(er.stack_cap), float(er.stack_base) + ev / maxf(1.0, src.atk))
		if randf() < ch:
			tgt.add_stack(e, src)

## 火 5 层爆炸：攻击×150% + 火伤×300%，半径 100，吃火抗（§1.2）
func fire_burst(src, tgt) -> void:
	if src == null or not is_instance_valid(src):
		return
	var fr: Dictionary = db.r.elements.fire
	var p: Vector2 = tgt.position
	spawn_ring(p, float(fr.burst_radius), Color(1.0, 0.45, 0.1), 0.45)
	for e in enemies_in_radius(src, p, float(fr.burst_radius)):
		var d: float = (src.atk * float(fr.burst_atk_mult) + float(src.elem.get("fire", 0.0)) * float(fr.burst_elem_mult)) * (1.0 - float(e.res.get("fire", 0.0)) / 100.0)
		e.take_damage(maxf(1.0, d), false, Color(1.0, 0.55, 0.15))

func spawn_projectile(src, tgt, dmg: float, color: Color, spd: float, kind: String, delay := 0.0, is_skill := false) -> void:
	var p = ProjScript.new()
	p.main = self; p.src = src; p.tgt = tgt; p.dmg = dmg; p.spd = spd; p.color = color; p.kind = kind; p.delay = delay; p.is_skill = is_skill
	p.position = src.position + Vector2(src.facing * 30, -60)
	fx_layer.add_child(p)

func spawn_text(p: Vector2, text: String, color: Color, sz := 20) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UiScale.fs(sz))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.position = p - Vector2(52, 0)
	l.size = Vector2(104, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fx_layer.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 46, 0.8)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.tween_callback(l.queue_free)

func spawn_ring(p: Vector2, r: float, color: Color, dur: float) -> void:
	var n := Node2D.new()
	n.position = p
	n.set_meta("r", r); n.set_meta("c", color)
	n.draw.connect(func():
		var rr: float = n.get_meta("r")
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
		n.draw_arc(Vector2.ZERO, rr, 0, TAU, 48, n.get_meta("c"), 6.0)
		n.draw_circle(Vector2.ZERO, rr, Color(n.get_meta("c"), 0.15)))
	fx_layer.add_child(n)
	n.scale = Vector2(0.4, 0.4)
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector2.ONE, dur * 0.5)
	tw.tween_property(n, "modulate:a", 0.0, dur * 0.5)
	tw.tween_callback(n.queue_free)

func on_unit_died(u) -> void:
	if u.team == "enemy":
		var k: String = str(u.kind)
		if k != "elite" and k != "boss":
			k = "normal"
		play_kills[k] = int(play_kills.get(k, 0)) + 1
		_refresh_play_stats()
		_drop_loot(u)
		var tw: Tween = u.create_tween()
		tw.tween_property(u, "modulate:a", 0.0, 0.8).set_delay(0.4)
		tw.tween_callback(func():
			units.erase(u)
			u.queue_free())
	if u == selected:
		_select(null)
	if u.team == "hero" and heroes().is_empty():
		_end("lose")

# ---------- 波次 ----------
func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()
	if banner_t > 0.0:
		banner_t -= delta
		banner.modulate.a = clampf(banner_t, 0.0, 1.0)
	bag_full_t = maxf(0.0, bag_full_t - delta)
	_spawn_pending(delta)
	if farm_loops > 0:
		_farm_process()
	elif endless and state == "playing" and enemies().is_empty() and pending_spawn.is_empty():
		if endless_wave >= 1 and not has_meta("endless_cleared_%d" % endless_wave):
			set_meta("endless_cleared_%d" % endless_wave, true)
			if endless_wave > endless_best:
				endless_best = endless_wave
				save_game()
			_show_banner("无尽 · 第 %d 波通过" % endless_wave)
		wave_timer -= delta
		if wave_timer <= 0.0:
			_spawn_endless_wave(endless_wave + 1)
	elif state == "playing" and enemies().is_empty() and pending_spawn.is_empty():
		if wave_idx >= 0 and not cleared_set.has(wave_idx):
			cleared_set[wave_idx] = true
			wave_times.append(elapsed - float(get_meta("wave_start", 0.0)))
			if wave_idx + 2 > max_wave and wave_idx + 1 < cfg.waves.size() and farm_loops == 0:
				max_wave = wave_idx + 2      # 打完这一波 → 解锁下一波
				_clamp_unlock()
				save_game()
			if cfg.waves[wave_idx].get("kind", "") == "boss" and farm_loops == 0:
				boss_killed = true
				save_game()
			if cfg.waves[wave_idx].get("kind", "") == "boss" and camp_boss.is_empty():
				camp_boss = {"attempt": camp_attempts, "time": elapsed}
		if wave_idx >= cfg.waves.size() - 1 and wave_idx >= 0:
			_end("win")
		else:
			wave_timer -= delta
			if wave_timer <= 0.0:
				_spawn_wave(wave_idx + 1)
	_refresh_wave_label()
	_refresh_portraits()
	if autotest:
		_autotest_step()
	if sim_preset != "":
		_sim_step()
	if "--test-clean-defeat" in OS.get_cmdline_user_args():
		_clean_defeat_step()

## 波次全部读 config.json waves（总经理定）；同屏怪物不超过 max_on_screen，多出的分批刷
func _spawn_wave(i: int) -> void:
	if get_meta("sim_auto_equip", false):
		_auto_equip_best()
	wave_idx = i
	if farm_loops == 0 and i + 1 > max_wave:
		max_wave = i + 1
		_clamp_unlock()
	wave_timer = cfg.wave_delay
	set_meta("wave_start", elapsed)
	var w: Dictionary = cfg.waves[i]
	_show_banner(w.name)
	for kind in w.spawn:
		for k in int(w.spawn[kind]):
			pending_spawn.append([kind, i])
	spawn_cd = 0.0
	_spawn_pending(0.0, true)

func wave_monster_level(i: int, kind: String) -> int:
	var ml = cfg.waves[i].get("monster_level", {})
	if typeof(ml) == TYPE_DICTIONARY and ml.has(kind):
		return int(ml[kind])
	if typeof(ml) != TYPE_DICTIONARY:
		return int(ml)
	return int(cfg.monsters[kind].get("level", db.r.hero_level))

func _spawn_pending(delta: float, burst := false) -> void:
	if pending_spawn.is_empty():
		return
	spawn_cd -= delta
	var cap: int = int(cfg.get("max_on_screen", 20))
	while not pending_spawn.is_empty() and enemies().size() < cap and (burst or spawn_cd <= 0.0):
		var e: Array = pending_spawn.pop_front()
		_spawn_one(e[0], e[1], enemies().size())
		if not burst:
			spawn_cd = float(cfg.get("spawn_batch_interval_s", 0.4))

func _spawn_one(kind: String, i: int, n: int) -> void:
	var m = UnitScript.new()
	world.add_child(m)
	var left := (n % 2 == 0)
	if kind == "boss":
		m.position = Vector2(1180, 440)
	else:
		m.position = Vector2(80 if left else 1200, randf_range(FIELD.position.y + 20, FIELD.end.y - 20))
	m.setup_monster(kind, cfg.monsters[kind], self, wave_monster_level(i, kind))
	m.set_meta("wave", i)
	if endless:
		var grow: float = float(cfg.get("endless", {}).get("hp_atk_growth", 0.08))
		var mul: float = pow(1.0 + grow, maxi(0, endless_wave - 1))
		m.max_hp = db.iround(float(m.max_hp) * mul)
		m.hp = m.max_hp
		m.atk = db.iround(float(m.atk) * mul)
	units.append(m)

func boss_cleared() -> bool:
	return boss_killed

func boss_wave_no() -> int:
	for j in cfg.waves.size():
		if cfg.waves[j].get("kind", "") == "boss":
			return j + 1
	return cfg.waves.size()

## 解锁上限：没杀过头目时最多解锁到头目波（挑战波必须先杀头目）
func _clamp_unlock() -> void:
	if not boss_killed:
		max_wave = mini(max_wave, boss_wave_no())

func _show_banner(text: String) -> void:
	banner.text = text
	banner_t = 2.0
	banner.modulate.a = 1.0

func _end(s: String) -> void:
	if state != "playing":
		return
	state = s
	if s == "win":
		result_label.text = "全部通关！挑战波也拿下了"
	elif cfg.waves[clampi(wave_idx, 0, cfg.waves.size() - 1)].get("kind", "") == "challenge":
		result_label.text = "挑战波失败——山贼头目已击败\n可以「再来一波」刷装备再战"
	else:
		if endless:
			result_label.text = "无尽模式战至第 %d 波\n最高纪录：第 %d 波\n背包和装备都保留" % [maxi(1, endless_wave), maxi(endless_best, endless_wave)]
		else:
			result_label.text = "失败……小队全灭（第 %d 波）\n背包和装备都保留" % (wave_idx + 1)
	result_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3) if s == "win" else Color(1, 0.4, 0.4))
	result_panel.visible = true
	farm_btn.visible = (not endless) and (s == "win" or boss_cleared())
	if endless:
		retry_first_btn.text = "再战无尽"
		for c in retry_first_btn.pressed.get_connections():
			retry_first_btn.pressed.disconnect(c.callable)
		retry_first_btn.pressed.connect(_retry_endless)
		retry_first_btn.visible = s == "lose"
		retry_btn.visible = false
		retry_box.visible = false
		farm_hint.visible = false
	else:
		retry_first_btn.text = "从第 1 波重打（背包和装备保留）"
		for c in retry_first_btn.pressed.get_connections():
			retry_first_btn.pressed.disconnect(c.callable)
		retry_first_btn.pressed.connect(func(): retry_from(1))
		retry_first_btn.visible = s == "lose"
		_fill_retry(retry_box, retry_btn)
		retry_btn.visible = s == "lose"
		farm_hint.visible = s == "lose"
		retry_box.visible = s == "lose"
	if mode_select_btn != null:
		mode_select_btn.visible = true
	save_game()
	print("RESULT: %s  (wave %d, elapsed %.1fs game time)" % [s, wave_idx + 1, elapsed])

# ---------- 输入 ----------
func _unhandled_input(ev: InputEvent) -> void:
	if state != "playing":
		return
	if ev is InputEventMouseButton and ev.pressed:
		var p: Vector2 = get_global_mouse_position()
		if ev.button_index == MOUSE_BUTTON_LEFT:
			for l in fx_layer.get_children():
				if l is LootScript and not l.picked and l.hit_test(p):
					l.pickup()
					return
			var hit = null; var bd := 60.0
			for h in heroes():
				var d: float = (h.position + Vector2(0, -50)).distance_to(p)
				if d < bd:
					bd = d; hit = h
			if hit != null:
				_select(hit)
			elif selected != null and FIELD.grow(30).has_point(p):
				selected.move_target = clamp_to_field(p)
				spawn_ring(clamp_to_field(p), 18, Color(0.4, 1, 0.5), 0.4)
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			_select(null)
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_1, KEY_2, KEY_3:
				var idx: int = ev.keycode - KEY_1
				if idx < units.size() and units[idx].team == "hero" and not units[idx].dead:
					_select(units[idx])
			KEY_E, KEY_B:
				toggle_bag()

func _select(u) -> void:
	if selected != null and is_instance_valid(selected):
		selected.selected = false
	selected = u
	if u != null:
		u.selected = true
	if bag_ui != null and bag_ui.visible and u != null:
		bag_ui.hero_idx = units.find(u); bag_ui.refresh()

# ---------- 地图（色块） ----------
func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.62, 0.82, 0.95))
	# 远山
	draw_colored_polygon(PackedVector2Array([Vector2(0, 200), Vector2(160, 90), Vector2(330, 190), Vector2(520, 70), Vector2(740, 190), Vector2(930, 100), Vector2(1120, 180), Vector2(1280, 110), Vector2(1280, 230), Vector2(0, 230)]), Color(0.55, 0.68, 0.62))
	# 地面
	draw_rect(Rect2(0, 210, 1280, 510), Color(0.56, 0.72, 0.38))
	draw_rect(Rect2(0, 210, 1280, 30), Color(0.47, 0.62, 0.32))
	# 村屋（背景）
	for x in [130, 330, 900, 1100]:
		draw_rect(Rect2(x, 150, 110, 70), Color(0.78, 0.7, 0.55))
		draw_colored_polygon(PackedVector2Array([Vector2(x - 12, 152), Vector2(x + 55, 112), Vector2(x + 122, 152)]), Color(0.35, 0.33, 0.38))
		draw_rect(Rect2(x + 42, 180, 26, 40), Color(0.45, 0.3, 0.2))
	# 石板路
	draw_set_transform(Vector2(640, 440), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 300, Color(0.66, 0.66, 0.6, 0.55))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 青石（地标）
	draw_colored_polygon(PackedVector2Array([Vector2(610, 250), Vector2(640, 214), Vector2(676, 222), Vector2(690, 252)]), Color(0.35, 0.5, 0.52))
	draw_string(font, Vector2(590, 246), "青石村", HORIZONTAL_ALIGNMENT_CENTER, 140, UiScale.fs(16), Color(1, 1, 1, 0.9))
	# 栅栏（前景）
	for x in range(0, 1280, 48):
		draw_rect(Rect2(x + 10, 650, 8, 36), Color(0.55, 0.4, 0.25, 0.8))
	draw_rect(Rect2(0, 662, 1280, 6), Color(0.55, 0.4, 0.25, 0.8))

# ---------- HUD ----------
func _build_hud() -> void:
	hud = CanvasLayer.new(); hud.layer = 5; add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.add_child(root)
	var ui_theme := Theme.new()
	ui_theme.default_font_size = UiScale.fs(16)
	root.theme = ui_theme
	var top := ColorRect.new(); top.color = Color(0, 0, 0, 0.45)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE); top.offset_bottom = 58
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	wave_label = Label.new(); wave_label.position = Vector2(16, 8)
	wave_label.size = Vector2(720, 44)
	wave_label.clip_text = false
	wave_label.add_theme_font_size_override("font_size", UiScale.fs(22))
	root.add_child(wave_label)
	hint_label = Label.new()
	hint_label.text = "点角色选中 → 点地面移动 · 点地上掉落拾取 · 1/2/3 选人 · B 背包"
	hint_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint_label.offset_left = -740; hint_label.offset_top = 6; hint_label.offset_right = -200; hint_label.offset_bottom = 54
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_font_size_override("font_size", UiScale.fs(15))
	root.add_child(hint_label)
	bag_btn = Button.new(); bag_btn.text = "背包 (B)"
	bag_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bag_btn.offset_left = -190; bag_btn.offset_top = 4; bag_btn.offset_right = -8; bag_btn.offset_bottom = 54
	bag_btn.add_theme_font_size_override("font_size", UiScale.fs(20))
	bag_btn.pressed.connect(toggle_bag)
	root.add_child(bag_btn)
	var st_btn := Button.new(); st_btn.text = "试玩统计"
	st_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	st_btn.offset_left = -180; st_btn.offset_top = -66; st_btn.offset_right = -8; st_btn.offset_bottom = -8
	st_btn.add_theme_font_size_override("font_size", UiScale.fs(18))
	root.add_child(st_btn)
	debug_panel = VBoxContainer.new()
	debug_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	debug_panel.offset_left = -400; debug_panel.offset_right = -8; debug_panel.offset_top = -380; debug_panel.offset_bottom = -74
	debug_panel.add_theme_constant_override("separation", 6)
	debug_panel.visible = false
	root.add_child(debug_panel)
	st_btn.pressed.connect(func(): debug_panel.visible = not debug_panel.visible)
	play_stats_lbl = Label.new()
	play_stats_lbl.add_theme_font_size_override("font_size", UiScale.fs(16))
	play_stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	play_stats_lbl.custom_minimum_size = Vector2(380, 210)
	debug_panel.add_child(play_stats_lbl)
	var rst := Button.new(); rst.text = "清空存档（重新开局）"
	rst.custom_minimum_size = Vector2(0, 56)
	rst.add_theme_font_size_override("font_size", UiScale.fs(17))
	rst.pressed.connect(debug_reset)
	debug_panel.add_child(rst)
	_refresh_play_stats()
	banner = Label.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.offset_left = -440; banner.offset_right = 440; banner.offset_top = 100
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", UiScale.fs(40))
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 8)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(banner)
	# 底部头像栏
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.offset_left = 12; bar.offset_top = -70; bar.offset_bottom = -8; bar.offset_right = 680
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	for i in cfg.heroes.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 58)
		b.add_theme_font_size_override("font_size", UiScale.fs(16))
		var idx: int = i
		b.pressed.connect(func():
			if idx < units.size() and not units[idx].dead:
				_select(units[idx]))
		bar.add_child(b)
		portrait_btns.append(b)
	bag_ui = BagUI.new()
	bag_ui.visible = false
	bag_ui.setup(self)
	# 结果面板
	result_panel = Panel.new()
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.offset_left = -330; result_panel.offset_right = 330; result_panel.offset_top = -300; result_panel.offset_bottom = 300
	result_panel.visible = false
	root.add_child(result_panel)
	result_panel.add_theme_stylebox_override("panel", _panel_box())
	var vb := VBoxContainer.new(); vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 20; vb.offset_right = -20; vb.offset_top = 24; vb.offset_bottom = -20
	vb.add_theme_constant_override("separation", 14)
	result_panel.add_child(vb)
	result_label = Label.new(); result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", UiScale.fs(30))
	vb.add_child(result_label)
	farm_hint = Label.new(); farm_hint.text = "装备不够？回前几波刷装备"; farm_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	farm_hint.add_theme_font_size_override("font_size", UiScale.fs(20)); farm_hint.add_theme_color_override("font_color", Color(1, 0.92, 0.55))
	vb.add_child(farm_hint)
	# 默认（主）按钮：从第 1 波重打；「从第 N 波重打」和选波次是次要选项
	retry_first_btn = _primary_button("从第 1 波重打（背包和装备保留）")
	retry_first_btn.pressed.connect(func(): retry_from(1))
	vb.add_child(retry_first_btn)
	retry_btn = _secondary_button()
	vb.add_child(retry_btn)
	retry_box = HFlowContainer.new(); retry_box.add_theme_constant_override("h_separation", 6); retry_box.add_theme_constant_override("v_separation", 6)
	vb.add_child(retry_box)
	farm_btn = Button.new(); farm_btn.text = "再来一波（刷怪）"; farm_btn.custom_minimum_size = Vector2(0, 60)
	farm_btn.add_theme_font_size_override("font_size", UiScale.fs(22))
	farm_btn.pressed.connect(start_farm)
	vb.add_child(farm_btn)
	mode_select_btn = _secondary_button()
	mode_select_btn.text = "返回选择模式"
	mode_select_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_select_btn.pressed.connect(_return_to_mode_select)
	vb.add_child(mode_select_btn)
	_build_start_panel(root)
	root.add_child(bag_ui)

## 「从第 N 波重打」：N 在 1~已解锁最高波次之间；重载场景（英雄满血），背包/装备从存档读回
func retry_from(n: int) -> void:
	n = clampi(n, 1, max_wave)
	save_game()
	Engine.set_meta("retry_from", n)
	_restart()

func _fill_retry(box: HFlowContainer, big: Button) -> void:
	for c in box.get_children(): c.queue_free()
	big.text = "或：从第 %d 波重打（已解锁最高）" % max_wave
	for c in big.pressed.get_connections(): big.pressed.disconnect(c.callable)
	var mw: int = max_wave
	big.pressed.connect(func(): retry_from(mw))
	var lb := Label.new(); lb.text = "选波次："; lb.add_theme_font_size_override("font_size", UiScale.fs(18))
	box.add_child(lb)
	for k in range(1, max_wave + 1):
		var w: Dictionary = cfg.waves[k - 1]
		var b := Button.new()
		b.text = "第%d波%s" % [k, "·头目" if w.get("kind", "") == "boss" else ("·挑战" if w.get("kind", "") == "challenge" else "")]
		b.custom_minimum_size = Vector2(112, 54); b.add_theme_font_size_override("font_size", UiScale.fs(17))
		var kk: int = k
		b.pressed.connect(func(): retry_from(kk))
		box.add_child(b)

## 开局界面：先点「开始游戏」，再选闯关模式或无尽模式。闯关里可从第 1 波或已解锁波次开始。
func _build_start_panel(root: Control) -> void:
	start_panel = Panel.new()
	start_panel.set_anchors_preset(Control.PRESET_CENTER)
	start_panel.offset_left = -380; start_panel.offset_right = 380; start_panel.offset_top = -270; start_panel.offset_bottom = 270
	start_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	start_panel.z_index = 80
	start_panel.visible = false
	root.add_child(start_panel)
	start_panel.add_theme_stylebox_override("panel", _panel_box())
	start_entry = _make_start_page(start_panel)
	start_modes = _make_start_page(start_panel)
	start_campaign = _make_start_page(start_panel)
	# —— 入口 ——
	start_entry.add_child(_title_label("修仙小队", true, "entry_title"))
	var entry_sub := _hint_label("选择要游玩的模式")
	entry_sub.set_meta("entry_sub", true)
	start_entry.add_child(entry_sub)
	var entry_rec := _hint_label("")
	entry_rec.set_meta("entry_rec", true)
	start_entry.add_child(entry_rec)
	var go := _primary_button("开始游戏")
	go.pressed.connect(func(): _show_start_view("modes"))
	start_entry.add_child(go)
	# —— 选择模式 ——
	start_modes.add_child(_title_label("选择模式", true, "modes_title"))
	var camp_hint := _hint_label("")
	camp_hint.set_meta("camp_hint", true)
	start_modes.add_child(camp_hint)
	var bcamp := _primary_button("闯关模式")
	bcamp.pressed.connect(_on_pick_campaign)
	start_modes.add_child(bcamp)
	start_modes.add_child(_hint_label("青石村按波推进，掉落和装备会保留"))
	var ben := _primary_button("无尽模式")
	ben.pressed.connect(_start_endless)
	start_modes.add_child(ben)
	var mode_rec := _hint_label("")
	mode_rec.set_meta("mode_rec", true)
	start_modes.add_child(mode_rec)
	var back_m := _back_button("返回")
	back_m.pressed.connect(func(): _show_start_view("entry"))
	start_modes.add_child(back_m)
	# —— 闯关选波 ——
	start_campaign.add_child(_title_label("闯关模式", true, "camp_title"))
	var b1 := _primary_button("从第 1 波开始")
	b1.pressed.connect(func(): _start_at(1))
	start_campaign.add_child(b1)
	var big := _secondary_button()
	big.set_meta("big", true)
	start_campaign.add_child(big)
	var box := HFlowContainer.new()
	box.add_theme_constant_override("h_separation", 6)
	box.add_theme_constant_override("v_separation", 6)
	box.set_meta("box", true)
	start_campaign.add_child(box)
	var back_c := _back_button("返回")
	back_c.pressed.connect(func(): _show_start_view("modes"))
	start_campaign.add_child(back_c)


func _make_start_page(host: Control) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 24; vb.offset_right = -24; vb.offset_top = 22; vb.offset_bottom = -22
	vb.add_theme_constant_override("separation", 12)
	vb.visible = false
	host.add_child(vb)
	return vb


func _title_label(text: String, gold := true, meta := "") -> Label:
	var t := Label.new()
	t.text = text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_font_size_override("font_size", UiScale.fs(28))
	t.add_theme_color_override("font_color", Color(1, 0.9, 0.6) if gold else Color(0.92, 0.93, 0.96))
	if meta != "":
		t.set_meta(meta, true)
	return t


func _hint_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", UiScale.fs(18))
	l.add_theme_color_override("font_color", Color(0.85, 0.86, 0.9))
	return l


func _back_button(text := "返回") -> Button:
	var b := _secondary_button()
	b.text = text
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return b


func _refresh_start_labels() -> void:
	var rec: String = "无尽最高纪录：第 %d 波" % endless_best if endless_best > 0 else "无尽最高纪录：暂无"
	var unlock: String = "闯关已解锁到第 %d 波" % max_wave
	for page in [start_entry, start_modes, start_campaign]:
		if page == null:
			continue
		for c in page.get_children():
			if c.has_meta("entry_sub"):
				c.text = unlock
			if c.has_meta("entry_rec") or c.has_meta("mode_rec"):
				c.text = rec
			if c.has_meta("camp_hint"):
				c.text = unlock
			if c.has_meta("camp_title"):
				c.text = "闯关模式"


func _show_start_view(view: String) -> void:
	if start_entry != null:
		start_entry.visible = view == "entry"
	if start_modes != null:
		start_modes.visible = view == "modes"
	if start_campaign != null:
		start_campaign.visible = view == "campaign"


func _on_pick_campaign() -> void:
	_refresh_campaign_picker()
	_show_start_view("campaign")


func _refresh_campaign_picker() -> void:
	var big: Button
	var box: HFlowContainer
	for c in start_campaign.get_children():
		if c.has_meta("big"):
			big = c
		if c.has_meta("box"):
			box = c
	if big == null or box == null:
		return
	_fill_retry(box, big)
	big.visible = max_wave > 1
	box.visible = max_wave > 1
	if big.visible:
		big.text = "或：从第 %d 波继续（已解锁最高）" % max_wave
		for c in big.pressed.get_connections():
			big.pressed.disconnect(c.callable)
		var mw: int = max_wave
		big.pressed.connect(func(): _start_at(mw))
	for b in box.get_children():
		if b is Button:
			for c in b.pressed.get_connections():
				b.pressed.disconnect(c.callable)
			var k: int = int(b.text.substr(1).split("波")[0])
			b.pressed.connect(func(): _start_at(k))


func _return_to_mode_select() -> void:
	save_game()
	Engine.set_meta("open_mode_select", true)
	_restart()


func _retry_endless() -> void:
	save_game()
	Engine.set_meta("retry_endless", true)
	_restart()

func _primary_button(text: String) -> Button:
	var b := Button.new(); b.text = text; b.custom_minimum_size = Vector2(0, 68)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.clip_text = false
	b.add_theme_font_size_override("font_size", UiScale.fs(24))
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new(); sb.set_corner_radius_all(8)
		sb.bg_color = Color(0.85, 0.6, 0.18) if st == "normal" else (Color(0.95, 0.7, 0.25) if st == "hover" else Color(0.7, 0.48, 0.12))
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color(0.12, 0.08, 0.02)); b.add_theme_color_override("font_hover_color", Color(0.12, 0.08, 0.02))
	return b

func _secondary_button() -> Button:
	var b := Button.new(); b.custom_minimum_size = Vector2(0, 54)
	b.add_theme_font_size_override("font_size", UiScale.fs(18))
	b.add_theme_color_override("font_color", Color(0.78, 0.8, 0.86))
	return b

func _panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.08, 0.09, 0.13, 0.94)
	sb.set_border_width_all(2); sb.border_color = Color(0.85, 0.75, 0.45); sb.set_corner_radius_all(10)
	return sb

func _show_start_panel(view := "entry") -> void:
	_refresh_start_labels()
	_refresh_campaign_picker()
	_show_start_view(view)
	start_panel.visible = true
	get_tree().paused = true

func _start_at(n: int) -> void:
	n = clampi(n, 1, maxi(1, max_wave))
	endless = false
	endless_wave = 0
	start_panel.visible = false
	get_tree().paused = false
	wave_idx = n - 2
	if n >= 2: cleared_set[n - 2] = true   # 之前的波次不算本局打完
	wave_timer = 0.8
	set_meta("start_wave", n)

func _start_endless() -> void:
	endless = true
	endless_wave = 0
	farm_loops = 0
	wave_idx = -1
	start_panel.visible = false
	get_tree().paused = false
	wave_timer = 0.4
	_show_banner("无尽模式")

func _refresh_wave_label() -> void:
	if wave_label == null:
		return
	if endless:
		wave_label.text = "无尽模式 · 第 %d 波（最高 %d）" % [maxi(1, endless_wave), endless_best]
	else:
		wave_label.text = "%s · %s%s" % [region, cfg.waves[wave_idx].name if wave_idx >= 0 and wave_idx < cfg.waves.size() else "准备", "（刷怪第 %d 轮）" % farm_loops if farm_loops > 0 else ""]

func _spawn_endless_wave(n: int) -> void:
	endless = true
	endless_wave = maxi(1, n)
	var tw: int = int(cfg.get("endless", {}).get("template_wave", 0))
	tw = clampi(tw, 0, cfg.waves.size() - 1)
	wave_idx = tw
	wave_timer = cfg.wave_delay
	set_meta("wave_start", elapsed)
	_show_banner("无尽 · 第 %d 波" % endless_wave)
	var w: Dictionary = cfg.waves[tw]
	for kind in w.spawn:
		for k in int(w.spawn[kind]):
			pending_spawn.append([kind, tw])
	spawn_cd = 0.0
	_spawn_pending(0.0, true)

func _is_starter_test_weapon(it) -> bool:
	if typeof(it) != TYPE_DICTIONARY:
		return false
	return bool(it.get("test_leech", false)) or str(it.get("starter_kit", "")) != ""


func _ensure_test_leech_weapons() -> void:
	const KIT := "faxiu_heal_v16"
	var have := 0
	for it in bag:
		if typeof(it) == TYPE_DICTIONARY and str(it.get("starter_kit", "")) == KIT:
			have += 1
	for u in units:
		if u.team != "hero":
			continue
		for sid in u.gear:
			var git = u.gear[sid]
			if typeof(git) == TYPE_DICTIONARY and str(git.get("starter_kit", "")) == KIT:
				have += 1
	if have >= 3:
		return
	var kept: Array = []
	for it in bag:
		if _is_starter_test_weapon(it):
			continue
		kept.append(it)
	bag = kept
	for u in units:
		if u.team != "hero":
			continue
		var changed := false
		for sid in u.gear:
			if _is_starter_test_weapon(u.gear[sid]):
				u.gear[sid] = null
				changed = true
		if changed:
			u.recalc_stats(true)
	for wt in ["sword", "blade", "staff"]:
		bag.append(db.make_starter_leech_weapon(wt, 10))

func _restart() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

func _refresh_portraits() -> void:
	for i in portrait_btns.size():
		var u = units[i]
		var b: Button = portrait_btns[i]
		b.text = "%d %s  %d/%d%s" % [i + 1, u.display_name, int(u.hp), int(u.max_hp), "  ✔" if u == selected else ""] if not u.dead else "%d %s  阵亡" % [i + 1, u.display_name]
		b.disabled = u.dead

# ---------- 装备系统：开局 / 掉落 / 背包操作 / 存档 ----------
## 老板决定 2026-11-20：默认不限职业（config.equip_class_restriction=false）
func class_restricted() -> bool:
	return bool(cfg.get("equip_class_restriction", false))

func _hero_wtype(u) -> String:
	return str(db.r.hero_weapon_type.get(u.uid, db.r.default_weapon_type))

func _new_game() -> void:
	bag.clear(); gems.clear(); pity.clear(); silver = 0; max_wave = 1; boss_killed = false
	# 总经理决定（方案 C）：config.starter_gear_override 覆盖表里的 starter_gear（表原值：白 1 级，只有武器/衣服/鞋）
	var sg: Dictionary = db.r.starter_gear
	var ov: Dictionary = cfg.get("starter_gear_override", {})
	if not ov.is_empty():
		sg = ov.duplicate()
		if str(ov.get("slots", "all")) == "all": sg.slots = db.slots.map(func(x): return x.id)
	for u in units:
		if u.team != "hero":
			continue
		# v0.4 starter_gear.slots：只给列出的部位（武器/衣服/鞋），其余空着等掉落
		var sl: Array = sg.get("slots", db.slots.map(func(x): return x.id))
		for s in db.slots:
			if not s.id in sl:
				u.gear[s.id] = null; continue
			u.gear[s.id] = db.make_item(s.id, db.rarity_idx[sg.rarity], int(sg.level), _hero_wtype(u) if s.id == "weapon" else "")
		u.recalc_stats(true)
	for gid in db.r.starter_gems:
		if db.gem_by_id.has(gid):
			gems["%s:1" % gid] = int(db.r.starter_gems[gid])
	_ensure_test_leech_weapons()

func _drop_loot(u) -> void:
	var wv: int = int(u.get_meta("wave", 0))
	var lvls: Array = db.r.farm_item_levels if farm_loops > 0 else cfg.waves[clampi(wv, 0, cfg.waves.size() - 1)].get("item_levels", db.r.farm_item_levels)
	# 怪物绑银（v0.4 monsters.levels[].bind_silver）
	silver += int(u.get_meta("bind_silver", 0))
	var lv: int = int(lvls[randi() % lvls.size()])
	db.rarity_boost = _sim_boost if (not _sim_boost.is_empty() and farm_loops == 0 and wv < _sim_boost_waves) else {}
	var items: Array = db.roll_drop(u.kind, region, lv, pity, u.uid if u.kind == "boss" else "")
	db.rarity_boost = {}
	var i := 0
	for it in items:
		_assign_wtype(it)
		drop_log.append(it)
		var qn: String = db.rarity_name(int(it.rarity))
		play_drops[qn] = int(play_drops.get(qn, 0)) + 1
		_refresh_play_stats()
		spawn_loot(u.position + Vector2(-30 + i * 60, 10), it, "")
		i += 1
	for gl in db.roll_gems(u.kind, region):
		spawn_loot(u.position + Vector2(-30 + i * 60, 24), {}, gl[0], int(gl[1]))
		i += 1

func _assign_wtype(it: Dictionary) -> void:
	if it.slot == "weapon":
		var types: Array = []
		if not class_restricted():
			# 不限职业：掉落的武器类型从数值表全部武器类型里随机，不再按队伍职业
			for wt in db.t.names.get("weapon_types", []): types.append(str(wt.id))
		for h in ([] if not types.is_empty() else cfg.heroes):
			var wt := str(db.r.hero_weapon_type.get(h.id, db.r.default_weapon_type))
			if not wt in types: types.append(wt)
		it.wtype = types[randi() % types.size()]
		it.name = db.item_name(it)

func spawn_loot(p: Vector2, it: Dictionary, gid: String, gem_lv := 1) -> void:
	var l = LootScript.new()
	l.main = self; l.item = it; l.gem_id = gid; l.set_meta("gem_lv", gem_lv)
	l.auto_t = float(db.r.get("loot_auto_pickup_s", 2.5))
	if gid != "":
		l.color = Color(0.5, 0.95, 0.85); l.label = "%s Lv%d" % [db.gem_by_id[gid].name, gem_lv]
	else:
		l.rarity = int(it.rarity); l.color = db.rarity_color(it.rarity); l.label = it.name
	l.position = clamp_to_field(p)
	fx_layer.add_child(l)

func bag_capacity() -> int:
	return int(cfg.get("bag", {}).get("capacity", 120))

func bag_has_room() -> bool:
	return bag.size() < bag_capacity()

## 背包满：地上的装备留着不捡，提示一次（2 秒内不重复）
func notify_bag_full(p: Vector2) -> void:
	if bag_full_t > 0.0:
		return
	bag_full_t = 2.0
	spawn_text(p + Vector2(0, -90), "背包已满（%d/%d）！打开背包「一键出售白绿」" % [bag.size(), bag_capacity()], Color(1, 0.45, 0.4), 22)
	_show_banner("背包已满，装备没捡起来")

## 一键出售：白/绿（config.bag.sell_rarities），排除已穿戴（不在 bag 里）和已上锁
func sell_junk() -> Dictionary:
	var rs: Array = cfg.get("bag", {}).get("sell_rarities", ["白", "绿"])
	var keep: Array = []; var n := 0; var got := 0
	for it in bag:
		if db.rarity_name(int(it.rarity)) in rs and not bool(it.get("locked", false)):
			n += 1; got += db.sell_price(it, cfg.get("bag", {}))
		else:
			keep.append(it)
	bag = keep
	silver += got
	_bag_badge(); save_game()
	return {"n": n, "silver": got}

func on_loot_picked(l) -> void:
	if l.gem_id != "":
		var k := "%s:%d" % [l.gem_id, int(l.get_meta("gem_lv", 1))]
		gems[k] = int(gems.get(k, 0)) + 1
	else:
		bag.append(l.item)
	spawn_text(l.position + Vector2(0, -70), "获得 " + l.label, l.color, 18)
	_bag_badge()
	if bag_ui.visible: bag_ui.refresh()
	save_game()

func _bag_badge() -> void:
	bag_btn.text = "背包 %d/%d%s" % [bag.size(), bag_capacity(), " 满!" if not bag_has_room() else ""]

func toggle_bag(pause := true) -> void:
	bag_ui.visible = not bag_ui.visible
	banner_t = 0.0; banner.modulate.a = 0.0
	if pause and not autotest:
		get_tree().paused = bag_ui.visible
	for u in units:
		if u.rig != null and not u.dead:
			u.rig.set_view("front" if bag_ui.visible else "side")
	if bag_ui.visible:
		var i := units.find(selected)
		bag_ui.hero_idx = i if i >= 0 else 0
		bag_ui.cur = null
		bag_ui.refresh()
	else:
		save_game()

func equip_item(u, it: Dictionary) -> void:
	var i := _bag_index(it)
	if i >= 0:
		bag.remove_at(i)
	var old = u.gear.get(it.slot)
	if old != null:
		bag.append(old)
	u.gear[it.slot] = it
	u.recalc_stats()
	_bag_badge()

func unequip(u, slot_id: String) -> void:
	var old = u.gear.get(slot_id)
	if old == null:
		return
	u.gear[slot_id] = null
	bag.append(old)
	u.recalc_stats()
	_bag_badge()

func _bag_index(it: Dictionary) -> int:
	for i in bag.size():
		if int(bag[i].uid) == int(it.uid):
			return i
	return -1

## 强化（v0.4）：成功率 = 当前方案成功率 + 祝福值（每次失败 +blessing_per_fail，成功清零）；
## 失败掉 fail_drop[级] 级但不低于 safe_floor[级]；试玩版 +0~+10 的 fail_drop 全是 0，所以失败不掉级。
## 消耗（绑银/炼器石）只显示不扣：样品没有货币系统
func enhance_item(it: Dictionary, u) -> Dictionary:
	var lv: int = int(it.enhance)
	if lv >= db.enhance_cap_for(it):
		return {"ok": false, "level": lv, "capped": true}
	var bl: float = float(it.get("blessing", 0.0))
	var ok: bool = randf() < db.enhance_success_rate(lv, bl)
	if ok:
		it.enhance = lv + 1
		if db.blessing_reset_on_success(): it.blessing = 0.0
	else:
		it.enhance = db.enhance_fail_level(lv)
		it.blessing = bl + db.blessing_per_fail()
	if u != null:
		var before: int = u.enh_tier
		u.recalc_stats()
		if u.enh_tier > before:
			_show_banner("%s 全身强化特效第 %d 档！" % [u.display_name, u.enh_tier])
	return {"ok": ok, "level": int(it.enhance), "from": lv}

func socket(it: Dictionary, i: int, key: String, u) -> void:
	if int(gems.get(key, 0)) <= 0 or it.sockets[i] != null:
		return
	gems[key] = int(gems[key]) - 1
	it.sockets[i] = {"id": key.split(":")[0], "lv": int(key.split(":")[1])}
	if u != null: u.recalc_stats()

func unsocket(it: Dictionary, i: int, u) -> void:
	var gm = it.sockets[i]
	if gm == null:
		return
	var k := "%s:%d" % [gm.id, int(gm.lv)]
	gems[k] = int(gems.get(k, 0)) + 1
	it.sockets[i] = null
	if u != null: u.recalc_stats()

## 宝石合成：同名同级 N 颗 → 下一级 1 颗（N 读规则，最高级 = 表里 levels 长度）
func devour_item(dst: Dictionary, src: Dictionary, u) -> Dictionary:
	var r: Dictionary = db.devour(dst, src)
	if not r.get("ok", false):
		return r
	var idx: int = _bag_index(src)
	if idx >= 0:
		bag.remove_at(idx)
	# 若材料穿着在身上，卸下
	for h in units:
		if h.team != "hero":
			continue
		for sid in h.gear:
			if h.gear[sid] != null and int(h.gear[sid].uid) == int(src.uid):
				h.gear[sid] = null
				h.recalc_stats()
	if u != null:
		u.recalc_stats()
	save_game()
	return r


func merge_gem(k: String) -> void:
	var gid: String = k.split(":")[0]; var lv: int = int(k.split(":")[1])
	var n: int = int(db.r.gem_merge_count)
	if int(gems.get(k, 0)) < n or lv >= db.gem_max_level(gid):
		return
	gems[k] = int(gems[k]) - n
	var nk := "%s:%d" % [gid, lv + 1]
	gems[nk] = int(gems.get(nk, 0)) + 1

# ---------- 刷怪 ----------
func start_farm() -> void:
	farm_loops += 1
	state = "playing"
	result_panel.visible = false
	get_tree().paused = false
	for u in units:
		if u.team == "hero":
			if u.dead:
				u.revive()
			u.hp = u.max_hp
	set_meta("farm_live", false)
	var nw: int = 0
	for j in cfg.waves.size():
		if cfg.waves[j].get("kind", "") != "challenge": nw += 1
	_spawn_wave((farm_loops - 1) % maxi(1, nw))
	set_meta("farm_live", true)

func _farm_process() -> void:
	if state == "playing" and get_meta("farm_live", false) and enemies().is_empty() and pending_spawn.is_empty():
		set_meta("farm_live", false)
		state = "win"
		result_label.text = "第 %d 轮刷怪完成\n掉落已进背包" % farm_loops
		result_panel.visible = true
		farm_btn.visible = true
		save_game()
		print("FARM: loop %d cleared" % farm_loops)

# ---------- 调试 ----------
func debug_drops() -> void:
	var plan := {"normal": 10, "elite": 5, "boss": 2}
	var n := 0
	for kind in plan:
		for k in int(plan[kind]):
			var items: Array = db.roll_drop(kind, region, 10 if kind == "boss" else 5, pity, "debug_boss" if kind == "boss" else "", true)
			for it in items:
				_assign_wtype(it)
				spawn_loot(Vector2(260 + (n % 8) * 105, 330 + (n / 8) * 95), it, "")
				n += 1
	for i in 3:
		var ids: Array = db.gem_by_id.keys()
		spawn_loot(Vector2(300 + i * 220, 600), {}, ids[randi() % ids.size()])
	spawn_text(Vector2(640, 280), "调试：生成 %d 件测试掉落" % n, Color(1, 0.9, 0.5), 22)

func debug_enhance_tier(k: int) -> void:
	var u = selected if selected != null and is_instance_valid(selected) else units[0]
	var ths: Array = db.fx_thresholds
	var target: int = 0 if k <= 0 else int(ths[mini(k, ths.size()) - 1])
	var its: Array = []
	for sid in u.gear:
		if u.gear[sid] != null: its.append(u.gear[sid])
	# 开局只有 3 个部位有装备（v0.4 starter_gear），不够堆到目标总强化时，给空部位补白装（调试用）
	if its.size() * db.item_cap < target:
		for sl in db.slots:
			if u.gear.get(sl.id) == null and its.size() * db.item_cap < target:
				var ni: Dictionary = db.make_item(sl.id, 0, 1, _hero_wtype(u) if sl.id == "weapon" else "")
				u.gear[sl.id] = ni; its.append(ni)
	if its.is_empty():
		return
	for it in its:
		it.enhance = 0
	var left := target
	var i := 0
	while left > 0 and i < its.size() * db.item_cap:
		var it: Dictionary = its[i % its.size()]
		if int(it.enhance) < db.item_cap:
			it.enhance = int(it.enhance) + 1; left -= 1
		i += 1
	u.recalc_stats()
	_show_banner("%s 全身强化 +%d → 特效 %d 档" % [u.display_name, u.enh_total, u.enh_tier])
	if bag_ui.visible: bag_ui.refresh()

func debug_reset() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	no_save = true
	_restart()

# ---------- 存档（user://） ----------
func save_game() -> void:
	if no_save:
		return
	var hs := []
	for u in units:
		if u.team == "hero":
			hs.append({"id": u.uid, "gear": u.gear})
	var d := {"save_version": 15, "table_version": db.t.get("version", ""), "bag": bag, "gems": gems, "silver": silver, "max_wave": max_wave, "boss_killed": boss_killed, "play_kills": play_kills, "play_drops": play_drops, "next_uid": db.next_uid, "heroes": hs, "endless_best": endless_best}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))

func _norm_item(it: Dictionary) -> Dictionary:
	for k in ["uid", "rarity", "level", "enhance"]:
		it[k] = int(it.get(k, 0))
	var socks: Array = it.get("sockets", [])
	for i in socks.size():
		if socks[i] != null:
			socks[i].lv = int(socks[i].lv)
	return it

func _load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY or not d.has("heroes"):
		return false
	if str(d.get("table_version", "")) != "1.3" or int(d.get("save_version", 0)) < 13:
		return false
	bag = []
	for it in d.bag:
		if db.slot_by_id.has(it.get("slot", "")):
			bag.append(_norm_item(it))
	gems = d.get("gems", {})
	silver = int(d.get("silver", 0))
	max_wave = clampi(int(d.get("max_wave", 1)), 1, cfg.waves.size())
	boss_killed = bool(d.get("boss_killed", false))
	_clamp_unlock()   # 旧存档/调试存档里没杀头目却解锁了挑战波的，压回头目波
	play_kills = d.get("play_kills", play_kills)
	play_drops = d.get("play_drops", play_drops)
	endless_best = int(d.get("endless_best", 0))
	db.next_uid = int(d.get("next_uid", 1))
	for h in d.heroes:
		for u in units:
			if u.uid == h.id:
				for s in db.slots:
					if not u.gear.has(s.id):
						u.gear[s.id] = null
				for sid in h.gear:
					if not u.gear.has(sid):
						u.gear[sid] = null
					u.gear[sid] = null if h.gear[sid] == null else _norm_item(h.gear[sid])
				u.recalc_stats(true)
	_ensure_test_leech_weapons()
	return true

# ---------- 自测 ----------
# ---------- 难度模拟 ----------
## 预设读 data/equipment_rules.json 的 sim_presets：每个部位按列表随机稀有度、等级、强化区间
func _apply_sim_gear(preset: String) -> void:
	var ps: Dictionary = db.r.get("sim_presets", {}).get(preset, {})
	if ps.get("use_new_game", false):
		set_meta("sim_auto_equip", ps.get("auto_equip", false))
		set_meta("sim_campaign", ps.get("campaign", false))
		set_meta("sim_campaign_cap", int(ps.get("max_attempts", 30)))
		set_meta("sim_retry_mode", ps.get("retry_from", "max"))
		return   # 「开局实际装备」：保持 _new_game 发的 starter_gear
	if ps.is_empty():
		push_error("未知 sim 预设：" + preset)
		return
	for u in units:
		if u.team != "hero":
			continue
		for sl in db.slots:
			var rs: Array = ps.rarities
			var ri: int = db.rarity_idx[rs[randi() % rs.size()]]
			var it: Dictionary = db.make_item(sl.id, ri, int(ps.level), _hero_wtype(u) if sl.id == "weapon" else "")
			var er: Array = ps.enhance
			it.enhance = mini(db.item_cap, randi_range(int(er[0]), int(er[1])))
			u.gear[sl.id] = it
		u.recalc_stats(true)

var sim_min_hp := 1.0
func _sim_step() -> void:
	for h in units:
		if h.team == "hero":
			sim_min_hp = minf(sim_min_hp, 0.0 if h.dead else h.hp / h.max_hp)
	if get_meta("sim_campaign", false) and state != "playing" and not has_meta("sim_done"):
		var cap: int = int(get_meta("sim_campaign_cap", 30))
		if state == "win":
			camp_ch = {"attempt": camp_attempts, "time": elapsed}
		if state == "lose" and camp_attempts < cap:
			_camp_retry()
			return
		set_meta("sim_done", true)
		print("CAMPAIGN boss_attempt=%d boss_time=%.1f ch_attempt=%d ch_time=%.1f attempts=%d total=%.1f max_wave=%d" % [int(camp_boss.get("attempt", -1)), float(camp_boss.get("time", -1)), int(camp_ch.get("attempt", -1)), float(camp_ch.get("time", -1)), camp_attempts, elapsed, max_wave])
		get_tree().quit()
		return
	if state != "playing" and not has_meta("sim_done"):
		set_meta("sim_done", true)
		var alive := heroes()
		var low := 0
		for h in alive:
			low = low + (1 if h.hp < h.max_hp * 0.3 else 0)
		print("SIM preset=%s result=%s time=%.1f alive=%d low=%d wave=%d minhp=%.2f cleared=%d wt=%s" % [sim_preset, state, elapsed, alive.size(), low, wave_idx + 1, sim_min_hp, wave_times.size(), ",".join(wave_times.map(func(x): return "%.1f" % x))])
		get_tree().quit()
	elif elapsed > (40000.0 if get_meta("sim_campaign", false) else 900.0) and not has_meta("sim_done"):
		set_meta("sim_done", true)
		print("SIM preset=%s result=timeout time=%.1f alive=%d low=0 wave=%d minhp=%.2f cleared=%d wt=%s" % [sim_preset, elapsed, heroes().size(), wave_idx + 1, sim_min_hp, wave_times.size(), ",".join(wave_times.map(func(x): return "%.1f" % x))])
		get_tree().quit()

## 模拟用的「输了从最高波次重打」：和游戏里 retry_from 等价（背包/装备保留、英雄满血、地上掉落先捡起），只是不重载场景
func _camp_retry() -> void:
	camp_attempts += 1
	for l in fx_layer.get_children():
		if l is LootScript and not l.picked: l.pickup()
	for e in enemies():
		units.erase(e); e.queue_free()
	pending_spawn.clear()
	for u in units:
		if u.team == "hero":
			if u.dead: u.revive()
			u.hp = u.max_hp
	result_panel.visible = false
	state = "playing"
	cleared_set.clear()
	_spawn_wave(0 if get_meta("sim_retry_mode", "max") == "first" else max_wave - 1)

func _autotest_step() -> void:
	var shots_on := DisplayServer.get_name() != "headless"
	var since: float = elapsed - float(get_meta("wave_start", 0.0))
	# 第 1 波：调试掉落 → 自动拾取
	if wave_idx == 0 and since > 1.0 and not has_meta("dbg_drop"):
		set_meta("dbg_drop", true)
		debug_drops()
		print("AUTOTEST debug drops spawned")
		if shots_on:
			_shot_seq_battle()
	# 第 2 波开始：每人穿最好的装备、镶宝石、强化，打印属性与全身特效档
	if wave_idx == 1 and not has_meta("equip_done"):
		set_meta("equip_done", true)
		_auto_equip_best()
		var w = units[0]
		for sid in w.gear:
			var it = w.gear[sid]
			if it == null: continue
			it.enhance = mini(int(it.enhance), 7)
			for i in 3:
				enhance_item(it, w)
		# 背包满 / 一键出售自测（有界面时在截图流程里做）
		var before := bag.size()
		if shots_on: before = -1
		var room_full := false; var sr := {"n": 0, "silver": 0}
		if not shots_on:
			while bag.size() < bag_capacity():
				bag.append(db.make_item(db.random_slot(), 0, 5, ""))
			bag[0].locked = true
			room_full = not bag_has_room()
			sr = sell_junk()
		print("AUTOTEST bag full=%s (cap %d, had %d) sell_junk sold=%d silver+=%d bag_now=%d locked_kept=%s" % [str(room_full), bag_capacity(), before, sr.n, sr.silver, bag.size(), str(bag.all(func(x): return not (db.rarity_name(int(x.rarity)) in ["白", "绿"]) or x.get("locked", false)))])
		for u in heroes():
			print("AUTOTEST %s: hp=%d atk=%d def=%d crit=%.1f%% 全身强化+%d 特效%d档 外观=%s 武器=%s" % [u.display_name, int(u.max_hp), int(u.atk), int(u.def), u.crit, u.enh_total, u.enh_tier, tier_name(u.appearance_tier), tier_name(u.weapon_tier)])
		print("AUTOTEST bag=%d gems=%d drops_so_far=%d fx_thresholds=%s (%s) item_cap=%d profile=%s" % [bag.size(), gems.size(), drop_log.size(), str(db.fx_thresholds), db.fx_source, db.item_cap, db.profile_key])
		if shots_on:
			_shot_seq_bag()
	# 满屏一波（第四波）与挑战波截图
	if shots_on and wave_idx == 3 and since > 1.2 and not has_meta("shot_w4") and not get_meta("busy", false):
		set_meta("shot_w4", true); _shot_quick("equip_wave_full_battle")
	if shots_on and wave_idx == 5 and since > 2.0 and not has_meta("shot_ch") and not get_meta("busy", false):
		set_meta("shot_ch", true); _shot_quick("equip_challenge_wave")
	if state == "win" and farm_loops == 0 and not has_meta("farm_started"):
		set_meta("farm_started", true)
		start_farm()
		print("AUTOTEST farm started")
	if farm_loops >= 1 and state == "win" and not has_meta("quit_at"):
		set_meta("quit_at", elapsed)
	if state == "lose" and not has_meta("quit_at"):
		set_meta("quit_at", elapsed)
	if has_meta("quit_at") and elapsed - float(get_meta("quit_at")) > 1.0 and not get_meta("busy", false):
		var hi := 0
		for it in drop_log:
			hi = maxi(hi, int(it.rarity))
		print("AUTOTEST drops total=%d highest=%s" % [drop_log.size(), tier_name(hi)])
		get_tree().quit()
	if elapsed > 600.0:
		print("RESULT: timeout")
		get_tree().quit()

func _score(it) -> float:
	# 粗估装备强度：主属性绝对值之和 + 等级/品质微差。强化按整数加值计入 item_stats。
	if it == null: return -1.0
	var st: Dictionary = db.item_stats(it)
	var s := 0.0
	for k in st:
		s += abs(float(st[k]))
	return s + float(it.level) * 0.01 + float(it.rarity) * 2.0 + float(it.get("skills", []).size()) * 8.0

func _auto_equip_best() -> void:
	for u in units:
		if u.team != "hero":
			continue
		for s in db.slots:
			var best = u.gear.get(s.id)
			for it in bag:
				if it.slot == s.id and bag_ui._can_equip(u, it) == "" and _score(it) > _score(best):
					best = it
			if best != null and best != u.gear.get(s.id):
				equip_item(u, best)
			var cur = u.gear.get(s.id)
			if cur != null:
				for i in cur.sockets.size():
					if cur.sockets[i] == null:
						for k in gems.keys():
							if int(gems[k]) > 0 and s.id in db.gem_by_id[k.split(":")[0]].slots:
								socket(cur, i, k, u); break

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func _shot_seq_battle() -> void:
	set_meta("busy", true)
	await _wait(0.35)
	await _shot_named("equip_drops_battle")
	set_meta("busy", false)

func _freeze_heroes_at(xs: Array) -> void:
	for i in xs.size():
		var u = units[i]
		u.position = Vector2(xs[i], 470); u.move_target = null; u.facing = 1.0
	for e in enemies():
		e.position = Vector2(1180, e.position.y)

func _shot_seq_bag() -> void:
	set_meta("busy", true)
	# 全身强化特效 4 档：先 1/2/3 档三人并排，再单独 4 档
	Engine.time_scale = 0.0001
	_select(units[0]); debug_enhance_tier(1)
	_select(units[1]); debug_enhance_tier(2)
	_select(units[2]); debug_enhance_tier(3)
	_select(null)
	_freeze_heroes_at([260, 560, 860])
	Engine.time_scale = 0.05
	await _wait(1.0)
	Engine.time_scale = 0.0001
	_freeze_heroes_at([260, 560, 860])
	await _shot_named("equip_fx_tier1-3_battle")
	_select(units[0]); debug_enhance_tier(4); _select(null)
	_select(units[1]); debug_enhance_tier(0); _select(null)
	_select(units[2]); debug_enhance_tier(0); _select(null)
	_freeze_heroes_at([560, 300, 860])
	Engine.time_scale = 0.05
	await _wait(1.0)
	Engine.time_scale = 0.0001
	_freeze_heroes_at([560, 300, 860])
	await _shot_named("equip_fx_tier4_battle")
	# 再来一批测试掉落，直接拾取，让背包里有各种稀有度
	debug_drops()
	for l in fx_layer.get_children():
		if l is LootScript: l.pickup()
	_select(units[0]); debug_enhance_tier(2)
	toggle_bag(false)
	bag_ui.hero_idx = 0; bag_ui.filter = ""; bag_ui.refresh()
	await _wait(0.3)
	await _shot_named("equip_bag")
	# 背包满 → 一键出售白绿（锁住一件白装，确认不会被卖）
	while bag.size() < bag_capacity():
		bag.append(db.make_item(db.random_slot(), randi() % 2, 5, ""))
	bag[bag.size() - 1].locked = true
	var lk = bag[bag.size() - 1]
	bag_ui.refresh()
	# 背包满时地上的装备不会被捡
	spawn_loot(Vector2(640, 400), db.make_item("ring", 1, 5, ""), "")
	await _wait(0.3)
	await _shot_named("equip_bag_full")
	bag_ui._on_sell()
	await _wait(0.3)
	print("AUTOTEST sell: bag=%d silver=%d locked_kept=%s" % [bag.size(), silver, str(lk in bag)])
	await _shot_named("equip_bag_sold")
	# 详情 + 对比：挑背包里战士能穿、稀有度最高的一件
	var best = null
	for it in bag:
		if bag_ui._can_equip(units[0], it) == "" and (best == null or it.rarity > best.rarity or (it.rarity == best.rarity and it.sockets.size() > best.sockets.size())):
			best = it
	if best != null:
		bag_ui._open(best, false)
		await _wait(0.3)
		await _shot_named("equip_detail_compare")
		# 镶一颗宝石再截（若有孔）
		if not best.sockets.is_empty():
			bag_ui._socket_click(0)
			await _wait(0.3)
			await _shot_named("equip_socket_picker")
			for k in gems.keys():
				if int(gems[k]) > 0 and best.slot in db.gem_by_id[k.split(":")[0]].slots:
					socket(best, 0, k, null); break
			bag_ui.picker.visible = false
	# 强化：打开已穿戴的武器，连点强化
	var wpn = units[0].gear.weapon
	bag_ui._open(wpn, true)
	for i in 4:
		bag_ui._on_enhance()
	await _wait(0.3)
	await _shot_named("equip_enhance")
	toggle_bag(false)
	await _shot_look_tier()
	for i in 3:
		_select(units[i]); debug_enhance_tier(0)
	_select(units[0])
	Engine.time_scale = 3.0
	set_meta("busy", false)

## 外观档规则截图：三人都穿紫饰品+紫腰带，只改衣服/头盔 → 外观 = 两件里较低的
func _shot_look_tier() -> void:
	var saved: Array = []
	for i in 3: saved.append(units[i].gear.duplicate())
	var combos := [[0, 0], [3, 2], [3, 3]]   # [衣服, 头盔] 稀有度
	Engine.time_scale = 0.0001
	for c in fx_layer.get_children(): c.queue_free()
	for i in 3:
		var u = units[i]
		for sl in db.slots:
			u.gear[sl.id] = db.make_item(sl.id, 3, 10, _hero_wtype(u) if sl.id == "weapon" else "")
		u.gear.chest = db.make_item("chest", combos[i][0], 10, "")
		u.gear.head = db.make_item("head", combos[i][1], 10, "")
		u.look_override = -1; u.weapon_override = -1
		u.recalc_stats(true)
		print("AUTOTEST look: %s 衣服=%s 头盔=%s 饰品/腰带=紫 → 外观=%s" % [u.display_name, tier_name(combos[i][0]), tier_name(combos[i][1]), tier_name(u.appearance_tier)])
	_freeze_heroes_at([300, 640, 980])
	for i in 3:
		spawn_text(Vector2([300, 640, 980][i], 300), "衣%s 盔%s → 外观%s" % [tier_name(combos[i][0]), tier_name(combos[i][1]), tier_name(units[i].appearance_tier)], Color(1, 0.95, 0.6), 24)
	Engine.time_scale = 0.05
	await _wait(0.5)
	Engine.time_scale = 0.0001
	_freeze_heroes_at([300, 640, 980])
	await _shot_named("equip_look_tier_rule")
	for i in 3:
		units[i].gear = saved[i]; units[i].recalc_stats(true)

## 开局装备截图：--shot-starter（新存档，背包里看战士的开局 10 件白装），截完退出
func _shot_starter() -> void:
	await _wait(0.6)
	await _shot_named("equip_start_battle")
	toggle_bag(false)
	bag_ui.hero_idx = 0; bag_ui.filter = ""; bag_ui.refresh()
	await _wait(0.3)
	await _shot_named("equip_starter_set")
	get_tree().quit()

## 重打入口截图：--shot-retry（假设已解锁到挑战波：第 5 波头目战败的失败界面，再截开局选波次界面）
## 开局选波次截图（调试状态：假设已经真正杀过头目、解锁到挑战波）。失败界面截图改用 --test-clean-defeat 的真实流程
func _shot_retry() -> void:
	max_wave = cfg.waves.size(); boss_killed = true
	await _wait(0.3)
	_show_start_panel("campaign")
	await _wait(0.4)
	await _shot_named("retry_start_wave_picker")
	get_tree().paused = false
	get_tree().quit()

## 干净存档端到端测试：--test-clean-defeat（需先删 user://save_equip.json）。开局装备真实开打，
## 输了就走真正的 retry_from（重载场景、读存档）从已解锁最高波次重打，直到在第 5 波（头目）输掉，打印状态并截图
func _clean_defeat_step() -> void:
	if state == "lose" and not has_meta("cd_done"):
		set_meta("cd_done", true)
		var att: int = int(Engine.get_meta("cd_attempt", 1))
		print("CLEANTEST attempt=%d lost_on_wave=%d max_wave=%d boss_killed=%s retry_btn='%s' picker=%d farm_btn_visible=%s hint_visible=%s" % [att, wave_idx + 1, max_wave, str(boss_killed), retry_btn.text, maxi(0, retry_box.get_child_count() - 1), str(farm_btn.visible), str(farm_hint.visible)])
		if wave_idx + 1 == boss_wave_no() or att >= 40:
			await _wait(0.5)
			if DisplayServer.get_name() != "headless":
				await _shot_named("retry_defeat_screen")
			get_tree().quit()
		else:
			Engine.set_meta("cd_attempt", att + 1)
			await _wait(0.3)
			retry_from(max_wave)
	elif state == "win" and not has_meta("cd_done"):
		set_meta("cd_done", true)
		print("CLEANTEST unexpected win, max_wave=%d boss_killed=%s" % [max_wave, str(boss_killed)])
		get_tree().quit()

## 任意职业穿剑截图：--shot-free-equip（法师打开背包，看一把紫剑的对比，再穿上）
func _shot_free_equip() -> void:
	await _wait(0.5)
	var sw: Dictionary = db.make_item("weapon", 3, 10, "sword")
	bag.append(sw)
	toggle_bag(false)
	var mi := 0
	for i in cfg.heroes.size():
		if cfg.heroes[i].id == "mage": mi = i
	bag_ui.hero_idx = mi; bag_ui.filter = "weapon"; bag_ui.refresh()
	bag_ui._open(sw, false)
	await _wait(0.3)
	print("FREETEST mage can_equip_sword='%s' (空 = 可以)" % bag_ui._can_equip(units[mi], sw))
	await _shot_named("free_equip_mage_sword_compare")
	bag_ui._on_equip()
	await _wait(0.3)
	print("FREETEST mage weapon now: %s (%s)" % [units[mi].gear.weapon.name, units[mi].gear.weapon.wtype])
	await _shot_named("free_equip_mage_sword_equipped")
	get_tree().quit()

func _shot_quick(name: String) -> void:
	set_meta("busy", true)
	await _shot_named(name)
	set_meta("busy", false)

func _shot_named(name: String) -> void:
	banner_t = 0.0; banner.modulate.a = 0.0
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://") + "截图/" + name + "_iphone.png"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("AUTOTEST screenshot ", path, " ", img.get_size())

func _shot(name: String) -> void:
	shots += 1
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://") + "截图/" + name
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("AUTOTEST screenshot ", path)



## 装备详情卡截图：--shot-tooltip（普通单件 / 超长分列 / 对比）。仅测试用，不改变试玩爆率。
func _shot_tooltip() -> void:
	no_save = true
	if start_panel != null and start_panel.visible:
		_start_at(1)
	await _wait(0.35)
	await _shot_named("ui_font_hud")
	_copy_shot_workspace("ui_font_hud_iphone.png", "ui_font_hud_raw.png")
	var title_it: Dictionary = db.make_item("title", 3, 10, "")
	title_it.set_id = ""
	var wpn_it: Dictionary = db.make_item("weapon", 5, 10, "sword")
	wpn_it.enhance = 10
	var long_it: Dictionary = _make_long_tooltip_item()
	if bag_has_room():
		bag.append(title_it)
	if bag_has_room():
		bag.append(wpn_it)
	if bag_has_room():
		bag.append(long_it)
	var w = units[0]
	if w != null:
		for sid in ["necklace", "earring", "legs", "hands", "chest"]:
			var git = w.gear.get(sid)
			if git != null:
				git.set_id = "tixiu"
		if w.gear.get("title") != null:
			unequip(w, "title")
	if not bag_ui.visible:
		toggle_bag()
	bag_ui.hero_idx = 0
	bag_ui.filter = ""
	bag_ui.refresh()
	await _wait(0.3)
	await _shot_named("ui_font_bag")
	_copy_shot_workspace("ui_font_bag_iphone.png", "ui_font_bag_raw.png")
	# 1. 普通短卡片（部位为空）
	bag_ui._open(title_it, false)
	await _wait(0.35)
	await _shot_named("ui_font_single")
	_copy_shot_workspace("ui_font_single_iphone.png", "ui_font_single_raw.png")
	# 2. 超长单件（卸下武器，词条+技能+套装很多，应分列且无滚动条）
	var worn_wpn = w.gear.get("weapon") if w != null else null
	if w != null and worn_wpn != null:
		unequip(w, "weapon")
	bag_ui._open(long_it, false)
	await _wait(0.4)
	await _shot_named("ui_font_long")
	_copy_shot_workspace("ui_font_long_iphone.png", "ui_font_long_raw.png")
	# 3. 对比：把原来的武器穿回去，再点超长武器
	if w != null and worn_wpn != null:
		equip_item(w, worn_wpn)
	bag_ui._open(long_it, false)
	await _wait(0.4)
	await _shot_named("ui_font_compare")
	_copy_shot_workspace("ui_font_compare_iphone.png", "ui_font_compare_raw.png")
	print("TOOLTIPSHOT done")
	get_tree().quit()

func _make_long_tooltip_item() -> Dictionary:
	var it: Dictionary = db.make_item("weapon", 6, 50, "sword")
	it.enhance = 20
	it.set_id = "tixiu"
	it.affixes = [
		{"key": "atk", "value": 24}, {"key": "atk_pct", "value": 10},
		{"key": "aspd", "value": 10}, {"key": "crit", "value": 8},
		{"key": "critdmg", "value": 20}, {"key": "acc", "value": 6},
		{"key": "hp", "value": 80}, {"key": "def", "value": 15},
		{"key": "ms", "value": 8}, {"key": "skill", "value": 12}
	]
	it.skills = []
	for sk in db.t.get("skill_affixes", []):
		it.skills.append(sk)
		if it.skills.size() >= 6:
			break
	for want in ["cangfeng_yi", "yinwu_pi"]:
		for sk in db.t.get("skill_affixes", []):
			if str(sk.get("id", "")) == want:
				it.skills.append(sk)
				break
	while it.sockets.size() < 3:
		it.sockets.append(null)
	return it

func _copy_shot_workspace(from_name: String, to_name: String) -> void:
	var src := ProjectSettings.globalize_path("res://") + "截图/" + from_name
	var dest_dir := "/workspace/tooltip_shots"
	DirAccess.make_dir_recursive_absolute(dest_dir)
	var dst := dest_dir + "/" + to_name
	if FileAccess.file_exists(src):
		DirAccess.copy_absolute(src, dst)
		print("TOOLTIPSHOT copied ", dst)

func _refresh_play_stats() -> void:
	if play_stats_lbl == null:
		return
	var total_k: int = int(play_kills.get("normal", 0)) + int(play_kills.get("elite", 0)) + int(play_kills.get("boss", 0))
	var total_d: int = 0
	for q in play_drops:
		total_d += int(play_drops[q])
	play_stats_lbl.text = "试玩统计（真实爆率，无作弊）\n击杀：普通 %d  精英 %d  头目 %d  共 %d\n掉落：白%d 绿%d 蓝%d 紫%d 橙%d 红%d 暗金%d  共 %d\n没有保底，每只怪单独掷点。" % [
		int(play_kills.get("normal", 0)), int(play_kills.get("elite", 0)), int(play_kills.get("boss", 0)), total_k,
		int(play_drops.get("白", 0)), int(play_drops.get("绿", 0)), int(play_drops.get("蓝", 0)), int(play_drops.get("紫", 0)),
		int(play_drops.get("橙", 0)), int(play_drops.get("红", 0)), int(play_drops.get("暗金", 0)), total_d
	]
