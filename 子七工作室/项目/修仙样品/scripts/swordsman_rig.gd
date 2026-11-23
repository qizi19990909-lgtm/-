extends Node2D
## 剑修七品阶外观（试做版 v2：1:1 头身，正面 + 3/4 侧面两个角度）。
## 每档每个角度一张整身贴图 + 一张单独的剑层（assets/swordsman_tiers/，由 tools/make_swordsman_tiers.py 生成）。
## 角度：战斗中（待机/移动/攻击）一律用侧面图，朝右原图、朝左镜像——横版战斗里角色一直侧身对敌，
##       待机也用侧面就不会在「站住↔走动」之间来回切换角度而闪烁；正面图只在打开装备面板时展示（当作换装预览）。
## 待机（呼吸）、移动（上下颠 + 左右晃）、攻击（挥剑 + 刀光）、受击（闪红 + 后仰）、倒地全部用代码做。
## 特效按品阶分层开关：蓝 水雾 / 紫 紫雾 / 橙 金光 + 闪光点 / 红 火焰 / 暗金 光环 + 飞剑 + 披风摆动。
## 粒子全部用 CPUParticles2D，数量很少（网页版是单线程，手机也跑得动）。

const DISPLAY_H := 135.0          # 贴图画布在屏幕上的高度（人物本身约 126 像素，1280×720 画面）
const ATTACK_TIME := 0.42
const SW_SIDE := [-2.3, 0.9, 0.0]       # 侧面挥剑：蓄力角、劈到的角、收剑角（弧度，相对原图）
const SW_FRONT := [1.9, 4.75, TAU]

const CAPE_SHADER := """
shader_type canvas_item;
uniform float sway = 0.0;              // 暗金档披风摆动
uniform vec4 cape = vec4(0.65, 0.50, 0.87, 0.85);   // 披风区域渐变（UV：x 从 x0 到 x1 由 0 变 1，y 同理；x0>x1 表示披风在左边）
varying vec4 v_mod;
void vertex() { v_mod = COLOR; }
void fragment() {
	vec2 uv = UV;
	float m = clamp((uv.x - cape.x) / (cape.z - cape.x), 0.0, 1.0) * clamp((uv.y - cape.y) / (cape.w - cape.y), 0.0, 1.0);
	m = m * m * (3.0 - 2.0 * m);
	uv.x += sin(TIME * 2.4 + uv.y * 10.0) * 0.010 * m * sway;
	COLOR = texture(TEXTURE, uv) * v_mod;
}
"""

var main
var tier := -1
var view := "side"             # "side"（战斗）/ "front"（装备面板预览）
var meta := {}
var k := 1.0                    # 贴图 → 屏幕缩放
var pose: Node2D                # 跟着动作移动/旋转/翻转的部分
var body: Sprite2D
var sword: Sprite2D
var trail: Node2D               # 刀光（挂在 pose 下，跟随翻转）
var back_fx: Node2D             # 身后：金光、光环、后半圈飞剑
var front_fx: Node2D            # 身前：前半圈飞剑
var mist: CPUParticles2D
var sparkle: CPUParticles2D
var flame_back: CPUParticles2D
var flame_front: CPUParticles2D
var body_mat: ShaderMaterial

var t := 0.0
var facing := 1.0
var moving := false
var atk := -1.0                 # 攻击进度 0..1，<0 表示没在攻击
var hit := 0.0
var dead_t := -1.0
var swing := 0.0                # 剑的旋转（弧度）
var trail_from := 0.0
var trail_alpha := 0.0
var weapon_color := Color.WHITE

func setup(m, weapon_mat: ShaderMaterial) -> void:
	main = m
	meta = main.sw_meta
	var sz := Vector2(meta.size[0], meta.size[1])
	k = DISPLAY_H / sz.y
	back_fx = Node2D.new(); back_fx.draw.connect(_draw_back); add_child(back_fx)
	mist = _make_particles(false); add_child(mist)
	flame_back = _make_particles(true); add_child(flame_back)
	pose = Node2D.new(); add_child(pose)
	body = Sprite2D.new(); body.centered = false
	body_mat = ShaderMaterial.new()
	var sh := Shader.new(); sh.code = CAPE_SHADER; body_mat.shader = sh
	body.material = body_mat
	pose.add_child(body)
	sword = Sprite2D.new(); sword.centered = false
	sword.material = weapon_mat
	pose.add_child(sword)
	trail = Node2D.new(); trail.draw.connect(_draw_trail); pose.add_child(trail)
	flame_front = _make_particles(true); add_child(flame_front)
	sparkle = _make_particles(false); add_child(sparkle)
	front_fx = Node2D.new(); front_fx.draw.connect(_draw_front); add_child(front_fx)
	_config_particles()

func _make_particles(_additive: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.local_coords = false
	p.texture = main.fx_dot_tex
	return p

func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array(); var cs := PackedColorArray()
	for i in cols.size():
		offs.append(float(i) / float(cols.size() - 1)); cs.append(cols[i])
	g.offsets = offs; g.colors = cs
	return g

func _config_particles() -> void:
	# 水雾/紫雾：几团大的半透明雾，绕着身体慢慢往上飘
	mist.amount = 10
	mist.lifetime = 2.6
	mist.preprocess = 2.6
	mist.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	mist.emission_rect_extents = Vector2(40, 46)
	mist.position = Vector2(0, -48)
	mist.direction = Vector2(0, -1); mist.spread = 60.0
	mist.initial_velocity_min = 6.0; mist.initial_velocity_max = 16.0
	mist.gravity = Vector2(0, -6)
	mist.scale_amount_min = 0.9; mist.scale_amount_max = 1.6
	mist.angular_velocity_min = -20; mist.angular_velocity_max = 20
	# 闪光点（橙）
	sparkle.texture = main.fx_star_tex
	sparkle.amount = 9
	sparkle.lifetime = 1.4
	sparkle.preprocess = 1.4
	sparkle.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	sparkle.emission_rect_extents = Vector2(46, 62)
	sparkle.position = Vector2(0, -66)
	sparkle.gravity = Vector2(0, -10)
	sparkle.initial_velocity_min = 0.0; sparkle.initial_velocity_max = 6.0
	sparkle.scale_amount_min = 0.35; sparkle.scale_amount_max = 0.7
	var sc := Curve.new(); sc.add_point(Vector2(0, 0)); sc.add_point(Vector2(0.3, 1)); sc.add_point(Vector2(1, 0))
	sparkle.scale_amount_curve = sc
	sparkle.color_ramp = _ramp([Color(1, 0.95, 0.6, 0), Color(1, 0.9, 0.45, 1), Color(1, 0.75, 0.2, 0)])
	# 火焰（红）：身后一圈 + 脚下几簇在身前，叠加混合
	for f in [flame_back, flame_front]:
		var fp := f as CPUParticles2D
		fp.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		fp.direction = Vector2(0, -1); fp.spread = 12.0
		fp.gravity = Vector2(0, -90)
		var c := Curve.new(); c.add_point(Vector2(0, 0.6)); c.add_point(Vector2(0.25, 1)); c.add_point(Vector2(1, 0.1))
		fp.scale_amount_curve = c
		fp.color_ramp = _ramp([Color(1, 0.9, 0.45, 0.0), Color(1, 0.62, 0.12, 0.95), Color(0.95, 0.25, 0.05, 0.8), Color(0.65, 0.05, 0.02, 0.35), Color(0.3, 0, 0, 0)])
	flame_back.amount = 26
	flame_back.lifetime = 0.75
	flame_back.preprocess = 0.75
	flame_back.emission_rect_extents = Vector2(40, 44)
	flame_back.position = Vector2(0, -50)
	flame_back.initial_velocity_min = 50.0; flame_back.initial_velocity_max = 90.0
	flame_back.scale_amount_min = 0.8; flame_back.scale_amount_max = 1.3
	flame_front.amount = 8
	flame_front.lifetime = 0.55
	flame_front.preprocess = 0.55
	flame_front.emission_rect_extents = Vector2(34, 4)
	flame_front.position = Vector2(0, -2)
	flame_front.initial_velocity_min = 30.0; flame_front.initial_velocity_max = 60.0
	flame_front.scale_amount_min = 0.6; flame_front.scale_amount_max = 1.0

func set_view(v: String) -> void:
	if v == view:
		return
	view = v
	atk = -1.0
	swing = 0.0
	trail_alpha = 0.0
	if tier >= 0:
		_apply_textures()
		update(0.0, facing, false, 0.0)

func _apply_textures() -> void:
	var tm: Dictionary = meta[view][tier]
	var foot := Vector2(meta.foot[0], meta.foot[1])
	var grip := Vector2(tm.grip[0], tm.grip[1])
	body.texture = main.sw_tex[view + "_body"][tier]
	body.offset = -foot
	sword.texture = main.sw_tex[view + "_sword"][tier]
	sword.position = grip - foot
	sword.offset = Vector2(tm.sword_origin[0], tm.sword_origin[1]) - grip
	body_mat.set_shader_parameter("sway", 1.0 if tier >= 6 else 0.0)
	body_mat.set_shader_parameter("cape", Vector4(0.65, 0.50, 0.87, 0.85) if view == "front" else Vector4(0.36, 0.50, 0.14, 0.85))

func set_tier(at: int, wt_color: Color) -> void:
	weapon_color = wt_color
	if at == tier:
		return
	tier = at
	_apply_textures()
	# 特效开关
	var mist_on := at == 2 or at == 3
	mist.emitting = mist_on; mist.visible = mist_on
	if mist_on:
		var mc := Color(0.3, 0.85, 1.0) if at == 2 else Color(0.72, 0.42, 1.0)
		var ma := 0.48 if at == 2 else 0.34
		mist.color_ramp = _ramp([Color(mc, 0.0), Color(mc, ma), Color(mc, ma * 0.7), Color(mc, 0.0)])
		mist.amount = 9 if at == 2 else 11
		mist.restart()
	sparkle.emitting = at == 4; sparkle.visible = at == 4
	if at == 4: sparkle.restart()
	for f in [flame_back, flame_front]:
		f.emitting = at == 5; f.visible = at == 5
		if at == 5: f.restart()
	back_fx.queue_redraw(); front_fx.queue_redraw()

func set_fx_visible(on: bool) -> void:
	for p in [mist, sparkle, flame_back, flame_front]:
		if not on:
			p.emitting = false
	back_fx.visible = on; front_fx.visible = on

# ---------- 动作 ----------
func play_attack() -> void:
	atk = 0.0

func play_hit() -> void:
	hit = 1.0

func play_death() -> void:
	dead_t = 0.0
	atk = -1.0
	set_fx_visible(false)

func update(delta: float, f: float, mv: bool, flash: float) -> void:
	t += delta
	facing = f
	moving = mv
	hit = maxf(0.0, hit - delta * 5.0)
	var pos := Vector2.ZERO
	var rot := 0.0
	var sx := 1.0; var sy := 1.0
	if dead_t >= 0.0:
		# 倒地：向后倒下、变灰
		dead_t += delta
		var q := clampf(dead_t / 0.45, 0.0, 1.0)
		q = 1.0 - pow(1.0 - q, 3.0)
		rot = -1.45 * q
		pos = Vector2(-10.0 * q, 0)
		swing = lerpf(swing, 0.6 if view == "side" else 0.0, q)
		trail_alpha = 0.0
		pose.modulate = Color(1, 1, 1).lerp(Color(0.55, 0.55, 0.6, 0.65), q)
	else:
		if moving:
			# 移动：上下颠 + 左右晃
			pos.y = -absf(sin(t * 12.0)) * 6.0
			rot = sin(t * 12.0) * 0.07 + 0.05
		else:
			# 待机：呼吸
			var b := sin(t * 3.0)
			sy = 1.0 + b * 0.018; sx = 1.0 - b * 0.010
		swing = sin(t * 3.0) * 0.04 if not moving else sin(t * 12.0) * 0.10
		if atk >= 0.0:
			atk += delta / ATTACK_TIME
			var p := atk
			# 侧面：剑平举向前 → 往后上方抬起（-2.3）→ 向前下方劈（+0.9）→ 收回 0
			# 正面：剑垂在身侧 → 顺时针抬起（1.9）→ 劈下（4.75）→ 转回原位（2π）
			var w0: float = SW_SIDE[0] if view == "side" else SW_FRONT[0]
			var w1: float = SW_SIDE[1] if view == "side" else SW_FRONT[1]
			var w2: float = SW_SIDE[2] if view == "side" else SW_FRONT[2]
			trail_from = w0
			if p < 0.28:          # 抬剑蓄力
				var q := p / 0.28
				swing = w0 * (1.0 - pow(1.0 - q, 2.0))
				rot -= 0.10 * q
				pos.x -= 4.0 * q
			elif p < 0.55:        # 劈下 + 向前冲
				var q := (p - 0.28) / 0.27
				q = q * q * (3.0 - 2.0 * q)
				swing = lerpf(w0, w1, q)
				rot += lerpf(-0.10, 0.16, q)
				pos.x += lerpf(-4.0, 16.0, q)
				trail_alpha = 1.0
			elif p < 1.0:         # 收剑（顺势转回原位）
				var q := (p - 0.55) / 0.45
				var e := 1.0 - pow(1.0 - q, 2.0)
				swing = lerpf(w1, w2, e)
				rot += 0.16 * (1.0 - e)
				pos.x += 16.0 * (1.0 - e)
			else:
				atk = -1.0
				swing = 0.0
		# 受击：后仰一下
		rot -= 0.12 * hit
		pos.x -= 5.0 * hit
		pose.modulate = Color(1, 1, 1).lerp(Color(1, 0.35, 0.35), flash)
	trail_alpha = maxf(0.0, trail_alpha - delta * (0.0 if (atk >= 0.28 and atk < 0.55) else 4.0))
	pose.position = Vector2(pos.x * facing, pos.y)
	pose.rotation = rot * facing
	pose.scale = Vector2(k * facing * sx, k * sy)
	sword.rotation = swing
	trail.queue_redraw()
	back_fx.queue_redraw()
	front_fx.queue_redraw()

# ---------- 绘制 ----------
func _sword_vec() -> Vector2:
	var tm: Dictionary = meta[view][tier]
	return Vector2(tm.tip[0], tm.tip[1]) - Vector2(tm.grip[0], tm.grip[1])

func _draw_trail() -> void:
	# 刀光：绕握剑点的一道月牙，从抬剑角度扫到当前角度（贴图坐标，跟着角色翻转）
	if trail_alpha <= 0.01 or tier < 0:
		return
	var tm: Dictionary = meta[view][tier]
	var grip := Vector2(tm.grip[0], tm.grip[1]) - Vector2(meta.foot[0], meta.foot[1])
	var v := _sword_vec()
	var r := v.length() * 1.05
	var a0 := v.angle() + trail_from
	var a1 := v.angle() + swing
	if a1 <= a0:
		return
	var c := weapon_color.lerp(Color.WHITE, 0.55)
	var n := 14
	var pts := PackedVector2Array(); var cols := PackedColorArray()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		var w := float(i) / n
		pts.append(grip + Vector2.from_angle(a) * r)
		cols.append(Color(c, 0.85 * w * trail_alpha))
	for i in range(n, -1, -1):
		var a := lerpf(a0, a1, float(i) / n)
		var w := float(i) / n
		pts.append(grip + Vector2.from_angle(a) * r * (1.0 - 0.38 * w))
		cols.append(Color(c, 0.0))
	trail.draw_polygon(pts, cols)
	trail.draw_arc(grip, r, a1 - 0.5, a1, 8, Color(1, 1, 1, 0.9 * trail_alpha), 5.0)

func _orbit_swords(front: bool, node: Node2D) -> void:
	# 暗金：4 把飞剑绕身体转；在身后的半圈画在身体后面，前半圈画在前面
	var n := 4
	for i in n:
		var a := t * 1.6 + TAU * i / n
		var depth := sin(a)
		if (depth > 0.0) != front:
			continue
		var p := Vector2(cos(a) * 62.0, -62.0 + sin(a) * 14.0 + sin(t * 2.0 + i) * 4.0)
		var sc := 0.85 + 0.15 * depth
		var dir := Vector2(0, 1).rotated(sin(t * 2.0 + i) * 0.25)   # 剑尖朝下，轻微摆动
		var tip := p + dir * 26.0 * sc
		var hilt := p - dir * 12.0 * sc
		var side := dir.orthogonal() * 3.2 * sc
		var glow := Color(1.0, 0.85, 0.4, 0.28 if front else 0.18)
		node.draw_line(hilt, tip, glow, 10.0 * sc)
		node.draw_colored_polygon(PackedVector2Array([p + side, tip, p - side]), Color(0.92, 0.94, 1.0, 0.95 if front else 0.7))
		node.draw_line(p - dir * 0.5 + side * 2.2, p - dir * 0.5 - side * 2.2, Color(0.95, 0.75, 0.25), 2.5 * sc)
		node.draw_line(p, hilt, Color(0.35, 0.22, 0.1), 2.5 * sc)

func _draw_back() -> void:
	if tier < 0 or dead_t >= 0.0:
		return
	if tier == 4:
		# 金光：身后一团暖色光晕
		var pulse := 0.8 + 0.2 * sin(t * 3.0)
		for i in 5:
			back_fx.draw_circle(Vector2(0, -60), 30.0 + i * 11.0, Color(1.0, 0.78, 0.3, 0.07 * pulse))
		back_fx.draw_set_transform(Vector2(0, -2), 0.0, Vector2(1.0, 0.3))
		back_fx.draw_circle(Vector2.ZERO, 52.0, Color(1.0, 0.8, 0.35, 0.25 * pulse))
		back_fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif tier == 6:
		# 暗金：头后光环（旋转光芒 + 双圈）+ 一道光柱
		var head := head_pos()
		var pulse := 0.85 + 0.15 * sin(t * 2.5)
		back_fx.draw_rect(Rect2(-9, -175, 18, 175), Color(1.0, 0.9, 0.55, 0.10 * pulse))
		back_fx.draw_rect(Rect2(-3, -190, 6, 190), Color(1.0, 0.95, 0.75, 0.16 * pulse))
		for i in 4:
			back_fx.draw_circle(head, 34.0 + i * 9.0, Color(1.0, 0.82, 0.35, 0.06 * pulse))
		for i in 12:
			var a := t * 0.5 + TAU * i / 12.0
			var d := Vector2.from_angle(a)
			back_fx.draw_colored_polygon(PackedVector2Array([head + d * 30.0 + d.orthogonal() * 3.0, head + d * 66.0, head + d * 30.0 - d.orthogonal() * 3.0]), Color(1.0, 0.85, 0.4, 0.35 * pulse))
		back_fx.draw_arc(head, 36.0, 0, TAU, 40, Color(1.0, 0.88, 0.45, 0.85), 3.0)
		back_fx.draw_arc(head, 44.0, t, t + TAU * 0.75, 32, Color(1.0, 0.75, 0.25, 0.55), 2.0)
		_orbit_swords(false, back_fx)

func head_pos() -> Vector2:
	# 头的中心（屏幕坐标，相对脚底）：1:1 头身，头中心约在身高 73% 处；侧面图头偏后
	return Vector2((-9.0 if view == "side" else -2.0) * facing, -92.0)

func _draw_front() -> void:
	if tier == 6 and dead_t < 0.0:
		_orbit_swords(true, front_fx)
