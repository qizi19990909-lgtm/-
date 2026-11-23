extends Node2D
## 样品用单位：英雄与怪物共用。数值来自 data/config.json。

const UiScale := preload("res://scripts/ui_scale.gd")
var main  # main.gd
var team := "hero"          # "hero" / "enemy"
var uid := ""
var display_name := ""
var data := {}
var max_hp := 100.0
var hp := 100.0
var atk := 10.0
var def := 0.0
var attack_range := 60.0
var interval := 1.0
var speed := 100.0
var ranged := false
var size := 1.0
var body_color := Color.WHITE
var dead := false
var selected := false
var move_target = null       # Vector2 或 null
var target = null
var atk_timer := 0.5
var skill_timer := 0.0
var skill := {}
var facing := 1.0
var radius := 26.0
var t := 0.0
var lunge := 0.0
var flash := 0.0
var windup := 0.0           # Boss 震地蓄力
# 装备：slot_id -> 装备字典（scripts/equip_db.gd 生成）或 null；数值全部来自 data/equipment.json
var gear := {}
var appearance_tier := 0
var weapon_tier := 0
var look_override := -1      # 截图/调试工具用：强制外观档
var weapon_override := -1
var stats := {}              # equip_db.hero_stats 的结果
# 公式用属性（§1.1）
var level := 1
var acc := 0.0
var eva := 0.0
var crit := 5.0
var critdmg := 150.0
var skill_pct := 0.0
var regen := 0.0
var leech := 0
var skill_leech := 0
var hit_heal := 0
var elem := {}
var res := {}
var kind := "normal"         # 怪物类型 normal / elite / boss
var base_interval := 1.0
var base_speed := 100.0
var enh_total := 0
var enh_tier := 0
# 属性叠层（§1.2）
var stacks := {}
var stack_t := {}
var immune := {}
var hit_down := 0.0
var hit_down_t := 0.0
var slow := 0.0
var slow_t := 0.0
var stun_t := 0.0
var fear_t := 0.0
var fear_dir := Vector2.ZERO
var burn_atk := 0.0
var burn_acc := 0.0
var regen_acc := 0.0

var body: Node2D             # AnimatedSprite2D / Sprite2D / null（怪物用图形）
var overlay: Node2D
var base_scale := 1.0
var outline_mat: ShaderMaterial
var weapon: Node2D           # 武器层（挂在 body 下，跟随动画/朝向）
var weapon_mat: ShaderMaterial
var rig: Node2D              # 剑修七品阶外观（scripts/swordsman_rig.gd）；有它时不用 body/weapon
var threat := {}             # 怪物仇恨：hero.uid -> 数值
var taunt_until := 0.0
var taunt_target = null
var buffs := {}              # stat -> {value, until}
var gear_skill_cd := {}
var hit_count := 0
var moved_flag := false
var next_hit_bonus := 0.0
var shield_hp := 0.0
var self_threat_mul := 1.0
var last_attacker = null
const RigScript := preload("res://scripts/swordsman_rig.gd")

# 衣服换色：按外观档把衣服重新上色（皮肤、头发、眼白保留原色），整体描边发光
const BODY_SHADER := """
shader_type canvas_item;
uniform vec4 tier_color : source_color = vec4(1.0);
uniform float strength = 0.0;   // 0 = 白装原色
uniform float width = 0.0;      // 描边宽度（贴图像素）
uniform float shimmer = 0.0;    // 高档流光
varying vec4 v_mod;
void vertex() { v_mod = COLOR; }
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 hsv = rgb2hsv(c.rgb);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	// 皮肤：浅肉色；眼白/高光：接近白；这些不换色
	float skin = step(hsv.x, 0.14) * step(hsv.y, 0.5) * step(0.62, hsv.z);
	float white = step(hsv.y, 0.12) * step(0.85, hsv.z);
	// 中等亮度以上的布料：全力换色；头发、描边等深色不动；深色裤子/靴子（最下部）轻微染色
	float cloth = smoothstep(0.30, 0.45, hsv.z) * (1.0 - skin) * (1.0 - white);
	float dark = (1.0 - smoothstep(0.30, 0.45, hsv.z)) * smoothstep(0.74, 0.82, UV.y) * 0.5;
	vec3 dyed = clamp(tier_color.rgb * (0.35 + lum * 1.5), 0.0, 1.0);
	vec3 col = mix(c.rgb, dyed, strength * max(cloth, dark));
	float band = 1.0 - smoothstep(0.0, 0.07, abs(fract(UV.x * 0.7 + UV.y * 0.7 - TIME * 0.45) - 0.5));
	col += vec3(1.0, 0.95, 0.8) * band * shimmer * 0.45 * cloth;
	float a = 0.0;
	if (width > 0.0) {
		for (int i = 0; i < 12; i++) {
			float ang = float(i) * 0.5236;
			vec2 d = vec2(cos(ang), sin(ang)) * TEXTURE_PIXEL_SIZE * width;
			a = max(a, texture(TEXTURE, UV + d).a);
			a = max(a, texture(TEXTURE, UV + d * 0.5).a);
		}
	}
	vec4 o = vec4(tier_color.rgb, a * tier_color.a);
	COLOR = mix(o, vec4(col, c.a), c.a) * v_mod;
}
"""

# 武器层：从立绘里抠出的武器（tools/extract_weapon_layers.py），按武器品质重新上色 + 发光
const WEAPON_SHADER := """
shader_type canvas_item;
uniform vec4 tier_color : source_color = vec4(1.0);
uniform float strength = 0.0;
uniform float glow = 0.0;       // 发光半径（贴图像素）
uniform float shimmer = 0.0;
uniform float keep_skin = 0.0;  // 剑修剑层里带着握剑的手：手（肤色）不染色
varying vec4 v_mod;
void vertex() { v_mod = COLOR; }
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float mx = max(c.r, max(c.g, c.b)); float mn = min(c.r, min(c.g, c.b));
	float sat = (mx - mn) / (mx + 1e-5);
	float skin = keep_skin * step(c.b + 0.04, c.g) * step(c.g + 0.03, c.r) * step(0.10, sat) * step(sat, 0.55) * step(0.55, mx);
	// 武器比衣服更亮：底色提亮 + 白色高光，保证和同档衣服也能区分
	vec3 dyed = clamp(mix(tier_color.rgb, vec3(1.0), 0.25) * (0.75 + lum * 0.9) + vec3(smoothstep(0.6, 1.0, lum) * 0.6), 0.0, 1.0);
	vec3 col = mix(c.rgb, dyed, strength * (1.0 - skin));
	float band = 1.0 - smoothstep(0.0, 0.08, abs(fract(UV.x * 1.2 - UV.y * 0.8 - TIME * 0.8) - 0.5));
	col += vec3(1.0) * band * shimmer * 0.6 * (1.0 - skin);
	float g = 0.0;
	if (glow > 0.0) {
		for (int i = 0; i < 12; i++) {
			float ang = float(i) * 0.5236;
			vec2 d = vec2(cos(ang), sin(ang)) * TEXTURE_PIXEL_SIZE * glow;
			g = max(g, texture(TEXTURE, UV + d).a * 0.55);
			g = max(g, texture(TEXTURE, UV + d * 0.6).a * 0.8);
			g = max(g, texture(TEXTURE, UV + d * 0.3).a);
		}
	}
	float pulse = 0.8 + 0.2 * sin(TIME * 5.0);
	vec4 o = vec4(mix(tier_color.rgb, vec3(1.0), 0.15), g * pulse);
	COLOR = mix(o, vec4(col, 1.0), c.a) * v_mod;
}
"""

func setup_hero(cfg: Dictionary, m) -> void:
	main = m
	team = "hero"
	data = cfg
	uid = cfg.id
	display_name = cfg.name
	ranged = cfg.ranged
	# v1.3：角色不带主动技能，技能来自装备词条
	skill = {}
	attack_range = cfg.range
	base_interval = cfg.interval
	base_speed = cfg.speed
	level = int(main.db.r.get("hero_level", 10))
	for s in main.db.slots:
		gear[s.id] = null
	_make_hero_body()
	recalc_stats(true)

## 数值（hp/atk/def/命中/闪避/抗性/攻击间隔/等级/Boss 技能倍率）来自 equipment.json monsters；
## config.json 只留表里没有的：名字、射程、移速、体型、颜色、技能类型
func setup_monster(mkind: String, cfg: Dictionary, m, mlevel := -1) -> void:
	main = m
	team = "enemy"
	data = cfg
	uid = mkind
	if mlevel < 0: mlevel = int(main.db.r.hero_level)
	# 挑战波新怪：base 指向表里的怪，按 base 的 coef × g(等级) 再乘 mult（挑战波专用，可调）
	var ms: Dictionary = main.db.monster_stats(str(cfg.get("base", mkind)), mlevel)
	if cfg.has("base"):
		ms = ms.duplicate(true)
		var mu: Dictionary = cfg.get("mult", {})
		for k in ["hp", "atk", "def"]:
			ms[k] = float(ms.get(k, 0)) * float(mu.get(k, 1.0))
		ms.kind = cfg.get("kind", ms.get("kind", "normal"))
		ms.name = cfg.get("name", ms.get("name", mkind))
	set_meta("bind_silver", int(ms.get("bind_silver", 0)))
	display_name = ms.get("name", cfg.get("name", mkind))
	max_hp = int(ms.get("hp", cfg.get("hp", 100))); hp = max_hp
	atk = int(ms.get("atk", cfg.get("atk", 10))); def = int(ms.get("def", cfg.get("def", 0)))
	threat = {}
	taunt_until = 0.0
	taunt_target = null
	attack_range = cfg.range; interval = float(ms.get("attack_interval_s", cfg.get("interval", 1.0))); speed = cfg.speed
	base_interval = interval; base_speed = speed
	var mr: Dictionary = ms
	kind = mr.get("kind", "normal")
	level = mlevel
	eva = float(mr.get("eva_pct", 0.0))
	acc = float(mr.get("acc_pct", 0.0))
	var cr: Dictionary = main.db.r.crit
	crit = float(cr.base_rate_pct); critdmg = float(cr.base_dmg_pct)
	var cap: float = float(main.db.t.formula.get("caps", {}).get("monster_res_pct", 100))
	for e in main.db.elements:
		res[e] = minf(float(mr.get("res", {}).get(e, 0.0)), cap)
		elem[e] = 0.0
	size = cfg.size
	radius = 22.0 * size
	body_color = Color(cfg.color)
	skill = cfg.get("skill", {}).duplicate()
	var ts: Dictionary = ms.get("skill", {})
	if not ts.is_empty():
		skill.name = ts.get("name", skill.get("name", ""))
		if ts.has("mult"): skill.mult = float(ts.mult)
		if ts.has("cd_s"): skill.cd = float(ts.cd_s)
		if ts.has("radius"): skill.radius = float(ts.radius)
		if ts.has("windup_s"): skill.windup = float(ts.windup_s)
	if not skill.is_empty():
		skill_timer = skill.cd * 0.6
	_make_overlay()

func _make_hero_body() -> void:
	var mat := ShaderMaterial.new()
	var sh := Shader.new(); sh.code = BODY_SHADER
	mat.shader = sh
	outline_mat = mat
	weapon_mat = ShaderMaterial.new()
	var wsh := Shader.new(); wsh.code = WEAPON_SHADER
	weapon_mat.shader = wsh
	var pad: float = main.WEAPON_PAD
	if uid == "warrior" and not main.sw_body.is_empty():
		# 剑修：七档独立外观 + 代码动作 + 分层特效
		weapon_mat.set_shader_parameter("keep_skin", 1.0)
		rig = RigScript.new()
		add_child(rig)
		rig.setup(main, weapon_mat)
		_make_overlay()
		return
	if uid == "warrior":
		var a := AnimatedSprite2D.new()
		a.sprite_frames = main.warrior_frames
		a.play("idle")
		a.centered = false
		var sz: Vector2 = main.warrior_size
		a.offset = Vector2(-sz.x * 0.5, -sz.y)
		base_scale = 115.0 / sz.y
		a.scale = Vector2.ONE * base_scale
		a.animation_finished.connect(_on_anim_finished)
		body = a
		var wa := AnimatedSprite2D.new()
		wa.sprite_frames = main.warrior_weapon_frames
		wa.animation = "idle"
		wa.speed_scale = 0.0
		wa.centered = false
		wa.offset = a.offset - Vector2(pad, pad)
		weapon = wa
	else:
		var s := Sprite2D.new()
		s.texture = load("res://assets/heroes/%s.png" % uid)
		s.centered = false
		var tsz: Vector2 = s.texture.get_size()
		s.offset = Vector2(-tsz.x * 0.5, -tsz.y)
		base_scale = 110.0 / tsz.y
		s.scale = Vector2.ONE * base_scale
		body = s
		var ws := Sprite2D.new()
		ws.texture = load("res://assets/heroes/%s_weapon.png" % uid)
		ws.centered = false
		ws.offset = s.offset - Vector2(pad, pad)
		weapon = ws
	body.material = outline_mat
	add_child(body)
	weapon.material = weapon_mat
	body.add_child(weapon)
	_make_overlay()

func _make_overlay() -> void:
	overlay = Node2D.new()
	overlay.z_index = 5
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)

# ---------- 装备与属性 ----------
func recalc_stats(full_heal := false) -> void:
	var db = main.db
	stats = db.hero_stats(gear, level)
	var ratio := hp / max_hp if max_hp > 0 else 1.0
	max_hp = int(stats.hp); atk = int(stats.atk); def = int(stats.def)
	acc = stats.acc; eva = stats.eva; crit = stats.crit; critdmg = stats.critdmg
	skill_pct = stats.skill; regen = stats.regen
	leech = int(stats.get("leech", 0))
	skill_leech = int(stats.get("skill_leech", 0))
	hit_heal = int(stats.get("hit_heal", 0))
	for e in db.elements:
		elem[e] = stats["elem_" + e]; res[e] = stats["res_" + e]
	var aspd_b: float = float(_buff_val("aspd"))
	var ms_b: float = float(_buff_val("ms"))
	var atk_b: float = float(_buff_val("atk_pct"))
	atk = main.db.iround(float(atk) * (1.0 + atk_b / 100.0) * (1.0 + _passive_atk_pct() / 100.0))
	interval = base_interval / (1.0 + (stats.aspd + aspd_b) / 100.0)
	speed = base_speed * (1.0 + (stats.ms + ms_b) / 100.0)
	enh_total = stats.enhance_total; enh_tier = stats.fx_tier
	hp = max_hp if full_heal else clampf(max_hp * ratio, 1.0, max_hp)
	# 外观 = config.look_tier_slots（衣服、头盔）里稀有度最低的一件（空槽算白）；饰品等不参与；武器单独显示
	var lowest := 99
	for s in db.slots:
		if not _counts_for_look(s):
			continue
		var it = gear.get(s.id)
		lowest = mini(lowest, 0 if it == null else int(it.rarity))
	appearance_tier = 0 if lowest == 99 else lowest
	weapon_tier = 0 if gear.get("weapon") == null else int(gear.weapon.rarity)
	if look_override >= 0: appearance_tier = look_override
	if weapon_override >= 0: weapon_tier = weapon_override
	_apply_appearance()

## 截图/调试：直接指定外观档与武器档（不改装备）
func debug_look(at: int, wt: int) -> void:
	look_override = at; weapon_override = wt
	recalc_stats(true)

func _counts_for_look(s: Dictionary) -> bool:
	var ls: Array = main.cfg.get("look_tier_slots", [])
	if ls.is_empty():
		return s.get("category", "") != "武器"
	return s.id in ls

func lowest_slot_name() -> String:
	var lowest := 99; var nm := ""
	for s in main.db.slots:
		if not _counts_for_look(s):
			continue
		var it = gear.get(s.id)
		var ri: int = 0 if it == null else int(it.rarity)
		if ri < lowest:
			lowest = ri; nm = s.name
	return nm

func _apply_appearance() -> void:
	if outline_mat == null:
		return
	if rig != null:
		# 剑修：换成该档整套贴图（不再调色）；武器层仍按武器档换色发光
		rig.set_tier(appearance_tier, main.tier_color(weapon_tier))
	# 外观档：衣服/头盔整体换成该档颜色；档越高描边越粗，橙及以上有流光
	var c: Color = main.tier_color(appearance_tier)
	var at := appearance_tier
	outline_mat.set_shader_parameter("tier_color", c)
	outline_mat.set_shader_parameter("strength", 0.0 if at == 0 else 0.85)
	outline_mat.set_shader_parameter("width", 0.0 if at == 0 else 3.0 + at * 1.5)
	outline_mat.set_shader_parameter("shimmer", 1.0 if at >= 4 else 0.0)
	# 武器档：武器本身换成该档颜色并发光，档越高光越大，橙及以上有流光
	var wc: Color = main.tier_color(weapon_tier)
	var wt := weapon_tier
	weapon_mat.set_shader_parameter("tier_color", wc)
	weapon_mat.set_shader_parameter("strength", 0.0 if wt == 0 else 1.0)
	weapon_mat.set_shader_parameter("glow", 0.0 if wt == 0 else 6.0 + wt * 2.5)
	weapon_mat.set_shader_parameter("shimmer", 1.0 if wt >= 4 else 0.0)
	queue_redraw()

# ---------- 主循环 ----------
func _process(delta: float) -> void:
	t += delta
	flash = maxf(0.0, flash - delta * 4.0)
	lunge = maxf(0.0, lunge - delta * 5.0)
	if dead:
		if rig != null:
			rig.update(delta, facing, false, 0.0)
		overlay.queue_redraw(); queue_redraw()
		return
	_tick_status(delta)
	if stun_t > 0.0:
		stun_t -= delta
		_refresh_visual(false)
		return
	if fear_t > 0.0:
		fear_t -= delta
		_step(fear_dir * speed * 0.8 * delta)
		_refresh_visual(true)
		return
	var slow_k := _slow_factor()
	atk_timer -= delta * slow_k
	if not skill.is_empty():
		skill_timer -= delta
	if windup > 0.0:
		windup -= delta
		if windup <= 0.0:
			_do_slam()
		_refresh_visual(false)
		return
	var moving := false
	if move_target != null:
		var d: Vector2 = move_target - position
		if d.length() < 6.0:
			move_target = null
		else:
			_step(d.normalized() * speed * _slow_factor() * delta)
			moving = true
	else:
		if target == null or not is_instance_valid(target) or target.dead:
			target = _pick_target()
		if team == "hero":
			_tick_gear_skills(delta)
		if target != null:
			var to: Vector2 = target.position - position
			facing = signf(to.x) if absf(to.x) > 2.0 else facing
			var reach: float = attack_range + target.radius * 0.5
			if not skill.is_empty() and skill_timer <= 0.0 and _try_skill():
				pass
			elif to.length() > reach:
				_step(to.normalized() * speed * _slow_factor() * delta)
				moving = true
			elif atk_timer <= 0.0:
				_attack(target)
	if moving:
		moved_flag = true
	_separate(delta)
	_refresh_visual(moving)

func _slow_factor() -> float:
	var er: Dictionary = main.db.r.elements
	var k: float = 1.0 - float(er.frost.slow_per_stack) * float(stacks.get("frost", 0))
	if slow_t > 0.0:
		k *= 1.0 - slow
	return maxf(0.1, k)

func _tick_status(delta: float) -> void:
	var er: Dictionary = main.db.r.elements
	for e in stacks.keys():
		if int(stacks[e]) <= 0:
			continue
		stack_t[e] = float(stack_t.get(e, 0.0)) - delta
		if stack_t[e] <= 0.0:
			stacks[e] = int(stacks[e]) - 1
			stack_t[e] = float(er.decay_s)
	for e in immune.keys():
		immune[e] = float(immune[e]) - delta
	if hit_down_t > 0.0:
		hit_down_t -= delta
		if hit_down_t <= 0.0: hit_down = 0.0
	if slow_t > 0.0:
		slow_t -= delta
	# 灼烧：每层每秒 攻击×4%（吃火抗，不吃防御、不会心）
	if int(stacks.get("fire", 0)) > 0:
		burn_acc += delta
		if burn_acc >= 1.0:
			burn_acc -= 1.0
			var d: float = burn_atk * float(er.fire.burn_atk_pct_per_stack) / 100.0 * int(stacks.fire) * (1.0 - float(res.get("fire", 0.0)) / 100.0)
			if d > 0.0:
				take_damage(d, false, Color(1.0, 0.55, 0.2))
	# 生命回复/秒
	if regen > 0.0 and hp < max_hp:
		regen_acc += delta
		if regen_acc >= 1.0:
			regen_acc -= 1.0
			hp = minf(max_hp, hp + regen)

## 叠属性层；满层触发（§1.2）。src 为攻击者
func add_stack(e: String, src) -> void:
	if dead:
		return
	var er: Dictionary = main.db.r.elements
	var mx: int = int(er.max_stacks)
	stacks[e] = mini(mx, int(stacks.get(e, 0)) + 1)
	stack_t[e] = float(er.decay_s)
	if e == "fire":
		burn_atk = src.atk
	if int(stacks[e]) < mx:
		return
	var boss := kind == "boss"
	var nm: String = er.names.get(e, e)
	match e:
		"frost":
			if boss:
				slow = float(er.frost.boss_slow); slow_t = float(er.frost.boss_slow_s)
				main.spawn_text(position + Vector2(0, _head_y() - 40), "减速", Color(0.6, 0.85, 1.0), 20)
			elif float(immune.get(e, 0.0)) <= 0.0:
				stun_t = float(er.frost.freeze_s); immune[e] = float(er.frost.immune_s)
				main.spawn_text(position + Vector2(0, _head_y() - 40), "冰冻", Color(0.6, 0.85, 1.0), 22)
			stacks[e] = 0
		"fire":
			stacks[e] = 0
			main.fire_burst(src, self)
		"lightning":
			if boss:
				windup = 0.0
				if not skill.is_empty(): skill_timer = maxf(skill_timer, 1.0)
				main.spawn_text(position + Vector2(0, _head_y() - 40), "打断", Color(1.0, 0.95, 0.4), 22)
			elif float(immune.get(e, 0.0)) <= 0.0:
				stun_t = float(er.lightning.stun_s); immune[e] = float(er.lightning.immune_s)
				main.spawn_text(position + Vector2(0, _head_y() - 40), "麻痹", Color(1.0, 0.95, 0.4), 22)
		"shadow":
			if boss:
				hit_down = float(er.shadow.boss_hit_down); hit_down_t = float(er.shadow.boss_hit_down_s)
				main.spawn_text(position + Vector2(0, _head_y() - 40), "命中下降", Color(0.75, 0.55, 1.0), 20)
			elif float(immune.get(e, 0.0)) <= 0.0:
				fear_t = float(er.shadow.fear_s); immune[e] = float(er.shadow.immune_s)
				fear_dir = (position - src.position).normalized()
				main.spawn_text(position + Vector2(0, _head_y() - 40), "恐惧", Color(0.75, 0.55, 1.0), 22)
	stacks[e] = int(stacks[e])
	if nm == "": pass

func revive() -> void:
	dead = false
	hp = max_hp
	modulate = Color.WHITE
	stacks.clear(); stun_t = 0.0; fear_t = 0.0
	if rig != null:
		rig.dead_t = -1.0
		rig.pose.modulate = Color.WHITE
		rig.pose.rotation = 0.0
		rig.set_fx_visible(true)
	if body != null:
		body.modulate = Color.WHITE
		body.rotation = 0.0
		if body is AnimatedSprite2D:
			(body as AnimatedSprite2D).play("idle")

func _step(v: Vector2) -> void:
	position += v
	if absf(v.x) > 0.01:
		facing = signf(v.x)
	position = main.clamp_to_field(position)

func _separate(delta: float) -> void:
	for o in main.units:
		if o == self or o.dead:
			continue
		var d: Vector2 = position - o.position
		var min_d: float = (radius + o.radius) * 0.8
		if d.length() < min_d and d.length() > 0.01:
			position += d.normalized() * (min_d - d.length()) * 0.5 * minf(1.0, delta * 10.0)
	position = main.clamp_to_field(position)

func _refresh_visual(moving: bool) -> void:
	if rig != null:
		rig.update(get_process_delta_time(), facing, moving, flash)
	elif body is AnimatedSprite2D:
		var a := body as AnimatedSprite2D
		if a.animation != "attack" and a.animation != "hit":
			var want := "run" if moving else "idle"
			if a.animation != want:
				a.play(want)
		a.flip_h = facing < 0
		var wa := weapon as AnimatedSprite2D
		if wa.animation != a.animation:
			wa.animation = a.animation
		wa.frame = a.frame
		wa.flip_h = a.flip_h
	elif body is Sprite2D:
		var s := body as Sprite2D
		s.flip_h = facing < 0
		(weapon as Sprite2D).flip_h = s.flip_h
		var bob := sin(t * (14.0 if moving else 4.0)) * (0.05 if moving else 0.02)
		s.scale = Vector2(base_scale * (1.0 - bob * 0.5), base_scale * (1.0 + bob))
		s.position = Vector2(facing * lunge * 14.0, -absf(sin(t * 14.0)) * 4.0 if moving else 0.0)
	if body != null:
		body.modulate = Color(1, 1, 1).lerp(Color(1, 0.35, 0.35), flash)
	overlay.queue_redraw()
	queue_redraw()

func _on_anim_finished() -> void:
	var a := body as AnimatedSprite2D
	if dead:
		return
	if a.animation == "attack" or a.animation == "hit":
		a.play("idle")

# ---------- 战斗 ----------
func _attack(tgt) -> void:
	atk_timer = interval
	lunge = 1.0
	if rig != null:
		rig.play_attack()
	if body is AnimatedSprite2D:
		(body as AnimatedSprite2D).play("attack")
	if ranged:
		main.spawn_projectile(self, tgt, 1.0, _proj_color(), data.get("proj_speed", 500.0), uid)
	else:
		main.deal_damage(self, tgt, 1.0, false)

func _proj_color() -> Color:
	return main.tier_color(weapon_tier) if team == "hero" else Color.WHITE

func _try_skill() -> bool:
	match skill.type:
		"aoe":
			var hit: Array = main.enemies_in_radius(self, position, skill.radius)
			if hit.is_empty():
				return false
			for e in hit:
				main.deal_damage(self, e, skill.mult, true)
			main.spawn_ring(position, skill.radius, main.tier_color(weapon_tier), 0.35)
		"multishot":
			var list: Array = main.enemies_sorted(self)
			if list.is_empty():
				return false
			for i in int(skill.count):
				var e = list[i % list.size()]
				main.spawn_projectile(self, e, skill.mult, _proj_color(), data.proj_speed * 1.2, uid, i * 0.08, true)
		"heal":
			var need := false
			for h in main.heroes():
				if h.hp < h.max_hp * 0.8:
					need = true
			if not need:
				return false
			for h in main.heroes():
				var amt: float = atk * skill.mult + h.max_hp * skill.pct
				h.heal(amt)
			main.spawn_ring(position, 140.0, Color(0.4, 1.0, 0.5), 0.5)
		"slam":
			if target == null or position.distance_to(target.position) > skill.radius:
				return false
			windup = skill.windup
		_:
			return false
	skill_timer = skill.cd
	main.spawn_text(position + Vector2(0, -150 if team == "hero" else -70.0 * size - 40), skill.name, Color(1, 0.95, 0.5), 20)
	return true

func _do_slam() -> void:
	main.spawn_ring(position, skill.radius, Color(1, 0.3, 0.2), 0.4)
	for h in main.heroes():
		if h.position.distance_to(position) <= skill.radius:
			main.deal_damage(self, h, skill.mult, true)

func take_damage(amount: float, is_crit: bool, color_override = null) -> void:
	if dead:
		return
	var crit := is_crit
	var dr: float = float(_buff_val("dr_pct"))
	var amt: int = maxi(1, main.db.iround(float(amount) * (1.0 - dr / 100.0)))
	if shield_hp > 0.0:
		var sh: float = minf(shield_hp, float(amt))
		shield_hp -= sh
		amt = int(amt - sh)
	if amt <= 0:
		main.spawn_text(position + Vector2(0, _head_y() - 18), "抵挡", Color(0.7, 0.9, 1.0), 18)
		return
	amount = amt
	hp -= amount
	if team == "hero":
		_on_took_hit(amount)
	flash = 1.0
	if rig != null:
		rig.play_hit()
	var col: Color = Color(1, 0.85, 0.2) if crit else (Color(1, 0.35, 0.3) if team == "hero" else Color.WHITE)
	if color_override != null:
		col = color_override
	main.spawn_text(position + Vector2(randf_range(-14, 14), _head_y() - 18), str(int(round(amount))) + ("!" if crit else ""), col, 26 if crit else 20)
	if body is AnimatedSprite2D and (body as AnimatedSprite2D).animation != "attack":
		(body as AnimatedSprite2D).play("hit")
	if hp <= 0.0:
		hp = 0.0
		die()

func heal(amount: float) -> void:
	if dead:
		return
	var before := hp
	hp = minf(max_hp, hp + amount)
	if hp - before >= 1.0:
		main.spawn_text(position + Vector2(0, _head_y() - 18), "+" + str(int(hp - before)), Color(0.4, 1.0, 0.45), 20)

func die() -> void:
	dead = true
	selected = false
	move_target = null
	if rig != null:
		rig.play_death()
	if body is AnimatedSprite2D:
		(body as AnimatedSprite2D).play("death")
	elif body != null:
		body.modulate = Color(0.5, 0.5, 0.5, 0.6)
		body.rotation = facing * 1.4
	main.on_unit_died(self)

func _head_y() -> float:
	if rig != null:
		return -145.0
	return -125.0 if team == "hero" else -60.0 * size - 18.0

# ---------- 绘制 ----------
func _draw() -> void:
	# 脚底阴影 + 外观档光圈（英雄）
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, radius * 1.1, Color(0, 0, 0, 0.25))
	if team == "hero" and appearance_tier > 0 and not dead:
		var c: Color = main.tier_color(appearance_tier)
		var pulse := 0.6 + 0.4 * sin(t * 4.0)
		draw_arc(Vector2.ZERO, radius * 1.35, 0, TAU, 40, Color(c, 0.5 + 0.4 * pulse), 4.0)
		if appearance_tier >= 5:
			draw_arc(Vector2.ZERO, radius * 1.75, t, t + TAU * 0.8, 40, Color(c, 0.6), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if team == "hero" and enh_tier > 0 and not dead:
		_draw_enh_back()
	if team == "hero" and appearance_tier >= 3 and not dead and rig == null:
		_draw_aura()
	if team == "enemy":
		_draw_monster()
	if selected:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.35))
		draw_arc(Vector2.ZERO, radius * 1.6, 0, TAU, 40, Color(0.3, 1.0, 0.4), 3.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_monster() -> void:
	var s := size
	var c := body_color.lerp(Color(1, 0.4, 0.4), flash)
	if dead:
		c = Color(c, 0.35)
	var off := Vector2(facing * lunge * 10.0, 0)
	var bob := sin(t * 8.0) * 2.0
	match uid:
		"wolf":
			draw_rect(Rect2(off + Vector2(-26, -34 + bob) * s, Vector2(52, 22) * s), c)
			draw_circle(off + Vector2(facing * 28, -36 + bob) * s, 13 * s, c)
			draw_colored_polygon(PackedVector2Array([off + Vector2(facing * 22, -46) * s, off + Vector2(facing * 28, -60) * s, off + Vector2(facing * 34, -46) * s]), c.darkened(0.2))
			for x in [-20, -8, 10, 20]:
				draw_line(off + Vector2(x, -14) * s, off + Vector2(x, 0) * s, c.darkened(0.3), 5 * s)
			draw_circle(off + Vector2(facing * 32, -39 + bob) * s, 2.5 * s, Color(1, 0.9, 0.2))
		"boar":
			draw_circle(off + Vector2(0, -28 + bob) * s, 26 * s, c)
			draw_circle(off + Vector2(facing * 26, -26 + bob) * s, 12 * s, c.lightened(0.15))
			draw_line(off + Vector2(facing * 30, -20) * s, off + Vector2(facing * 40, -32) * s, Color(0.95, 0.95, 0.85), 4 * s)
			for x in [-14, 14]:
				draw_line(off + Vector2(x, -8) * s, off + Vector2(x, 0) * s, c.darkened(0.3), 6 * s)
		_:
			# 山贼 / 山贼头目：人形
			draw_rect(Rect2(off + Vector2(-16, -48 + bob) * s, Vector2(32, 38) * s), c)
			draw_circle(off + Vector2(0, -62 + bob) * s, 16 * s, Color(0.98, 0.85, 0.7) if not dead else Color(0.6, 0.55, 0.5, 0.4))
			draw_rect(Rect2(off + Vector2(-17, -78 + bob) * s, Vector2(34, 9) * s), c.darkened(0.4))
			draw_line(off + Vector2(-8, -10) * s, off + Vector2(-8, 0) * s, c.darkened(0.4), 6 * s)
			draw_line(off + Vector2(8, -10) * s, off + Vector2(8, 0) * s, c.darkened(0.4), 6 * s)
			draw_line(off + Vector2(facing * 18, -36) * s, off + Vector2(facing * 34, -58) * s, Color(0.75, 0.75, 0.8), 4 * s)
			draw_circle(off + Vector2(facing * 6, -63 + bob) * s, 2.2 * s, Color.BLACK)
	if windup > 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
		var k: float = 1.0 - windup / skill.windup
		draw_circle(Vector2.ZERO, skill.radius, Color(1, 0.2, 0.1, 0.12))
		draw_arc(Vector2.ZERO, skill.radius * k, 0, TAU, 48, Color(1, 0.3, 0.1, 0.8), 4.0)
		draw_arc(Vector2.ZERO, skill.radius, 0, TAU, 48, Color(1, 0.3, 0.1, 0.6), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------- 全身强化特效（占位，代码绘制；4 档各不相同，门槛读 enhance.slice_fx_thresholds） ----------
const ENH_COL := [Color(0.35, 0.95, 1.0), Color(0.55, 0.6, 1.0), Color(1.0, 0.78, 0.25), Color(1.0, 0.97, 0.85)]

func _draw_enh_back() -> void:
	var tr := enh_tier
	var pulse := 0.5 + 0.5 * sin(t * 3.0)
	# 1 档「灵光」：脚下青色双层光环呼吸
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.35))
	var c1: Color = ENH_COL[0]
	draw_circle(Vector2.ZERO, radius * 2.0, Color(c1, 0.10 + 0.08 * pulse))
	draw_arc(Vector2.ZERO, radius * (1.9 + 0.15 * pulse), 0, TAU, 48, Color(c1, 0.75), 3.0)
	if tr >= 2:
		# 2 档「符阵」：旋转的符文阵（刻度 + 菱形符）
		var c2: Color = ENH_COL[1]
		var rr := radius * 2.6
		draw_arc(Vector2.ZERO, rr, 0, TAU, 64, Color(c2, 0.85), 3.0)
		draw_arc(Vector2.ZERO, rr * 0.82, 0, TAU, 64, Color(c2, 0.6), 2.0)
		for i in 8:
			var a := t * 0.8 + i * TAU / 8.0
			var p := Vector2(cos(a), sin(a)) * rr * 0.91
			var q := Vector2(cos(a), sin(a))
			var n := Vector2(-q.y, q.x)
			draw_colored_polygon(PackedVector2Array([p + q * 9, p + n * 6, p - q * 9, p - n * 6]), Color(c2.lightened(0.3), 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if tr >= 3:
		# 3 档「金焰」：身后金色光柱 + 上升火星
		var c3: Color = ENH_COL[2]
		for i in 5:
			var w := 70.0 - i * 11.0
			draw_rect(Rect2(-w * 0.5, -175, w, 175), Color(c3, 0.05 + 0.03 * pulse))
		for i in 10:
			var ph := fmod(t * 0.7 + i * 0.1, 1.0)
			var x := sin(i * 1.9 + t * 1.3) * 40.0
			draw_circle(Vector2(x, -8.0 - ph * 170.0), 4.0 * (1.0 - ph) + 1.0, Color(c3.lightened(0.2), 1.0 - ph))
	if tr >= 4:
		# 4 档「天光」：顶天白金光柱 + 外圈双环（后半圈在身后）
		var c4: Color = ENH_COL[3]
		draw_rect(Rect2(-16, -420, 32, 420), Color(c4, 0.12 + 0.08 * pulse))
		draw_rect(Rect2(-5, -420, 10, 420), Color(c4, 0.32 + 0.15 * pulse))
		_orbs(true)

func _orbs(back: bool) -> void:
	var c4: Color = ENH_COL[3]
	for i in 3:
		var a := t * 2.2 + i * TAU / 3.0
		var z := sin(a)
		if (z < 0.0) != back:
			continue
		var p := Vector2(cos(a) * 62.0, -70.0 + z * 16.0)
		draw_circle(p, 11.0, Color(1.0, 0.85, 0.4, 0.35))
		draw_circle(p, 6.0, c4)

func _draw_enh_front() -> void:
	if enh_tier >= 4:
		var c4: Color = ENH_COL[3]
		for i in 3:
			var a := t * 2.2 + i * TAU / 3.0
			if sin(a) < 0.0:
				continue
			var p := Vector2(cos(a) * 62.0, -70.0 + sin(a) * 16.0)
			overlay.draw_circle(p, 12.0, Color(1.0, 0.85, 0.4, 0.35))
			overlay.draw_circle(p, 6.5, c4)

func _draw_stacks() -> void:
	var er: Dictionary = main.db.r.elements
	var cols := {"frost": Color(0.55, 0.85, 1.0), "fire": Color(1.0, 0.45, 0.15), "lightning": Color(1.0, 0.95, 0.3), "shadow": Color(0.7, 0.45, 1.0)}
	var y := _head_y() - 14.0
	var x := -30.0
	for e in stacks:
		var n: int = int(stacks[e])
		if n <= 0:
			continue
		for i in n:
			overlay.draw_circle(Vector2(x + i * 7, y), 3.0, cols.get(e, Color.WHITE))
		y -= 8.0
	if stun_t > 0.0 or fear_t > 0.0:
		overlay.draw_string(main.font, Vector2(-36, _head_y() - 36), "眩" if stun_t > 0.0 else "惧", HORIZONTAL_ALIGNMENT_CENTER, 72, UiScale.fs(16), Color.WHITE)
	if er.is_empty(): pass

func _draw_overlay() -> void:
	if dead:
		return
	if team == "hero":
		_draw_enh_front()
	else:
		_draw_stacks()
	var w := 60.0 if team == "hero" else 46.0 * maxf(1.0, size * 0.8)
	var y := _head_y()
	overlay.draw_rect(Rect2(-w * 0.5 - 1, y - 1, w + 2, 9), Color(0, 0, 0, 0.7))
	var col := Color(0.25, 0.9, 0.35) if team == "hero" else Color(0.9, 0.25, 0.2)
	overlay.draw_rect(Rect2(-w * 0.5, y, w * hp / max_hp, 7), col)
	if team == "hero":
		var f: Font = main.font
		var nc: Color = main.tier_color(appearance_tier)
		overlay.draw_string(f, Vector2(-w * 0.5, y - 5), display_name, HORIZONTAL_ALIGNMENT_CENTER, w, UiScale.fs(15), nc)
		if not skill.is_empty():
			var k := clampf(1.0 - skill_timer / skill.cd, 0.0, 1.0)
			overlay.draw_rect(Rect2(-w * 0.5, y + 9, w * k, 3), Color(0.4, 0.7, 1.0))
	elif size >= 1.5:
		overlay.draw_string(main.font, Vector2(-w * 0.5, y - 5), display_name, HORIZONTAL_ALIGNMENT_CENTER, w, UiScale.fs(16), Color(1, 0.8, 0.6))

func _draw_aura() -> void:
	# 紫及以上：身后一团该档颜色的光；红/暗金再加上升的光点
	var c: Color = main.tier_color(appearance_tier)
	var k := float(appearance_tier - 2) / 4.0     # 紫 0.25 → 暗金 1.0
	var pulse := 0.75 + 0.25 * sin(t * 3.0)
	draw_set_transform(Vector2(0, -58), 0.0, Vector2(0.62, 1.0))
	for i in 4:
		var r := 62.0 + i * 12.0 * (0.6 + k)
		draw_circle(Vector2.ZERO, r, Color(c, (0.07 + 0.05 * k) * pulse))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if appearance_tier >= 5:
		for i in 8:
			var ph := fmod(t * 0.6 + i * 0.125, 1.0)
			var x := sin(i * 2.3 + t) * 34.0
			draw_circle(Vector2(x, -10.0 - ph * 120.0), 3.5 * (1.0 - ph) + 1.0, Color(c.lightened(0.3), 1.0 - ph))


func _buff_val(stat: String) -> float:
	var now := Time.get_ticks_msec() * 0.001
	var b = buffs.get(stat, null)
	if b == null:
		return 0.0
	if float(b.get("until", 0.0)) <= now:
		buffs.erase(stat)
		return 0.0
	return float(b.get("value", 0.0))


func add_buff(stat: String, value: float, dur: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	buffs[stat] = {"value": value, "until": now + dur}


func threat_deal() -> float:
	var th: Dictionary = main.db.t.get("combat_v13", {}).get("threat", {})
	var row: Dictionary = th.get(uid, th.get(data.get("id", uid), {}))
	if row.is_empty():
		if uid == "warrior":
			row = {"deal": 2.5, "taken": 1.5}
		elif uid == "mage":
			row = {"deal": 1.0, "taken": 0.3}
		else:
			row = {"deal": 1.0, "taken": 0.4}
	return float(row.get("deal", 1.0)) * self_threat_mul


func threat_taken() -> float:
	var th: Dictionary = main.db.t.get("combat_v13", {}).get("threat", {})
	var row: Dictionary = th.get(uid, {})
	if row.is_empty():
		if uid == "warrior":
			row = {"deal": 2.5, "taken": 1.5}
		elif uid == "mage":
			row = {"deal": 1.0, "taken": 0.3}
		else:
			row = {"deal": 1.0, "taken": 0.4}
	return float(row.get("taken", 0.4)) * self_threat_mul


func add_threat(hero, amount: float) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	var k: String = str(hero.uid)
	threat[k] = float(threat.get(k, 0.0)) + amount


func apply_taunt(hero, bonus: float, force_s: float) -> void:
	add_threat(hero, bonus)
	taunt_until = Time.get_ticks_msec() * 0.001 + force_s
	taunt_target = hero
	target = hero
	main.spawn_text(position + Vector2(0, -80), "嘲讽", Color(1.0, 0.85, 0.3), 18)


func _threat_of(hero) -> float:
	if hero == null or not is_instance_valid(hero):
		return 0.0
	return float(threat.get(str(hero.uid), 0.0))


func _threat_switch_ratio() -> float:
	var th: Dictionary = main.db.t.get("combat_v13", {}).get("threat", {})
	return float(th.get("switch_ratio", 1.1))


## 刷出或还没有仇恨时打最近的角色；有仇恨后按仇恨表选目标。
## 新目标仇恨必须超过当前目标的 switch_ratio（默认 110%）才切换，避免来回跳。
func _pick_threat_target():
	var best = null
	var best_th := 0.0
	for h in main.heroes():
		if h == null or not is_instance_valid(h) or h.dead:
			continue
		var th: float = _threat_of(h)
		if th > best_th:
			best_th = th
			best = h
	if best == null or best_th <= 0.0:
		return main.nearest_hero(self)
	if target != null and is_instance_valid(target) and target.team == "hero" and not target.dead:
		var cur: float = _threat_of(target)
		if cur > 0.0 and best != target and best_th <= cur * _threat_switch_ratio():
			return target
	return best


func _pick_target():
	if team == "hero":
		return main.nearest_enemy(self)
	var now := Time.get_ticks_msec() * 0.001
	# 嘲讽：一次性仇恨加成后强制 2 秒，结束后回到仇恨表
	if now < taunt_until and taunt_target != null and is_instance_valid(taunt_target) and not taunt_target.dead:
		return taunt_target
	return _pick_threat_target()


func _passive_atk_pct() -> float:
	var pct := 0.0
	for sk in stats.get("gear_skills", []):
		var rt: Dictionary = sk.get("runtime", {})
		match str(rt.get("type", "")):
			"passive_lowhp_atk":
				var lost: float = (1.0 - hp / maxf(1.0, max_hp)) * 100.0
				var stacks: int = mini(int(rt.get("cap", 9)), int(lost / float(rt.get("per", 10))))
				pct += stacks * float(rt.get("value", 3))
			"passive_highhp_atk":
				if hp / maxf(1.0, max_hp) * 100.0 >= float(rt.get("hp_pct", 70)):
					pct += float(rt.get("value", 8))
	return pct


func _tick_gear_skills(delta: float) -> void:
	if team != "hero" or dead:
		return
	for sk in stats.get("gear_skills", []):
		var sid: String = str(sk.get("id", ""))
		gear_skill_cd[sid] = float(gear_skill_cd.get(sid, 0.0)) - delta
		var trig: String = str(sk.get("trigger", "auto"))
		if trig != "auto":
			continue
		if float(gear_skill_cd.get(sid, 0.0)) > 0.0:
			continue
		if _cast_gear_skill(sk):
			var cd: float = float(sk.get("cd", 8))
			gear_skill_cd[sid] = cd
			# 澄源术为全队同源技能：多件暗金同时装备时共用冷却，避免治疗叠成无敌。
			if str(sk.get("runtime", {}).get("type", "")) == "heal_lowest_pct" and main != null and main.has_method("heroes"):
				for h in main.heroes():
					if h != null and is_instance_valid(h):
						h.gear_skill_cd[sid] = cd


func _cast_gear_skill(sk: Dictionary) -> bool:
	var rt: Dictionary = sk.get("runtime", {})
	var typ: String = str(rt.get("type", ""))
	match typ:
		"taunt":
			var list: Array = main.enemies_in_radius(self, position, float(rt.get("radius", 200)))
			if list.is_empty():
				return false
			var bonus: float = float(main.db.iround(float(atk) / maxf(0.4, interval) * float(rt.get("bonus_seconds", 8.0)) * threat_deal()))
			for e in list:
				e.apply_taunt(self, bonus, float(rt.get("force_s", 2.0)))
			main.spawn_ring(position, float(rt.get("radius", 200)), Color(1.0, 0.8, 0.3), 0.35)
			main.spawn_text(position + Vector2(0, -150), str(sk.get("name", "嘲讽")), Color(1, 0.95, 0.5), 20)
			return true
		"buff":
			add_buff(str(rt.get("stat", "atk_pct")), float(rt.get("value", 0)), float(rt.get("dur", 5)))
			main.spawn_text(position + Vector2(0, -150), str(sk.get("name", "增益")), Color(1, 0.95, 0.5), 20)
			recalc_stats()
			return true
		"shield_pct":
			shield_hp = maxf(shield_hp, max_hp * float(rt.get("value", 15)) / 100.0)
			main.spawn_text(position + Vector2(0, -150), str(sk.get("name", "护盾")), Color(0.7, 0.9, 1.0), 20)
			return true
		"heal_pct":
			heal(max_hp * float(rt.get("value", 3)) / 100.0)
			main.spawn_text(position + Vector2(0, -150), str(sk.get("name", "回复")), Color(0.5, 1.0, 0.6), 20)
			return true
		"heal_lowest_pct":
			if main == null or not main.has_method("heroes"):
				return false
			var best = null
			var best_ratio := 2.0
			for h in main.heroes():
				if h == null or not is_instance_valid(h) or h.dead:
					continue
				var ratio: float = float(h.hp) / maxf(1.0, float(h.max_hp))
				if ratio < best_ratio:
					best_ratio = ratio
					best = h
			if best == null or best.hp >= best.max_hp:
				return false
			var amt: int = main.db.iround(float(best.max_hp) * float(rt.get("value", 12)) / 100.0)
			best.heal(float(amt))
			main.spawn_text(best.position + Vector2(0, -150), str(sk.get("name", "治疗")), Color(0.45, 1.0, 0.7), 20)
			return true
		"extra_hit":
			if target == null or not is_instance_valid(target) or target.dead:
				return false
			main.deal_damage(self, target, float(rt.get("pct", 100)) / 100.0, true, true)
			main.spawn_text(position + Vector2(0, -150), str(sk.get("name", "连击")), Color(1, 0.95, 0.5), 20)
			return true
		_:
			return false


func on_dealt_hit(tgt, info: Dictionary, proc := false) -> void:
	if team != "hero" or proc:
		return
	hit_count += 1
	# 叠刃环：每第 3 次必定会心，在下一次 compute 前加临时
	if next_hit_bonus > 0.0:
		next_hit_bonus = 0.0
	if moved_flag:
		moved_flag = false
	for sk in stats.get("gear_skills", []):
		var rt: Dictionary = sk.get("runtime", {})
		var typ: String = str(rt.get("type", ""))
		var chance: float = float(sk.get("chance", rt.get("chance", 100)))
		if typ == "passive_every_n_crit" and hit_count % int(rt.get("n", 3)) == 0:
			# 已在伤害里处理较难，这里补一次追加伤害表示必定会心的额外一截
			pass
		if typ == "passive_first_after_move":
			pass
		if typ in ["splash", "nuke", "next_hit_pct"]:
			if randf() * 100.0 > chance:
				continue
			var sid: String = str(sk.get("id", typ))
			if typ != "splash" and typ != "nuke" and typ != "next_hit_pct":
				continue
			if typ == "next_hit_pct":
				next_hit_bonus = float(rt.get("value", 40))
				continue
			if typ == "splash":
				for e in main.enemies_in_radius(self, tgt.position, float(rt.get("radius", 80))):
					if e == tgt:
						continue
					main.deal_damage(self, e, float(rt.get("pct", 35)) / 100.0, true, true)
			elif typ == "nuke":
				main.deal_damage(self, tgt, float(rt.get("pct", 80)) / 100.0, true, true)
		if typ == "buff" and str(sk.get("trigger", "")) == "on_crit" and info.get("crit", false):
			var sid2: String = str(sk.get("id", ""))
			if float(gear_skill_cd.get(sid2, 0.0)) <= 0.0:
				add_buff(str(rt.get("stat", "aspd")), float(rt.get("value", 15)), float(rt.get("dur", 3)))
				gear_skill_cd[sid2] = float(sk.get("cd", 6))
				recalc_stats()
	# 套装触发
	for tr in stats.get("set_bonus", {}).get("triggers", []):
		var defn: Dictionary = tr.get("def", {})
		if str(defn.get("type", "")) == "on_hit_buff" and randf() * 100.0 <= float(tr.get("chance", 10)):
			add_buff(str(defn.get("stat", "def_pct")), float(defn.get("value", 50)), float(defn.get("dur", 5)))
			recalc_stats()



func _on_took_hit(_amount: float) -> void:
	if dead:
		return
	for sk in stats.get("gear_skills", []):
		if str(sk.get("trigger", "")) != "on_hit_taken":
			continue
		var sid: String = str(sk.get("id", ""))
		if float(gear_skill_cd.get(sid, 0.0)) > 0.0:
			continue
		var chance: float = float(sk.get("chance", 100))
		if randf() * 100.0 > chance:
			continue
		var rt: Dictionary = sk.get("runtime", {})
		var typ: String = str(rt.get("type", ""))
		if typ == "shield_pct":
			shield_hp = maxf(shield_hp, max_hp * float(rt.get("value", 8)) / 100.0)
			main.spawn_text(position + Vector2(0, -150), str(sk.get("name", "护盾")), Color(0.7, 0.9, 1.0), 20)
			gear_skill_cd[sid] = float(sk.get("cd", rt.get("cd", 8)))
		elif typ == "heal_pct":
			heal(max_hp * float(rt.get("value", 3)) / 100.0)
			gear_skill_cd[sid] = float(sk.get("cd", 8))
		elif typ == "buff":
			add_buff(str(rt.get("stat", "dr_pct")), float(rt.get("value", 15)), float(rt.get("dur", 3)))
			gear_skill_cd[sid] = float(sk.get("cd", 7))
			recalc_stats()
	for tr in stats.get("set_bonus", {}).get("triggers", []):
		var defn: Dictionary = tr.get("def", {})
		if str(defn.get("type", "")) != "on_hit_taken_shield":
			continue
		var tid: String = "set_shield_%s" % str(tr.get("group", "a"))
		if float(gear_skill_cd.get(tid, 0.0)) > 0.0:
			continue
		if randf() * 100.0 > float(tr.get("chance", 100)):
			continue
		shield_hp = maxf(shield_hp, max_hp * float(defn.get("value", 10)) / 100.0)
		main.spawn_text(position + Vector2(0, -150), "灵罩", Color(0.7, 0.9, 1.0), 20)
		gear_skill_cd[tid] = float(defn.get("cd", 8))


func leech_pct(is_skill: bool) -> int:
	var p: int = leech
	if is_skill:
		p += skill_leech
	# 技能饮刃印等
	for sk in stats.get("gear_skills", []):
		var rt: Dictionary = sk.get("runtime", {})
		if str(rt.get("type", "")) == "lifesteal":
			p += int(rt.get("value", 0))
	return mini(12, maxi(0, p))


func hit_heal_value() -> int:
	var v: int = hit_heal
	for sk in stats.get("gear_skills", []):
		var rt: Dictionary = sk.get("runtime", {})
		v += int(rt.get("hit_heal", 0))
	return maxi(0, v)


func on_kill(_tgt) -> void:
	for sk in stats.get("gear_skills", []):
		var rt: Dictionary = sk.get("runtime", {})
		if str(sk.get("trigger", "")) == "on_kill":
			match str(rt.get("type", "")):
				"buff":
					add_buff(str(rt.get("stat", "ms")), float(rt.get("value", 30)), float(rt.get("dur", 3)))
					recalc_stats()
				"heal_pct":
					heal(max_hp * float(rt.get("value", 2)) / 100.0)
		# 吸血类技能可附带击杀回血（如饮刃印）
		if int(rt.get("on_kill_heal_pct", 0)) > 0:
			heal(max_hp * float(rt.get("on_kill_heal_pct", 0)) / 100.0)
