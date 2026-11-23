extends SceneTree

func _init() -> void:
	var db = load("res://scripts/equip_db.gd").new()
	if not db.load_tables():
		push_error("load_tables failed")
		quit(1)
		return
	print("version=", db.t.get("version", ""))
	print("slots=", db.slots.size())
	var it = db.make_item("weapon", 5, 30, "blade")
	print("item=", it.name, " rarity=", db.rarity_name(it.rarity), " atk_main=", it.main, " skills=", it.get("skills", []), " enhance_cap=", db.enhance_cap_for(it))
	var st = db.item_stats(it)
	print("item_stats=", st)
	it.enhance = 10
	print("after+10=", db.item_stats(it), " step totals", db.enhance_total_atk(30, 10), db.enhance_total_atk(30, 20))
	var drops := {"白":0,"绿":0,"蓝":0,"紫":0,"橙":0,"红":0,"暗金":0}
	var n_items := 0
	for i in 2000:
		for it2 in db.roll_drop("normal", "qingshi", 10, {}, ""):
			n_items += 1
			drops[db.rarity_name(it2.rarity)] = int(drops[db.rarity_name(it2.rarity)]) + 1
	print("2000 normal lv10 drops items=", n_items, " by=", drops)
	var src := {"atk":271,"def":20,"level":20,"acc":0.0,"eva":0.0,"crit":5.0,"critdmg":150.0,"skill_pct":0.0,"elem":{},"res":{},"stacks":{},"hit_down":0.0}
	var tgt := {"atk":10,"def":301,"level":30,"acc":0.0,"eva":0.0,"crit":5.0,"critdmg":150.0,"skill_pct":0.0,"elem":{},"res":{},"stacks":{},"hit_down":0.0}
	# force hit: acc high
	src.acc = 100
	tgt.eva = 0
	var d = db.compute_damage(src, tgt, 1.0, false)
	print("dmg 271 vs def 301 =", d)
	var ev = db.monster_stats("wolf", 10)
	print("wolf10=", ev)
	var bo = db.monster_stats("boss", 10)
	print("boss10=", bo)
	print("OK")
	quit(0)
