extends Node
## 剑修七品阶对比截图（开发用）。
## 用法：xvfb-run -s "-screen 0 1280x720x24" godot --path . --resolution 844x475 res://tools/swordsman_tiers_shot.tscn
## 输出：
##   截图/swordsman_7tiers_front_side_iphone.png —— 游戏内七档并排：上排正面、下排侧面（待机，武器发光关掉），844×475（iPhone 横屏宽度）
##   截图/swordsman_darkgold_battle_iphone.png —— 暗金档实战（挥剑瞬间），844×475

const UnitScript := preload("res://scripts/unit.gd")
var main

func _ready() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await _compare()
	await _battle()
	get_tree().quit()

func _compare() -> void:
	main.set_process(false)          # 不刷怪
	for u in main.units:
		u.visible = false; u.set_process(false)
	var ws := []
	var extra := []
	for row in 2:
		var view := "front" if row == 0 else "side"
		for i in 7:
			var u = UnitScript.new()
			main.world.add_child(u)
			u.position = Vector2(110 + i * 177, 400 + row * 230)
			u.setup_hero(main.cfg.heroes[0], main)
			# 武器档设成白：去掉武器换色发光，看清每档剑本身的样子
			u.debug_look(i, 0)
			u.facing = 1.0
			u.rig.set_view(view)
			ws.append(u)
			var l := Label.new()
			l.text = main.tier_name(i) + ("·正面" if row == 0 else "·侧面")
			l.add_theme_font_size_override("font_size", 22)
			l.add_theme_color_override("font_color", main.tier_color(i))
			l.add_theme_color_override("font_outline_color", Color.BLACK)
			l.add_theme_constant_override("outline_size", 6)
			l.position = u.position + Vector2(-42, 14)
			l.z_index = 20
			main.world.add_child(l)
			extra.append(l)
	main.selected = null
	for i in 90:
		await get_tree().process_frame
	await _save("swordsman_7tiers_front_side_iphone.png")
	for u in ws:
		u.queue_free()
	for l in extra:
		l.queue_free()
	for u in main.units:
		u.visible = true; u.set_process(true)
	await get_tree().process_frame

func _battle() -> void:
	main.set_process(true)
	var w = main.units[0]
	w.debug_look(6, 6)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 25000:
		await get_tree().process_frame
		var r = w.rig
		if main.wave_idx >= 0 and main.enemies().size() >= 2 and Time.get_ticks_msec() - t0 > 2500 and r.atk > 0.40 and r.atk < 0.52:
			break
	await _save("swordsman_darkgold_battle_iphone.png")

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://") + "截图/"
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir + name)
	print("SHOT ", dir + name, " ", img.get_size())
