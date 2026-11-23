extends Node2D
## 投射物：箭（弓手）/ 法球（法师）。颜色 = 武器品质色。
var main
var src
var tgt
var dmg := 10.0
var spd := 500.0
var color := Color.WHITE
var kind := "archer"
var delay := 0.0
var is_skill := false
var life := 3.0

func _process(delta: float) -> void:
	if delay > 0.0:
		delay -= delta
		visible = false
		return
	visible = true
	life -= delta
	if tgt == null or not is_instance_valid(tgt) or tgt.dead or life <= 0.0:
		queue_free(); return
	var aim: Vector2 = tgt.position + Vector2(0, -40 * tgt.size if tgt.team == "enemy" else -50)
	var d: Vector2 = aim - position
	if d.length() < spd * delta + 8.0:
		main.deal_damage(src, tgt, dmg, is_skill)
		queue_free(); return
	position += d.normalized() * spd * delta
	rotation = d.angle()
	queue_redraw()

func _draw() -> void:
	if kind == "archer":
		draw_line(Vector2(-18, 0), Vector2(10, 0), Color(color, 0.4), 6)
		draw_line(Vector2(-18, 0), Vector2(10, 0), Color(0.55, 0.4, 0.25), 2)
		draw_colored_polygon(PackedVector2Array([Vector2(16, 0), Vector2(8, -5), Vector2(8, 5)]), color)
	else:
		draw_circle(Vector2.ZERO, 12, Color(color, 0.3))
		draw_circle(Vector2.ZERO, 7, color)
		draw_circle(Vector2(-2, -2), 3, Color(1, 1, 1, 0.8))
