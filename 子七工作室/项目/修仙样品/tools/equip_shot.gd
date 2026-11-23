extends Node
## 换装对比截图（开发用）：同一批角色先全白装、再全暗金装各截一张。
## 用法：xvfb-run godot --path . res://tools/equip_shot.tscn
## 输出：截图/equip_before_white.png、截图/equip_after_darkgold.png、截图/equip_mixed_blue_red.png（另有 *_iphone.png 缩到 iPhone 横屏大小）

var main

func _ready() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	for u in main.units:
		u.set_process(false)          # 定住站位，方便对比
	var pos := [Vector2(640, 470), Vector2(420, 470), Vector2(860, 470)]
	for i in main.units.size():
		main.units[i].position = pos[i]
		main.units[i].facing = 1.0
	await _shot(0, "equip_before_white")
	await _shot(6, "equip_after_darkgold")
	await _shot(2, "equip_mixed_blue_red", 5)   # 衣服头盔蓝 + 武器红：衣服和武器分别显示
	get_tree().quit()

func _shot(tier: int, name: String, weapon_tier := -1) -> void:
	for u in main.units:
		u.debug_look(tier, tier if weapon_tier < 0 else weapon_tier)
		u.t = 1.3
		u._refresh_visual(false)
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://") + "截图/"
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir + name + ".png")
	var small := img.duplicate()
	small.resize(844, 475, Image.INTERPOLATE_LANCZOS)   # iPhone 横屏宽度约 844 点
	small.save_png(dir + name + "_iphone.png")
	print("SHOT ", dir + name + ".png")
