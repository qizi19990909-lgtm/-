extends Node2D
var mode := "skel"
var n := 30
var frames := 0
var t0 := 0
const WARM := 30
const MEASURE := 600
var tex: Texture2D

var acc := 0.0
func _ready():
	Engine.max_fps = 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("mode="): mode = a.substr(5)
		if a.begins_with("n="): n = int(a.substr(2))
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8); img.fill(Color.WHITE)
	tex = ImageTexture.create_from_image(img)
	for i in n:
		var u: Node2D
		match mode:
			"skel": u = make_skel()
			"anim": u = make_anim()
			"spine": u = make_spine()
		u.position = Vector2(randf()*1280, 200+randf()*400)
		add_child(u)

func make_skel() -> Node2D:
	# 15 bones ~ 美术规范 2.1 主要骨骼量级; each bone with a Sprite2D part
	var root := Node2D.new()
	var sk := Skeleton2D.new(); root.add_child(sk)
	var names := ["hip","body","head","hair_b","hair_f","headgear","hand_L","hand_R","weapon_main","weapon_off","foot_L","foot_R","back","cape","fx"]
	var parent: Node = sk
	var bones := []
	for i in names.size():
		var b := Bone2D.new(); b.name = names[i]; b.position = Vector2(0, -6)
		b.set_autocalculate_length_and_angle(false); b.set_length(10); b.rest = Transform2D(0, Vector2(0,-6))
		(sk if i < 2 else bones[1 if i>2 else 0]).add_child(b)
		var s := Sprite2D.new(); s.texture = tex; b.add_child(s)
		bones.append(b)
	var ap := AnimationPlayer.new(); root.add_child(ap)
	var lib := AnimationLibrary.new(); var anim := Animation.new(); anim.length = 0.5; anim.loop_mode = Animation.LOOP_LINEAR
	for b in bones:
		var tr := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(tr, NodePath("../Skeleton2D/" + str(sk.get_path_to(b)) + ":rotation"))
		anim.track_insert_key(tr, 0.0, 0.0); anim.track_insert_key(tr, 0.25, 0.4); anim.track_insert_key(tr, 0.5, 0.0)
	lib.add_animation("run", anim); ap.add_animation_library("", lib)
	ap.play("run"); ap.seek(randf()*0.5)
	return root

func make_anim() -> Node2D:
	var a := AnimatedSprite2D.new(); var sf := SpriteFrames.new()
	sf.set_animation_speed("default", 12)
	for i in 6: sf.add_frame("default", tex)
	a.sprite_frames = sf; a.play("default")
	return a

func make_spine() -> Node2D:
	var sd = ClassDB.instantiate("SpineSkeletonDataResource")
	sd.atlas_res = load("res://spine/spineboy-pma.atlas")
	sd.skeleton_file_res = load("res://spine/spineboy-pro.skel")
	var sp = ClassDB.instantiate("SpineSprite")
	sp.skeleton_data_res = sd
	sp.get_animation_state().set_animation("run", true, 0)
	sp.scale = Vector2(0.2, 0.2)
	return sp

func _process(_d):
	frames += 1
	if frames == WARM: t0 = Time.get_ticks_usec()
	if frames > WARM: acc += Performance.get_monitor(Performance.TIME_PROCESS)
	if frames == WARM + MEASURE:
		var us := float(Time.get_ticks_usec() - t0) / MEASURE
		print("RESULT mode=%s n=%d wall_us=%.1f process_us=%.1f" % [mode, n, us, acc/MEASURE*1e6])
		get_tree().quit()
