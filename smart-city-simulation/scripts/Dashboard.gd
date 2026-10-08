class_name Dashboard
extends CanvasLayer

var sim: CitySim

var _time_lbl: Label
var _speed_lbl: Label
var _kpi_box: VBoxContainer
var _kpi_labels := {}
var _charts := {}
var _tables := {}
var _overlay_btn: OptionButton

var _speed_index := 2
var _speeds := [0.0, 1.0, 3.0, 12.0, 48.0]
var _speed_names := ["PAUSED", "1×", "3×", "12×", "48×"]

var main: Node

# palette
const C_BG      := Color(0.055, 0.062, 0.078)
const C_PANEL   := Color(0.078, 0.086, 0.105)
const C_BORDER  := Color(0.16, 0.18, 0.22)
const C_TEXT    := Color(0.82, 0.85, 0.89)
const C_DIM     := Color(0.46, 0.50, 0.56)
const C_ACCENT  := Color(0.38, 0.76, 0.96)
const C_GOOD    := Color(0.36, 0.80, 0.52)
const C_WARN    := Color(0.94, 0.74, 0.28)
const C_BAD     := Color(0.90, 0.36, 0.32)

# ─────────────────────────────────────────────────────────────
func setup(sim_ref: CitySim, main_ref: Node) -> void:
	sim = sim_ref
	main = main_ref
	layer = 10
	_build()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_topbar(root)
	_build_left(root)
	_build_right(root)
	_build_bottom(root)

func _panel(parent: Control, rect: Rect2) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", _style(C_PANEL, C_BORDER))
	parent.add_child(p)
	return p

func _style(bg: Color, border: Color, radius := 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

# ── TOP BAR ──────────────────────────────────────────────────
func _build_topbar(root: Control) -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 46)
	bar.add_theme_stylebox_override("panel", _style(C_BG, C_BORDER, 0))
	root.add_child(bar)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	bar.add_child(h)

	var title := Label.new()
	title.text = "SMART CITY SIMULATION"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", C_ACCENT)
	h.add_child(title)

	h.add_child(_vsep())

	_time_lbl = Label.new()
	_time_lbl.add_theme_font_size_override("font_size", 13)
	_time_lbl.add_theme_color_override("font_color", C_TEXT)
	h.add_child(_time_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	var ov_lbl := Label.new()
	ov_lbl.text = "OVERLAY"
	ov_lbl.add_theme_font_size_override("font_size", 11)
	ov_lbl.add_theme_color_override("font_color", C_DIM)
	h.add_child(ov_lbl)

	_overlay_btn = OptionButton.new()
	for n in CityBuilder.OVERLAY_NAMES:
		_overlay_btn.add_item(n)
	_overlay_btn.selected = 0
	_overlay_btn.item_selected.connect(func(i): main.set_overlay(i))
	h.add_child(_overlay_btn)

	h.add_child(_vsep())

	for i in _speed_names.size():
		var b := Button.new()
		b.text = _speed_names[i]
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(func(): _set_speed(i))
		h.add_child(b)

	_speed_lbl = Label.new()
	_speed_lbl.add_theme_font_size_override("font_size", 11)
	_speed_lbl.add_theme_color_override("font_color", C_DIM)
	h.add_child(_speed_lbl)

func _vsep() -> Control:
	var c := ColorRect.new()
	c.color = C_BORDER
	c.custom_minimum_size = Vector2(1, 22)
	return c

func _set_speed(i: int) -> void:
	_speed_index = i
	_speed_lbl.text = "  " + _speed_names[i]

func speed_hours_per_second() -> float:
	return _speeds[_speed_index]

# ── LEFT: KPI PANEL ──────────────────────────────────────────
func _build_left(root: Control) -> void:
	var p := _panel(root, Rect2(10, 56, 330, 560))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)

	_kpi_box = VBoxContainer.new()
	_kpi_box.add_theme_constant_override("separation", 1)
	_kpi_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_kpi_box)

	var groups := {}
	for k in CitySim.METRICS:
		var g: String = CitySim.METRICS[k][0]
		if not groups.has(g): groups[g] = []
		groups[g].append(k)

	for g in groups:
		_kpi_box.add_child(_section_header(g))
		for k in groups[g]:
			_kpi_box.add_child(_metric_row(k))

func _section_header(text: String) -> Control:
	var c := MarginContainer.new()
	c.add_theme_constant_override("margin_top", 10)
	c.add_theme_constant_override("margin_bottom", 3)
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", C_ACCENT)
	c.add_child(l)
	return c

func _metric_row(key: String) -> Control:
	var d: Array = CitySim.METRICS[key]
	var row := HBoxContainer.new()

	var name_l := Label.new()
	name_l.text = d[1]
	name_l.add_theme_font_size_override("font_size", 11)
	name_l.add_theme_color_override("font_color", C_DIM)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)

	var val_l := Label.new()
	val_l.add_theme_font_size_override("font_size", 11)
	val_l.add_theme_color_override("font_color", C_TEXT)
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_l.custom_minimum_size = Vector2(118, 0)
	row.add_child(val_l)

	_kpi_labels[key] = val_l
	return row

# ── RIGHT: CHARTS ────────────────────────────────────────────
func _build_right(root: Control) -> void:
	var p := _panel(root, Rect2(1250, 56, 340, 560))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)

	var hdr := Label.new()
	hdr.text = "TRENDS"
	hdr.add_theme_font_size_override("font_size", 10)
	hdr.add_theme_color_override("font_color", C_ACCENT)
	v.add_child(hdr)

	var charts := [
		["population", "Population", Color(0.42, 0.78, 0.98)],
		["net_budget", "Net Budget ($/day)", Color(0.46, 0.86, 0.56)],
		["aqi", "Air Quality Index", Color(0.96, 0.62, 0.34)],
		["energy_demand_mw", "Energy Demand (MW)", Color(0.90, 0.82, 0.36)],
		["unemployment_rate", "Unemployment", Color(0.94, 0.48, 0.52)],
		["sustainability", "Sustainability Index", Color(0.50, 0.86, 0.72)],
	]
	for c in charts:
		v.add_child(_chart_block(c[0], c[1], c[2]))

func _chart_block(key: String, label: String, col: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var head := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", C_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)

	var v := Label.new()
	v.add_theme_font_size_override("font_size", 10)
	v.add_theme_color_override("font_color", C_TEXT)
	head.add_child(v)
	_charts[key + "_val"] = v

	box.add_child(head)

	var sp := Sparkline.new()
	sp.line_color = col
	sp.fill_color = Color(col.r, col.g, col.b, 0.13)
	sp.custom_minimum_size = Vector2(0, 46)
	box.add_child(sp)
	_charts[key] = sp
	return box

# ── BOTTOM: REPORT TABS ──────────────────────────────────────
func _build_bottom(root: Control) -> void:
	var p := _panel(root, Rect2(350, 626, 890, 264))

	var tabs := TabContainer.new()
	tabs.add_theme_font_size_override("font_size", 11)
	p.add_child(tabs)

	for group in ["Society", "Economy", "Infrastructure", "Environment", "Smart Systems"]:
		var scroll := ScrollContainer.new()
		scroll.name = group
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)

		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 26)
		grid.add_theme_constant_override("v_separation", 3)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(grid)

		var table := {}
		for k in CitySim.METRICS:
			if CitySim.METRICS[k][0] != group: continue
			var nl := Label.new()
			nl.text = CitySim.METRICS[k][1]
			nl.add_theme_font_size_override("font_size", 11)
			nl.add_theme_color_override("font_color", C_DIM)
			grid.add_child(nl)

			var vl := Label.new()
			vl.add_theme_font_size_override("font_size", 11)
			vl.add_theme_color_override("font_color", C_TEXT)
			vl.custom_minimum_size = Vector2(110, 0)
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(vl)
			table[k] = vl

			var ul := Label.new()
			ul.text = CitySim.METRICS[k][2]
			ul.add_theme_font_size_override("font_size", 10)
			ul.add_theme_color_override("font_color", Color(0.34, 0.37, 0.42))
			grid.add_child(ul)

		_tables[group] = table

# ─────────────────────────────────────────────────────────────
#  REFRESH
# ─────────────────────────────────────────────────────────────
func refresh() -> void:
	_time_lbl.text = sim.date_string()

	for k in _kpi_labels:
		_kpi_labels[k].text = _fmt(k)

	for group in _tables:
		for k in _tables[group]:
			_tables[group][k].text = _fmt(k)

	for key in _charts:
		if key.ends_with("_val"):
			continue
		var sp: Sparkline = _charts[key]
		sp.set_values(sim.metrics.series(key))
		var vl: Label = _charts.get(key + "_val")
		if vl:
			var disp := _fmt(key)
			vl.text = disp

func _fmt(key: String) -> String:
	var d: Array = CitySim.METRICS.get(key)
	var raw: float = sim.metrics.latest(key, sim.s.get(key, 0.0))
	if d == null:
		return _num(raw, "", false)

	var scale: float = d[3]
	var is_int: bool = d[4]
	var v: float = raw * scale
	return _num(v, d[2], is_int)

func _num(v: float, unit: String, is_int: bool) -> String:
	var body: String
	if is_int:
		body = _thousands(int(round(v)))
	elif absf(v) >= 1000.0:
		body = _thousands(int(round(v)))
	elif absf(v) >= 100.0:
		body = "%.0f" % v
	elif absf(v) >= 10.0:
		body = "%.1f" % v
	else:
		body = "%.2f" % v

	if unit == "$" or unit.begins_with("$"):
		body = "$" + body
	if unit != "" and not unit.begins_with("$"):
		body += " " + unit
	return body

func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
