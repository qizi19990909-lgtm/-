extends Node2D
## 地上的掉落物（装备或宝石）：代码绘制的品质色宝箱/光柱，点一下拾取，过几秒自动拾取。
const UiScale := preload("res://scripts/ui_scale.gd")
var main
var item := {}          # 装备字典；宝石时为空
var gem_id := ""
var color := Color.WHITE
var label := ""
var rarity := 0
var t := 0.0
var auto_t := 2.5
var picked := false

func _ready() -> void:
	z_index = 4
	scale = Vector2(0.2, 0.2)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	t += delta
	if picked:
		return
	auto_t -= delta
	if auto_t <= 0.0:
		pickup()
	queue_redraw()

func hit_test(p: Vector2) -> bool:
	return Rect2(position + Vector2(-46, -70), Vector2(92, 90)).has_point(p)

func pickup() -> void:
	if picked:
		return
	if not item.is_empty() and not main.bag_has_room():
		main.notify_bag_full(position)
		auto_t = 2.0
		return
	picked = true
	main.on_loot_picked(self)
	var tw := create_tween()
	tw.tween_property(self, "position", position + Vector2(0, -60), 0.25)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)

func _draw() -> void:
	var bob := sin(t * 4.0) * 3.0
	# 紫及以上：竖直光柱
	if rarity >= 3 and gem_id == "":
		draw_rect(Rect2(-6, -150, 12, 150), Color(color, 0.25 + 0.1 * sin(t * 5.0)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 22, Color(color, 0.35))
	draw_arc(Vector2.ZERO, 26, 0, TAU, 32, color, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var c := Vector2(0, -18 + bob)
	if gem_id != "":
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -14), c + Vector2(11, 0), c + Vector2(0, 14), c + Vector2(-11, 0)]), color)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -14), c + Vector2(5, -2), c + Vector2(-5, -2)]), Color(1, 1, 1, 0.6))
	else:
		draw_rect(Rect2(c + Vector2(-15, -11), Vector2(30, 22)), color.darkened(0.35))
		draw_rect(Rect2(c + Vector2(-15, -11), Vector2(30, 22)), color, false, 3.0)
		draw_rect(Rect2(c + Vector2(-15, -4), Vector2(30, 4)), color.lightened(0.3))
	var f: Font = main.font
	draw_string_outline(f, Vector2(-110, -48 + bob), label, HORIZONTAL_ALIGNMENT_CENTER, 220, UiScale.fs(17), 5, Color(0, 0, 0, 0.85))
	draw_string(f, Vector2(-110, -48 + bob), label, HORIZONTAL_ALIGNMENT_CENTER, 220, UiScale.fs(17), color)
