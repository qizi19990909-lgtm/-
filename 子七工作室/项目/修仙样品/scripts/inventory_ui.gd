extends Control
## 背包 / 简化详情卡（字号放大 30%；高度随内容增高，超出向右分列，无滚动条；套装与有条件词条按 DNF 式高亮/变灰）。
const UiScale := preload("res://scripts/ui_scale.gd")
var main
var db
var hero_idx := 0
var filter := ""            # "" 全部 / slot_id / "gems"
var cur = null              # 当前详情装备
var cur_equipped := false
var msg := ""
var msg_col := Color.WHITE

var hero_btns: Array = []
var slot_btns := {}
var stats_lbl: RichTextLabel
var filter_btns := {}
var grid: GridContainer
var scroll: ScrollContainer
var detail: Panel
var d_title: Label
var d_info: RichTextLabel
var _fit_sel_sock := false
var _fit_eq_sock := false
var _fit_pass2 := false
var _fit_pass3 := false
var d_cmp: RichTextLabel
var d_sockets: HBoxContainer
var d_equip: Button
var d_enh: Button
var d_msg: Label
var d_lock: Button
var d_devour: Button
var sell_btn: Button
var bag_lbl: Label
var picker: Panel
var picker_box: VBoxContainer
var dimmer: ColorRect
var tip_eq: Dictionary = {}
var tip_sel: Dictionary = {}
var tip_hint: Label

const CARD_W_SINGLE := 380
const CARD_W_CMP := 340
const CARD_GAP := 14
const SCREEN_M := 16
const COL_W := 340
const COL_GAP := 12
const MIN_COL_W := 160
const TITLE_H := 44
const HINT_H := 28
const SOCK_H := 32
const ACT_H := 48
const MSG_H := 24
const SET_ON := "#FFE7A0"
const SET_OFF := "#6E6E76"

func setup(m) -> void:
	main = m; db = m.db
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new(); bg.color = Color(0.06, 0.07, 0.1, 0.985)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(bg)
	# 顶栏
	var ui_theme := Theme.new()
	ui_theme.default_font_size = UiScale.fs(16)
	theme = ui_theme
	var title := _label("背包 · 装备", 26, Color(1, 0.9, 0.6)); title.position = Vector2(16, 8); title.size = Vector2(200, 52); add_child(title)
	for i in main.cfg.heroes.size():
		var b := _button(main.cfg.heroes[i].name, Vector2(148, 58), 20)
		b.position = Vector2(214 + i * 156, 6)
		var k: int = i
		b.pressed.connect(func(): hero_idx = k; cur = null; refresh())
		add_child(b); hero_btns.append(b)
	sell_btn = _button("一键出售白绿", Vector2(196, 58), 19)
	sell_btn.position = Vector2(690, 6); sell_btn.pressed.connect(_on_sell); add_child(sell_btn)
	bag_lbl = _label("", 17, Color(0.9, 0.9, 0.8)); bag_lbl.position = Vector2(894, 4); bag_lbl.size = Vector2(222, 58); add_child(bag_lbl)
	var close := _button("关闭 ✕", Vector2(148, 58), 20)
	close.position = Vector2(1124, 6); close.pressed.connect(main.toggle_bag); add_child(close)
	# 左：已穿戴 13 格（可滚动）
	var eq_sc := ScrollContainer.new()
	eq_sc.position = Vector2(14, 72); eq_sc.size = Vector2(462, 300)
	eq_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(eq_sc)
	var eqg := GridContainer.new(); eqg.columns = 2
	eqg.add_theme_constant_override("h_separation", 8); eqg.add_theme_constant_override("v_separation", 6)
	eq_sc.add_child(eqg)
	for s in db.slots:
		var b := _button("", Vector2(214, 70), 15)
		b.clip_text = false
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var sid: String = s.id
		b.pressed.connect(func():
			var u = _hero()
			if u != null and u.gear.get(sid) != null:
				_open(u.gear[sid], true))
		eqg.add_child(b); slot_btns[sid] = b
	stats_lbl = RichTextLabel.new(); stats_lbl.bbcode_enabled = true
	stats_lbl.position = Vector2(14, 364); stats_lbl.size = Vector2(462, 348)
	stats_lbl.add_theme_font_size_override("normal_font_size", UiScale.fs(18))
	stats_lbl.scroll_active = false
	add_child(stats_lbl)
	# 右：筛选
	var flow := HFlowContainer.new(); flow.position = Vector2(490, 72); flow.size = Vector2(776, 120)
	flow.add_theme_constant_override("h_separation", 6); flow.add_theme_constant_override("v_separation", 6)
	add_child(flow)
	var fl := [["", "全部"]]
	for s in db.slots: fl.append([s.id, s.name])
	fl.append(["gems", "宝石"])
	for f in fl:
		var b := _button(f[1], Vector2(90, 50), 16)
		var fid: String = f[0]
		b.pressed.connect(func(): filter = fid; cur = null; refresh())
		flow.add_child(b); filter_btns[fid] = b
	scroll = ScrollContainer.new(); scroll.position = Vector2(490, 198); scroll.size = Vector2(776, 514)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	grid = GridContainer.new(); grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6); grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	_build_detail()
	_build_picker()

func _build_detail() -> void:
	dimmer = ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.52)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.visible = false
	dimmer.z_index = 8
	dimmer.gui_input.connect(_on_dimmer_input)
	add_child(dimmer)
	tip_hint = _label("点击周围空白处关闭", 16, Color(0.85, 0.85, 0.9, 0.9))
	tip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_hint.z_index = 9
	tip_hint.visible = false
	tip_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tip_hint)
	tip_eq = _make_card(false)
	tip_sel = _make_card(true)
	d_title = tip_sel.title
	d_sockets = tip_sel.sockets
	d_equip = tip_sel.equip
	d_enh = tip_sel.enh
	d_devour = tip_sel.devour
	d_lock = tip_sel.lock
	d_msg = tip_sel.msg
	detail = tip_sel.panel

func _make_card(is_sel: bool) -> Dictionary:
	var p := Panel.new()
	p.visible = false
	p.z_index = 9
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.clip_contents = true
	add_child(p)
	var tag := _label("", 12, Color(0.85, 0.85, 0.9, 0.0))
	tag.visible = false
	p.add_child(tag)
	var title := _label("", 20, Color.WHITE)
	title.position = Vector2(12, 8)
	title.size = Vector2(300, 40)
	title.clip_text = true
	p.add_child(title)
	var close := _button("✕", Vector2(40, 40), 16)
	close.pressed.connect(_close_tooltip)
	p.add_child(close)
	var cols_box := HBoxContainer.new()
	cols_box.add_theme_constant_override("separation", COL_GAP)
	cols_box.clip_contents = true
	p.add_child(cols_box)
	var footer := ColorRect.new()
	footer.color = Color(0.08, 0.09, 0.13, 1.0)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(footer)
	var sockets := HBoxContainer.new()
	sockets.add_theme_constant_override("separation", 8)
	p.add_child(sockets)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	p.add_child(row1)
	var equip := _button("穿戴", Vector2(80, ACT_H), 16)
	var enh := _button("强化", Vector2(96, ACT_H), 15)
	var devour := _button("吞噬", Vector2(72, ACT_H), 16)
	var lock := _button("上锁", Vector2(72, ACT_H), 16)
	row1.add_child(equip)
	row1.add_child(enh)
	row1.add_child(devour)
	row1.add_child(lock)
	var row2 := HBoxContainer.new()
	row2.visible = false
	p.add_child(row2)
	if is_sel:
		equip.pressed.connect(_on_equip)
		enh.pressed.connect(_on_enhance)
		devour.pressed.connect(_on_devour)
		lock.pressed.connect(_on_lock)
	var msg := _label("", 16, Color.WHITE)
	p.add_child(msg)
	return {
		"panel": p, "tag": tag, "title": title, "close": close,
		"cols_box": cols_box, "cols": [], "lines": [], "footer": footer,
		"sockets": sockets, "row1": row1, "row2": row2,
		"equip": equip, "enh": enh, "devour": devour, "lock": lock, "msg": msg
	}

func _set_card_border(panel: Panel, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.98)
	sb.border_color = col
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 10
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	panel.add_theme_stylebox_override("panel", sb)

func _bottom_h(show_actions: bool, has_sockets: bool, has_msg: bool) -> int:
	var h := 8
	if has_sockets:
		h += SOCK_H + 8
	if show_actions:
		h += ACT_H + 6
		if has_msg:
			h += MSG_H
	return h

func _max_card_h() -> int:
	return 720 - SCREEN_M * 2 - HINT_H

func _strip_bb(s: String) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		if s[i] == "[":
			var j := s.find("]", i)
			if j < 0:
				out += s.substr(i)
				break
			i = j + 1
		else:
			out += s[i]
			i += 1
	return out

func _line_h(bb: String, width: int) -> int:
	var plain: String = _strip_bb(bb)
	if plain.strip_edges() == "":
		return 10
	var fs: int = UiScale.fs(16)
	var rows: int = 1
	var wacc := 0
	for i in plain.length():
		var ch: String = plain[i]
		var cw: int = (fs + 1) if ch.unicode_at(0) > 127 else maxi(7, int(ceili(float(fs) * 0.52)))
		if wacc + cw > width and wacc > 0:
			rows += 1
			wacc = cw
		else:
			wacc += cw
	return rows * (fs + 8) + 2

func _ensure_cols(card: Dictionary, n: int) -> void:
	while card.cols.size() < n:
		var rtl := RichTextLabel.new()
		rtl.bbcode_enabled = true
		rtl.fit_content = true
		rtl.scroll_active = false
		rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rtl.add_theme_font_size_override("normal_font_size", UiScale.fs(16))
		card.cols_box.add_child(rtl)
		card.cols.append(rtl)
	for i in card.cols.size():
		var rtl: RichTextLabel = card.cols[i]
		rtl.visible = i < n
		if i >= n:
			rtl.text = ""

func _pack_columns(lines: Array, col_w: int, max_body: int) -> Array:
	max_body = maxi(80, max_body - 20)
	var cols: Array = []
	var cur: Array = []
	var h := 0
	for line in lines:
		var lh: int = _line_h(str(line), col_w)
		if cur.size() > 0 and h + lh > max_body:
			cols.append(cur)
			cur = [line]
			h = lh
		else:
			cur.append(line)
			h += lh
	if cur.size() > 0:
		cols.append(cur)
	if cols.is_empty():
		cols.append([])
	return cols

func _col_text(col_lines: Array) -> String:
	var tx := ""
	for i in col_lines.size():
		tx += str(col_lines[i])
		if i < col_lines.size() - 1:
			tx += "\n"
	return tx

func _body_h(cols: Array, col_w: int) -> int:
	var h := 0
	for col_lines in cols:
		var ch := 0
		for line in col_lines:
			ch += _line_h(str(line), col_w)
		h = maxi(h, ch)
	return maxi(h, 24)

func _card_inner_w(n_cols: int, col_w: int) -> int:
	return PAD_X() * 2 + n_cols * col_w + maxi(0, n_cols - 1) * COL_GAP

func PAD_X() -> int:
	return 12

func _layout_card(card: Dictionary, x: int, y: int, col_w: int, packed: Array, show_actions: bool, has_sockets: bool) -> Vector2:
	var has_msg: bool = show_actions and str(card.msg.text) != ""
	var bottom: int = _bottom_h(show_actions, has_sockets, has_msg)
	var n: int = maxi(1, packed.size())
	var body: int = _body_h(packed, col_w)
	var maxh: int = _max_card_h()
	var h: int = TITLE_H + body + 24 + bottom
	if packed.size() >= 3:
		h = maxh
	h = clampi(h, 160, maxh)
	var w: int = _card_inner_w(n, col_w)
	card.panel.position = Vector2(x, y)
	card.panel.size = Vector2(w, h)
	card.close.position = Vector2(w - 40, 6)
	card.title.size = Vector2(w - 52, 30)
	_ensure_cols(card, n)
	card.cols_box.position = Vector2(PAD_X(), TITLE_H)
	card.cols_box.size = Vector2(w - PAD_X() * 2, h - TITLE_H - bottom)
	card.footer.position = Vector2(3, h - bottom)
	card.footer.size = Vector2(w - 6, bottom - 3)
	for i in n:
		var rtl: RichTextLabel = card.cols[i]
		rtl.custom_minimum_size = Vector2(col_w, 0)
		rtl.size = Vector2(col_w, card.cols_box.size.y)
		rtl.text = _col_text(packed[i])
	var yb: int = h - bottom + 8
	if has_sockets:
		card.sockets.visible = true
		card.sockets.position = Vector2(12, yb)
		card.sockets.size = Vector2(w - 24, SOCK_H)
		yb += SOCK_H + 6
	else:
		card.sockets.visible = false
	if show_actions:
		card.row1.visible = true
		card.row2.visible = false
		var bw: int = int((w - 42) / 4)
		card.equip.custom_minimum_size = Vector2(bw, ACT_H)
		card.enh.custom_minimum_size = Vector2(bw, ACT_H)
		card.devour.custom_minimum_size = Vector2(bw, ACT_H)
		card.lock.custom_minimum_size = Vector2(bw, ACT_H)
		card.row1.position = Vector2(12, yb)
		card.row1.size = Vector2(w - 24, ACT_H)
		yb += ACT_H + 4
		if has_msg:
			card.msg.visible = true
			card.msg.position = Vector2(12, yb)
			card.msg.size = Vector2(w - 24, MSG_H)
		else:
			card.msg.visible = false
	else:
		card.msg.visible = false
		card.row1.visible = false
		card.row2.visible = false
	return Vector2(w, h)

func _pack_to_width(lines: Array, max_body: int, avail: int) -> Dictionary:
	avail = maxi(200, avail)
	max_body = maxi(80, max_body)
	var trial: int = mini(COL_W, maxi(MIN_COL_W, avail - PAD_X() * 2))
	var total_h: int = 0
	for line in lines:
		total_h += _line_h(str(line), trial)
	var n: int = maxi(1, int(ceili(float(maxi(1, total_h)) / float(max_body))))
	for _i in 6:
		var gaps: int = PAD_X() * 2 + maxi(0, n - 1) * COL_GAP
		var cw: int = int((avail - gaps) / n) if n > 0 else trial
		if cw < 150 and n > 1:
			n -= 1
			continue
		cw = maxi(150, cw)
		var packed: Array = _pack_columns(lines, cw, max_body)
		if packed.size() > n:
			var n2: int = packed.size()
			var gaps2: int = PAD_X() * 2 + maxi(0, n2 - 1) * COL_GAP
			var cw2: int = int((avail - gaps2) / n2) if n2 > 0 else cw
			if cw2 >= 150:
				return {"pack": _pack_columns(lines, cw2, max_body), "col_w": cw2}
			return {"pack": packed, "col_w": maxi(150, cw)}
		return {"pack": packed, "col_w": cw}
	var cw_f: int = maxi(150, trial)
	return {"pack": _pack_columns(lines, cw_f, max_body), "col_w": cw_f}

func _merge_cols(cols: Array, keep: int) -> Array:
	if cols.size() <= keep:
		return cols
	var out: Array = []
	for i in keep:
		var cp: Array = []
		for line in cols[i]:
			cp.append(line)
		out.append(cp)
	for j in range(keep, cols.size()):
		for line in cols[j]:
			out[keep - 1].append(line)
	return out

func _layout_tips(compare: bool, sel_has_sockets: bool, eq_has_sockets: bool) -> void:
	var max_w: int = 1280 - SCREEN_M * 2
	var maxh: int = _max_card_h()
	var sel_bot: int = _bottom_h(true, sel_has_sockets, str(tip_sel.msg.text) != "")
	var eq_bot: int = _bottom_h(false, eq_has_sockets, false)
	var sel_max_body: int = maxh - TITLE_H - 6 - sel_bot
	var eq_max_body: int = maxh - TITLE_H - 6 - eq_bot
	var sel_pack: Array = []
	var eq_pack: Array = []
	var col_w_sel: int = COL_W
	var col_w_eq: int = COL_W
	if compare:
		var eq_res: Dictionary = _pack_to_width(tip_eq.get("lines", []), mini(eq_max_body, 420), mini(380, int(max_w * 0.36)))
		eq_pack = eq_res.pack
		col_w_eq = int(eq_res.col_w)
		var eq_tmp: int = _card_inner_w(maxi(1, eq_pack.size()), col_w_eq)
		# 对比时右侧卡片较窄，把分列高度上限压低，优先再开一列，避免最后几行压到按钮
		var sel_res: Dictionary = _pack_to_width(tip_sel.get("lines", []), mini(sel_max_body, 300), max_w - eq_tmp - CARD_GAP)
		sel_pack = sel_res.pack
		col_w_sel = int(sel_res.col_w)
	else:
		var sel_res: Dictionary = _pack_to_width(tip_sel.get("lines", []), sel_max_body, max_w)
		sel_pack = sel_res.pack
		col_w_sel = int(sel_res.col_w)
	var sel_w: int = _card_inner_w(maxi(1, sel_pack.size()), col_w_sel)
	var eq_w: int = _card_inner_w(maxi(1, eq_pack.size()), col_w_eq) if compare else 0
	var total: int = sel_w if not compare else eq_w + CARD_GAP + sel_w
	if total > max_w:
		# 保底：整体左对齐并压缩右边卡片宽度
		sel_w = maxi(220, sel_w - (total - max_w))
		total = max_w
	var x0: int = maxi(SCREEN_M, int((1280 - total) / 2))
	if x0 + total > 1280 - SCREEN_M:
		x0 = SCREEN_M
	var sel_h: int = TITLE_H + _body_h(sel_pack, col_w_sel) + 24 + sel_bot
	# 分列较多时直接用到最大高度，避免最后一列被按钮挡住
	if sel_pack.size() >= 3:
		sel_h = maxh
	sel_h = clampi(sel_h, 160, maxh)
	var eq_h: int = 0
	if compare:
		eq_h = TITLE_H + _body_h(eq_pack, col_w_eq) + 24 + eq_bot
		eq_h = clampi(eq_h, 160, maxh)
	var block_h: int = maxi(sel_h, eq_h)
	var y0: int = maxi(SCREEN_M, int((720 - HINT_H - block_h) / 2))
	if compare:
		_layout_card(tip_eq, x0, y0, col_w_eq, eq_pack, false, eq_has_sockets)
		_layout_card(tip_sel, x0 + eq_w + CARD_GAP, y0, col_w_sel, sel_pack, true, sel_has_sockets)
	else:
		_layout_card(tip_sel, x0, y0, col_w_sel, sel_pack, true, sel_has_sockets)
	tip_hint.position = Vector2(SCREEN_M, y0 + block_h + 4)
	tip_hint.size = Vector2(1280 - SCREEN_M * 2, 22)
	_fit_sel_sock = sel_has_sockets
	_fit_eq_sock = eq_has_sockets
	_fit_pass2 = false
	_fit_pass3 = false
	call_deferred("_fit_tooltip_heights")


func _col_actual_h(card: Dictionary) -> int:
	var h := 0
	for rtl in card.cols:
		if rtl.visible:
			h = maxi(h, int(rtl.get_content_height()))
	return maxi(h, 24)

func _shrink_one_card(card: Dictionary, show_actions: bool, has_sockets: bool) -> void:
	if not card.panel.visible:
		return
	var has_msg: bool = show_actions and str(card.msg.text) != ""
	var bottom: int = _bottom_h(show_actions, has_sockets, has_msg)
	var actual: int = _col_actual_h(card)
	if actual <= 24:
		return
	# get_content_height 偶发偏短，多留一行避免最后几条套装档被按钮挡住
	var h: int = TITLE_H + actual + 44 + bottom
	h = clampi(h, 160, _max_card_h())
	var w: int = int(card.panel.size.x)
	# 只允许加高，避免把已经拉满的分列卡片再缩短，裁掉最后几行
	if h <= int(card.panel.size.y):
		return
	card.panel.size = Vector2(w, h)
	card.cols_box.size = Vector2(w - PAD_X() * 2, h - TITLE_H - bottom)
	card.footer.position = Vector2(3, h - bottom)
	card.footer.size = Vector2(w - 6, bottom - 3)
	var yb: int = h - bottom + 8
	if has_sockets:
		card.sockets.position = Vector2(12, yb)
		card.sockets.size = Vector2(w - 24, SOCK_H)
		yb += SOCK_H + 6
	if show_actions:
		card.row1.position = Vector2(12, yb)
		card.row1.size = Vector2(w - 24, ACT_H)
		yb += ACT_H + 4
		if has_msg:
			card.msg.position = Vector2(12, yb)
			card.msg.size = Vector2(w - 24, MSG_H)

func _visible_col_count(card: Dictionary) -> int:
	var n := 0
	for rtl in card.cols:
		if rtl.visible:
			n += 1
	return n


func _apply_card_height(card: Dictionary, h: int, show_actions: bool, has_sockets: bool) -> void:
	if not card.panel.visible:
		return
	h = clampi(h, 160, _max_card_h())
	var has_msg: bool = show_actions and str(card.msg.text) != ""
	var bottom: int = _bottom_h(show_actions, has_sockets, has_msg)
	var w: int = int(card.panel.size.x)
	card.panel.size = Vector2(w, h)
	card.cols_box.size = Vector2(w - PAD_X() * 2, h - TITLE_H - bottom)
	card.footer.position = Vector2(3, h - bottom)
	card.footer.size = Vector2(w - 6, bottom - 3)
	var yb: int = h - bottom + 8
	if has_sockets:
		card.sockets.position = Vector2(12, yb)
		card.sockets.size = Vector2(w - 24, SOCK_H)
		yb += SOCK_H + 6
	if show_actions:
		card.row1.position = Vector2(12, yb)
		card.row1.size = Vector2(w - 24, ACT_H)
		yb += ACT_H + 4
		if has_msg:
			card.msg.position = Vector2(12, yb)
			card.msg.size = Vector2(w - 24, MSG_H)


func _fit_tooltip_heights() -> void:
	if not tip_sel.panel.visible:
		return
	# 等一帧让 RichTextLabel 算好实际高度，避免缩太狠把后面的行裁掉
	if not _fit_pass2:
		_fit_pass2 = true
		call_deferred("_fit_tooltip_heights")
		return
	if not _fit_pass3:
		_fit_pass3 = true
		call_deferred("_fit_tooltip_heights")
		return
	_fit_pass2 = false
	_fit_pass3 = false
	var compare: bool = tip_eq.panel.visible
	if _visible_col_count(tip_sel) >= 3:
		_apply_card_height(tip_sel, _max_card_h(), true, _fit_sel_sock)
	else:
		_shrink_one_card(tip_sel, true, _fit_sel_sock)
	if compare:
		_shrink_one_card(tip_eq, false, _fit_eq_sock)
	var sel_h: int = int(tip_sel.panel.size.y)
	var eq_h: int = int(tip_eq.panel.size.y) if compare else 0
	var block_h: int = maxi(sel_h, eq_h)
	var y0: int = maxi(SCREEN_M, int((720 - HINT_H - block_h) / 2))
	tip_sel.panel.position.y = y0
	if compare:
		tip_eq.panel.position.y = y0
	tip_hint.position = Vector2(SCREEN_M, y0 + block_h + 4)

func _on_dimmer_input(ev: InputEvent) -> void:
	var tap := false
	if ev is InputEventMouseButton:
		tap = ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT
	elif ev is InputEventScreenTouch:
		tap = ev.pressed
	if not tap:
		return
	if picker.visible:
		picker.visible = false
	else:
		_close_tooltip()
	accept_event()

func _close_tooltip() -> void:
	cur = null
	cur_equipped = false
	picker.visible = false
	msg = ""
	refresh()

func _build_picker() -> void:
	picker = Panel.new()
	picker.position = Vector2(430, 120)
	picker.size = Vector2(420, 470)
	picker.visible = false
	picker.z_index = 20
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.15, 0.22, 1.0)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.8, 0.8, 1.0)
	sb.set_corner_radius_all(8)
	picker.add_theme_stylebox_override("panel", sb)
	add_child(picker)
	var sc := ScrollContainer.new()
	sc.position = Vector2(10, 10)
	sc.size = Vector2(400, 450)
	picker.add_child(sc)
	picker_box = VBoxContainer.new()
	picker_box.add_theme_constant_override("separation", 6)
	sc.add_child(picker_box)

func _label(text: String, sz: int, col: Color) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", UiScale.fs(sz)); l.add_theme_color_override("font_color", col)
	return l

func _button(text: String, sz: Vector2, fs: int) -> Button:
	var b := Button.new(); b.text = text; b.custom_minimum_size = sz; b.size = sz
	b.add_theme_font_size_override("font_size", UiScale.fs(fs))
	return b

func _frame(b: Button, col: Color, fill := 0.18, bw := 3) -> void:
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col.darkened(0.6), 0.9) if st != "hover" else Color(col.darkened(0.45), 0.95)
		sb.bg_color = sb.bg_color.lerp(col, fill * 0.3)
		sb.border_color = col; sb.set_border_width_all(bw); sb.set_corner_radius_all(6)
		sb.content_margin_left = 6; sb.content_margin_right = 6
		b.add_theme_stylebox_override(st, sb)

func _hero():
	var u = main.units[hero_idx] if hero_idx < main.units.size() else null
	return u

# ---------- 刷新 ----------
func refresh() -> void:
	if not visible:
		return
	var u = _hero()
	for i in hero_btns.size():
		var hb: Button = hero_btns[i]
		_frame(hb, Color(0.4, 1.0, 0.5) if i == hero_idx else Color(0.5, 0.5, 0.6), 0.4 if i == hero_idx else 0.0)
	for sid in slot_btns:
		var b: Button = slot_btns[sid]
		var it = u.gear.get(sid)
		var sn: String = db.slot_by_id[sid].name
		if it == null:
			b.text = "%s：空" % sn; _frame(b, Color(0.35, 0.35, 0.4), 0.0, 2)
			b.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		else:
			b.text = "%s %s%s" % [sn, it.name, " +%d" % it.enhance if it.enhance > 0 else ""]
			_frame(b, db.rarity_color(it.rarity), 0.25)
			b.add_theme_color_override("font_color", db.rarity_color(it.rarity).lightened(0.25))
	_refresh_stats(u)
	for fid in filter_btns:
		_frame(filter_btns[fid], Color(1, 0.85, 0.4) if fid == filter else Color(0.45, 0.45, 0.55), 0.5 if fid == filter else 0.0, 2)
	_refresh_grid()
	_refresh_detail()

func _refresh_stats(u) -> void:
	var s: Dictionary = u.stats
	var txt := "[color=#ffe9a0]%s  Lv%d[/color]   外观档：[color=%s]%s[/color]（最低件：%s）\n" % [u.display_name, u.level, db.rarity_color(u.appearance_tier).to_html(false), db.rarity_name(u.appearance_tier), u.lowest_slot_name()]
	txt += "生命 %d   攻击 %d   防御 %d\n" % [int(s.hp), int(s.atk), int(s.def)]
	txt += "攻速 +%.1f%%   移速 +%.1f%%\n" % [s.aspd, s.ms]
	txt += "会心 %.1f%%   会伤 %.0f%%\n" % [s.crit, s.critdmg]
	txt += "命中 +%.1f%%   闪避 %.1f%%\n" % [s.acc, s.eva]
	txt += "技能伤害 +%.1f%%   回复 %.1f/秒\n" % [s.skill, s.regen]
	var el := ""; var rs := ""
	for e in db.elements:
		if s["elem_" + e] > 0.0: el += "%s %.1f  " % [db.elem_names.get(e, e), s["elem_" + e]]
		if s["res_" + e] > 0.0: rs += "%s %.1f%%  " % [db.elem_names.get(e, e), s["res_" + e]]
	txt += "属性伤害：%s\n属性抗性：%s\n" % [el if el != "" else "无", rs if rs != "" else "无"]
	var ths: Array = db.fx_thresholds
	var nxt := ""
	if s.fx_tier < ths.size():
		nxt = "，下一档还差 %d" % (int(ths[s.fx_tier]) - s.enhance_total)
	txt += "[color=#9fe8ff]全身强化 +%d / %d · 特效 %d/%d 档%s[/color]\n[font_size=%d][color=#8890a0]门槛 %s（%s，强化方案 %s，单件上限 +%d）[/color][/font_size]" % [s.enhance_total, db.total_cap, s.fx_tier, ths.size(), nxt, UiScale.fs(14), "/".join(ths.map(func(x): return str(int(x)))), db.fx_source, db.profile_key, db.item_cap]
	stats_lbl.text = txt

func _refresh_grid() -> void:
	var full: bool = not main.bag_has_room()
	bag_lbl.text = "背包 %d/%d%s\n绑银 %d" % [main.bag.size(), main.bag_capacity(), "（已满！）" if full else "", main.silver]
	bag_lbl.add_theme_color_override("font_color", Color(1, 0.45, 0.4) if full else Color(0.9, 0.9, 0.8))
	for c in grid.get_children():
		c.queue_free()
	if filter == "gems":
		var keys: Array = main.gems.keys(); keys.sort()
		for k in keys:
			var n: int = int(main.gems[k])
			if n <= 0: continue
			var gid: String = k.split(":")[0]; var lv: int = int(k.split(":")[1])
			var gd: Dictionary = db.gem_by_id[gid]
			var b := _button("%s Lv%d\n×%d%s" % [gd.name, lv, n, "  合成" if n >= int(db.r.gem_merge_count) and lv < db.gem_max_level(gid) else ""], Vector2(148, 104), 16)
			_frame(b, Color(0.5, 0.9, 0.8), 0.2)
			var kk: String = k
			b.pressed.connect(func(): _merge(kk))
			grid.add_child(b)
		return
	var items: Array = main.bag.filter(func(it): return filter == "" or it.slot == filter)
	items.sort_custom(func(a, b): return a.rarity > b.rarity if a.rarity != b.rarity else a.uid > b.uid)
	for it in items:
		var b := _button("%s%s\nLv%d%s" % ["🔒" if it.get("locked", false) else "", it.name, it.level, " +%d" % it.enhance if it.enhance > 0 else ""], Vector2(148, 118), 15)
		b.clip_text = false
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_frame(b, db.rarity_color(it.rarity), 0.2)
		b.add_theme_color_override("font_color", db.rarity_color(it.rarity).lightened(0.3))
		var itr = it
		b.pressed.connect(func(): _open(itr, false))
		grid.add_child(b)
	if items.is_empty():
		var l := _label("（空）打怪掉落会自动进背包", 18, Color(0.7, 0.7, 0.75))
		grid.add_child(l)

func _open(it, equipped: bool) -> void:
	cur = it; cur_equipped = equipped; msg = ""
	picker.visible = false
	refresh()

func _stat_lines(st: Dictionary) -> String:
	var out := ""
	for k in st:
		out += "%s +%s\n" % [db.stat_label(k), db.fmt_val(k, st[k])]
	return out

func _item_body_lines(it: Dictionary, compare_old) -> Array:
	var slot: Dictionary = db.slot_by_id[it.slot]
	var lines: Array = []
	lines.append("等级：%d" % int(it.level))
	if it.slot == "weapon" and str(it.get("wtype", "")) != "":
		lines.append("武器类型：%s" % db.weapon_type_name(it.wtype))
	else:
		lines.append("部位：%s" % slot.name)
	var core: Dictionary = _core_stats(it)
	var old_core: Dictionary = {} if compare_old == null else _core_stats(compare_old)
	var order: Array = ["atk", "hp", "def", "aspd", "ms", "crit", "critdmg"]
	for k in core:
		if not k in order:
			order.append(k)
	for k in order:
		if not core.has(k):
			continue
		var row := "%s：%s" % [_stat_title(k), db.fmt_val(k, float(core[k]))]
		if compare_old != null:
			row += _delta_bb(float(core[k]), float(old_core.get(k, 0)), k)
		lines.append(row)
	var old_aff: Dictionary = {} if compare_old == null else _affix_sums(compare_old)
	for a in it.affixes:
		var row := "　　%s" % _affix_phrase(str(a.key), float(a.value))
		if compare_old != null:
			row += _delta_bb(float(a.value), float(old_aff.get(a.key, 0)), str(a.key))
		lines.append(row)
	for sk in it.get("skills", []):
		var sl: String = "　　%s" % _skill_line(sk)
		if _has_standing_cond(sk):
			sl = _tone(sl, _cond_met(sk))
		lines.append(sl)
	for sl in _set_lines(it):
		lines.append(sl)
	return lines

func _item_body_text(it: Dictionary, compare_old) -> String:
	return "\n".join(PackedStringArray(_item_body_lines(it, compare_old)))

func _set_lines(it: Dictionary) -> Array:
	var sid: String = str(it.get("set_id", ""))
	if sid == "":
		return []
	var def: Dictionary = db.t.get("sets", {}).get(sid, {})
	if def.is_empty():
		return []
	var lines: Array = [_tone("套装：%s" % str(def.get("name", sid)), true)]
	var groups: Dictionary = def.get("groups", {})
	for gname in groups:
		var g: Dictionary = groups[gname]
		var slots: Array = g.get("slots", [])
		var breaks: Array = g.get("breaks", [])
		var bonus: Dictionary = g.get("bonus", {})
		var cnt: int = _set_count(sid, slots)
		if breaks.is_empty():
			var note: String = _plain_bonus_desc(str(g.get("note", "")))
			if note != "":
				lines.append(_tone("　　%s" % note, false))
			continue
		for b in breaks:
			var bn: Dictionary = bonus.get(str(int(b)), {})
			if bn.is_empty():
				bn = bonus.get(str(b), {})
			var desc: String = _plain_bonus_desc(str(bn.get("desc", "")))
			if str(bn.get("type", "")) == "on_hit_heal":
				var lv_ref: int = int(it.get("level", 10))
				var hv: int = maxi(int(bn.get("value", 0)), db.iround(float(db.white_weapon_atk(lv_ref)) * 0.40))
				var lp: int = int(bn.get("lifesteal", 0))
				if lp > 0:
					desc = "每次攻击回复 %d 点生命；造成伤害的 %d%% 转化为生命" % [hv, lp]
				else:
					desc = "每次攻击回复 %d 点生命" % hv
			var on: bool = cnt >= int(b)
			lines.append(_tone("　　%d件：%s" % [int(b), desc], on))
	return lines

func _set_count(set_id: String, slots: Array) -> int:
	var u = _hero()
	if u == null:
		return 0
	var n := 0
	for sid in slots:
		var g = u.gear.get(str(sid))
		if g != null and str(g.get("set_id", "")) == set_id:
			n += 1
	return n



func _tone(text: String, on: bool) -> String:
	return "[color=%s]%s[/color]" % [SET_ON if on else SET_OFF, text]

func _plain_bonus_desc(s: String) -> String:
	s = s.strip_edges()
	# 去掉「需要 X 件」「（已达成 m/n）」这类条件说明
	var cut := s.find("需要")
	if cut >= 0:
		var rest: String = s.substr(cut)
		if rest.find("件") >= 0 and cut + 8 >= s.length():
			s = s.substr(0, cut).strip_edges()
	var a: int = s.rfind("（")
	var b: int = s.rfind("）")
	if a >= 0 and b > a:
		var inner: String = s.substr(a, b - a + 1)
		if inner.find("件") >= 0 or inner.find("需要") >= 0 or inner.find("达成") >= 0 or inner.find("/") >= 0:
			s = (s.substr(0, a) + s.substr(b + 1)).strip_edges()
	return s

func _hero_hp_pct() -> float:
	var u = _hero()
	if u == null or float(u.max_hp) <= 0.0:
		return 100.0
	return 100.0 * float(u.hp) / float(u.max_hp)

func _has_standing_cond(sk) -> bool:
	if typeof(sk) != TYPE_DICTIONARY:
		return false
	if sk.has("hp_below") or sk.has("hp_above") or sk.has("hp_pct"):
		return true
	var rt = sk.get("runtime", {})
	if typeof(rt) == TYPE_DICTIONARY:
		var typ: String = str(rt.get("type", ""))
		if typ == "passive_highhp_atk" or typ == "passive_lowhp" or rt.has("hp_pct") or rt.has("hp_below"):
			return true
	var desc: String = str(sk.get("desc", ""))
	return desc.find("生命高于") >= 0 or desc.find("生命低于") >= 0

func _cond_met(sk) -> bool:
	if typeof(sk) != TYPE_DICTIONARY:
		return true
	var hp: float = _hero_hp_pct()
	var rt = sk.get("runtime", {})
	if typeof(rt) == TYPE_DICTIONARY:
		if str(rt.get("type", "")) == "passive_highhp_atk" or rt.has("hp_pct"):
			return hp >= float(rt.get("hp_pct", 70))
		if rt.has("hp_below"):
			return hp <= float(rt.get("hp_below", 0))
	if sk.has("hp_below"):
		return hp <= float(sk.get("hp_below", 0))
	if sk.has("hp_above"):
		return hp >= float(sk.get("hp_above", 0))
	var desc: String = str(sk.get("desc", ""))
	if desc.find("生命高于") >= 0:
		return hp >= 70.0
	if desc.find("生命低于") >= 0:
		return hp <= 25.0
	return true


func _stat_title(k: String) -> String:
	if k == "atk":
		return "攻击力"
	var n: String = db.stat_label(k)
	if n.ends_with("%"):
		n = n.substr(0, n.length() - 1)
	return n

func _affix_phrase(k: String, v: float) -> String:
	var n: String = _stat_title(k)
	if n == "攻击力":
		n = "攻击"
	if db.is_pct_key(k) or k.begins_with("res_") or k in ["crit", "critdmg", "ms", "aspd", "acc", "eva", "atk_pct", "hp_pct", "def_pct", "dr_pct", "leech", "skill_leech"]:
		return "%s增加%d%%" % [n.replace("增加", ""), db.iround(v)]
	return "%s +%d" % [n, db.iround(v)]

func _delta_bb(now_v: float, old_v: float, k: String) -> String:
	var d: int = db.iround(now_v) - db.iround(old_v)
	if d == 0:
		return ""
	var txt: String = db.fmt_val(k, abs(float(d)))
	if d > 0:
		return " [color=#4adb6a]▲+%s[/color]" % txt
	return " [color=#ff5a5a]▼-%s[/color]" % txt

func _core_stats(it: Dictionary) -> Dictionary:
	var out := {}
	var plus: int = int(it.get("enhance", 0))
	var lv: int = int(it.get("level", 1))
	var add: int = db.enhance_total_atk(lv, plus)
	var watk: int = maxi(1, db.white_weapon_atk(lv))
	for k in it.main:
		var v: int = db.iround(float(it.main[k]))
		if plus > 0:
			if k == "atk":
				if str(it.slot) == "weapon":
					v += add
				else:
					v += db.iround(float(add) * float(db.white_base(it.slot, lv).get("atk", 0)) / float(watk))
			elif k == "hp":
				v += db.iround(float(add) * float(db.white_base(it.slot, lv).get("hp", 0)) / float(watk))
			elif k == "def":
				v += db.iround(float(add) * float(db.white_base(it.slot, lv).get("def", 0)) / float(watk))
		out[k] = v
	return out

func _affix_sums(it: Dictionary) -> Dictionary:
	var out := {}
	for a in it.get("affixes", []):
		out[a.key] = int(out.get(a.key, 0)) + db.iround(float(a.value))
	return out

func _skill_line(sk) -> String:
	var nm: String = str(sk.get("name", sk.get("id", "技能")))
	var desc: String = str(sk.get("desc", ""))
	for s in ["不能永久锁定。", "不能永久锁定", "（不是永久隐身）", "不是永久隐身。", "不是永久隐身"]:
		desc = desc.replace(s, "")
	desc = desc.strip_edges()
	var cd: int = int(sk.get("cd", 0))
	if cd > 0 and desc.find("冷却") < 0:
		if desc.ends_with("。") or desc.ends_with("."):
			desc = desc.substr(0, desc.length() - 1)
		desc += "，冷却 %d 秒。" % cd
	elif desc != "" and not (desc.ends_with("。") or desc.ends_with(".")):
		desc += "。"
	if desc == "":
		return nm
	return "%s：%s" % [nm, desc]

func _socket_dot(filled: bool, col: Color, clickable: bool) -> Button:
	var b := Button.new()
	var dsz: int = UiScale.px(28)
	b.custom_minimum_size = Vector2(dsz, dsz)
	b.size = Vector2(dsz, dsz)
	b.text = ""
	b.focus_mode = Control.FOCUS_NONE
	if not clickable:
		b.disabled = true
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		if filled:
			sb.bg_color = col if st != "hover" else col.lightened(0.15)
			sb.set_border_width_all(0)
		else:
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = Color(0.75, 0.75, 0.82) if st != "hover" else Color(1, 1, 1)
			sb.set_border_width_all(2)
		sb.set_corner_radius_all(int(dsz / 2))
		b.add_theme_stylebox_override(st, sb)
	return b

func _gem_dot_color(gid: String) -> Color:
	var gk: String = str(db.gem_by_id.get(gid, {}).get("stat", gid))
	if gk == "hp" or gid.find("hp") >= 0:
		return Color(0.35, 0.85, 0.45)
	if gk == "atk" or gid.find("atk") >= 0:
		return Color(0.95, 0.45, 0.25)
	if gk == "def" or gid.find("def") >= 0:
		return Color(0.35, 0.6, 0.95)
	return Color(0.85, 0.7, 0.25)

func _fill_sockets(card: Dictionary, it: Dictionary, clickable: bool) -> void:
	for ch in card.sockets.get_children():
		ch.queue_free()
	for i in it.sockets.size():
		var gm = it.sockets[i]
		var col := Color(0.75, 0.75, 0.82)
		var filled := false
		if gm != null:
			filled = true
			col = _gem_dot_color(str(gm.id))
		var b: Button = _socket_dot(filled, col, clickable)
		var si: int = i
		if clickable:
			b.pressed.connect(func(): _socket_click(si))
		card.sockets.add_child(b)

func _fill_side(card: Dictionary, it: Dictionary, _tag: String, show_actions: bool, compare_old) -> void:
	var col: Color = db.rarity_color(it.rarity)
	_set_card_border(card.panel, col)
	card.tag.visible = false
	card.title.text = "%s +%d" % [db.item_name(it), int(it.enhance)]
	card.title.add_theme_color_override("font_color", col)
	card.lines = _item_body_lines(it, compare_old)
	_fill_sockets(card, it, show_actions)
	if not show_actions:
		card.msg.text = ""
		return
	var u = _hero()
	var can := _can_equip(u, it)
	card.equip.text = "卸下" if cur_equipped else ("穿戴" if can == "" else can)
	card.equip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.equip.clip_text = false
	card.equip.disabled = not cur_equipped and can != ""
	var lv: int = int(it.enhance)
	if lv >= db.enhance_cap_for(it):
		card.enh.text = "已满 +%d" % db.enhance_cap_for(it)
		card.enh.disabled = true
	else:
		var bl: float = float(it.get("blessing", 0.0))
		card.enh.text = "强化 %d%%" % int(round(db.enhance_success_rate(lv, bl) * 100))
		card.enh.disabled = false
	card.lock.visible = not cur_equipped
	card.lock.text = "解锁" if it.get("locked", false) else "上锁"
	card.msg.text = msg
	card.msg.add_theme_color_override("font_color", msg_col)

func _refresh_detail() -> void:
	var open: bool = cur != null
	dimmer.visible = open
	tip_hint.visible = open
	if not open:
		tip_eq.panel.visible = false
		tip_sel.panel.visible = false
		picker.visible = false
		return
	var u = _hero()
	var old = null if u == null else u.gear.get(cur.slot)
	var compare: bool = (not cur_equipped) and old != null
	if compare:
		_fill_side(tip_eq, old, "", false, null)
		_fill_side(tip_sel, cur, "", true, old)
		tip_eq.panel.visible = true
		tip_sel.panel.visible = true
	else:
		tip_eq.panel.visible = false
		_fill_side(tip_sel, cur, "", true, null)
		tip_sel.panel.visible = true
	var sel_sock: bool = cur != null and cur.sockets.size() > 0
	var eq_sock: bool = compare and old != null and old.sockets.size() > 0
	_layout_tips(compare, sel_sock, eq_sock)

func _total_diff(u, slot_id: String, new_it) -> String:
	var g2: Dictionary = u.gear.duplicate()
	g2[slot_id] = new_it
	var a: Dictionary = u.stats
	var b: Dictionary = db.hero_stats(g2, u.level)
	var out := ""
	for k in ["hp", "atk", "def", "aspd", "ms", "crit", "critdmg", "acc", "eva", "skill", "regen", "leech", "hit_heal"] + db.elements.map(func(e): return "elem_" + e) + db.elements.map(func(e): return "res_" + e):
		var d: float = float(b[k]) - float(a[k])
		if absf(d) < 0.05: continue
		out += "  %s %s → %s [color=%s](%s%s)[/color]\n" % [db.stat_label(k), db.fmt_val(k, a[k]), db.fmt_val(k, b[k]), "#5ee07a" if d > 0 else "#ff6060", "+" if d > 0 else "−", db.fmt_val(k, absf(d))]
	if b.enhance_total != a.enhance_total:
		out += "  全身强化 +%d → +%d（特效 %d → %d 档）\n" % [a.enhance_total, b.enhance_total, a.fx_tier, b.fx_tier]
	return out if out != "" else "  （没有变化）\n"

func _can_equip(u, it) -> String:
	if bool(db.t.get("qingshi", {}).get("wear_rule", {}).get("require_hero_level_ge_item_level", false)) and int(it.level) > int(u.level):
		return "需%d级" % int(it.level)
	if it.slot == "weapon" and it.wtype != "" and main.class_restricted():
		var need: String = db.r.hero_weapon_type.get(u.uid, it.wtype)
		if need != it.wtype:
			return "%s用不了%s" % [u.display_name, db.weapon_type_name(it.wtype)]
	return ""

# ---------- 操作 ----------
func _on_equip() -> void:
	var u = _hero()
	if cur == null or u == null:
		return
	if cur_equipped:
		main.unequip(u, cur.slot)
	else:
		main.equip_item(u, cur)
	_close_tooltip()

func _on_enhance() -> void:
	var r: Dictionary = main.enhance_item(cur, _hero() if cur_equipped else null)
	if r.get("capped", false):
		msg = "已强化满"
	elif r.ok:
		msg = "成功！+%d" % r.level
	elif int(r.level) == int(cur.enhance) and int(r.level) == int(r.get("from", r.level)):
		msg = "失败（不掉级）\n祝福 +%d%%" % int(round(float(cur.get("blessing", 0.0)) * 100))
	else:
		msg = "失败，降到 +%d" % r.level
	msg_col = Color(0.4, 1.0, 0.5) if r.ok else Color(1.0, 0.45, 0.4)
	refresh()

func _socket_click(i: int) -> void:
	var gm = cur.sockets[i]
	if gm != null:
		main.unsocket(cur, i, _hero() if cur_equipped else null)
		refresh(); return
	for ch in picker_box.get_children(): ch.queue_free()
	picker_box.add_child(_label("选择宝石（%s可镶）" % db.slot_by_id[cur.slot].name, 18, Color(1, 0.9, 0.6)))
	var cat: String = db.slot_by_id[cur.slot].get("category", "")
	var keys: Array = main.gems.keys(); keys.sort()
	var any := false
	for k in keys:
		var gid: String = k.split(":")[0]; var lv: int = int(k.split(":")[1])
		if int(main.gems[k]) <= 0 or not (cur.slot in db.gem_by_id[gid].slots):
			continue
		any = true
		var gk: String = db.gem_stat(gid, cat)
		var b := _button("%s Lv%d ×%d  %s +%s" % [db.gem_by_id[gid].name, lv, int(main.gems[k]), db.stat_label(gk), db.fmt_val(gk, db.gem_value(gid, lv, cat))], Vector2(390, 48), 17)
		var kk: String = k
		b.pressed.connect(func():
			main.socket(cur, i, kk, _hero() if cur_equipped else null)
			picker.visible = false; refresh())
		picker_box.add_child(b)
	if not any:
		picker_box.add_child(_label("没有能镶在这里的宝石", 17, Color(0.8, 0.8, 0.8)))
	var cb := _button("取消", Vector2(390, 48), 18); cb.pressed.connect(func(): picker.visible = false)
	picker_box.add_child(cb)
	picker.visible = true

func _on_lock() -> void:
	cur.locked = not bool(cur.get("locked", false))
	main.save_game()
	refresh()

func _on_sell() -> void:
	var r: Dictionary = main.sell_junk()
	cur = null
	refresh()
	bag_lbl.text += "  卖出 %d 件 +%d" % [r.n, r.silver]

func _merge(k: String) -> void:
	main.merge_gem(k)
	refresh()


func _on_devour() -> void:
	if cur == null:
		return
	for ch in picker_box.get_children():
		ch.queue_free()
	picker_box.add_child(_label("选一件同部位装备当作材料（强化和石头不跟着走，石头会消失）", 16, Color(1, 0.9, 0.6)))
	var any := false
	for it in main.bag:
		if it == cur:
			continue
		if str(it.slot) != str(cur.slot):
			continue
		if it.get("locked", false):
			continue
		any = true
		var b := _button("%s %s +%d  经验+%d" % [db.rarity_name(it.rarity), it.name, int(it.enhance), db.inherent_xp(it)], Vector2(380, 52), 15)
		var src: Dictionary = it
		b.pressed.connect(func():
			var r: Dictionary = main.devour_item(cur, src, _hero() if cur_equipped else null)
			picker.visible = false
			if r.get("ok", false):
				msg = "吞噬成功，经验 +%d" % int(r.get("xp_gained", 0))
				if int(r.get("upgrades", 0)) > 0:
					msg += "，升到" + "、".join(PackedStringArray(r.get("unlocked", [])))
				if int(r.get("gems_destroyed", 0)) > 0:
					msg += "（材料上的石头已消失）"
				msg_col = Color(0.5, 1.0, 0.6)
			else:
				msg = str(r.get("msg", "不能吞噬"))
				msg_col = Color(1.0, 0.5, 0.4)
			refresh())
		picker_box.add_child(b)
	if not any:
		picker_box.add_child(_label("背包里没有同部位、未上锁的材料。", 16, Color(1.0, 0.6, 0.5)))
	var c := _button("取消", Vector2(200, 48), 18)
	c.pressed.connect(func(): picker.visible = false)
	picker_box.add_child(c)
	picker.visible = true
