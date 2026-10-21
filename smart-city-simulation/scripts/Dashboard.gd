class_name Dashboard
extends CanvasLayer

const REFRESH_HZ_DESKTOP := 6.0
const REFRESH_HZ_MOBILE  := 3.0

var sim: CitySim
var mobile: bool = false

var _time_lbl: Label
var _speed_lbl: Label
var _kpi_box: VBoxContainer
var _kpi_labels := {}
var _charts := {}
var _tables := {}
var _overlay_btn: OptionButton
var _night_btn: Button
var _wealth_btn: Button
var _is_night: bool = false
var _wealth_on: bool = false
var _overlay_before_wealth: int = 0

var _speed_index := 2
var _speeds := [0.0, 1.0, 3.0, 12.0, 48.0]
var _speed_names := ["PAUSED", "1×", "3×", "12×", "48×"]

var main: Node

var _refresh_accum := 0.0
var _refresh_interval := 1.0 / REFRESH_HZ_DESKTOP
var _last_kpi_text := {}
var _last_tab_text := {}
var _last_series_day := -1
var _cached_series := {}

var _slider_labels := {}
var _sliders := {}
const POLICY_ROWS := [
	["pol_min_wage",        "Minimum Wage"],
	["pol_housing_supply",  "Housing Supply"],
	["pol_police_funding",  "Police Funding"],
	["pol_education_spend", "Education Spending"],
	["pol_transit_invest",  "Transit Investment"],
	["pol_green_space",     "Green Space"],
	["pol_pollution_ctrl",  "Pollution Control"],
	["pol_waste_mgmt",      "Waste Management"],
	["pol_water_treat",     "Water Treatment"],
	["pol_tax_income",      "Income Tax Rate"],
	["pol_tax_business",    "Business Tax Rate"],
]

const CHART_DEFS := [
	["population",         "Population",             Color(0.42, 0.78, 0.98)],
	["net_budget",         "Net Budget ($/day)",     Color(0.46, 0.86, 0.56)],
	["unemployment_rate",  "Unemployment",           Color(0.94, 0.48, 0.52)],
	["homeless_pct",       "Homelessness",           Color(0.92, 0.56, 0.62)],
	["crime_rate",         "Crime Rate",             Color(0.96, 0.40, 0.44)],
	["health_index",       "Health Index",           Color(0.52, 0.86, 0.68)],
	["avg_education",      "Education Level",        Color(0.72, 0.62, 0.94)],
	["median_rent",        "Median Rent",            Color(0.94, 0.72, 0.36)],
	["median_income",      "Median Income",          Color(0.60, 0.86, 0.42)],
	["traffic_congestion", "Congestion",             Color(0.96, 0.54, 0.36)],
	["transit_share",      "Transit Mode Share",     Color(0.44, 0.72, 0.94)],
	["energy_demand_mw",   "Energy Demand (MW)",     Color(0.90, 0.82, 0.36)],
	["water_quality",      "Water Quality",          Color(0.36, 0.80, 0.90)],
	["aqi",                "Air Quality Index",      Color(0.96, 0.62, 0.34)],
	["co2_per_capita",     "CO₂ per Capita",         Color(0.78, 0.56, 0.42)],
	["recycling_rate",     "Recycling Rate",         Color(0.38, 0.82, 0.48)],
	["renewable_share",    "Renewable Share",        Color(0.94, 0.86, 0.40)],
	["sustainability",     "Sustainability Index",   Color(0.50, 0.86, 0.72)],
	["gdp_per_capita",     "GDP per Capita",         Color(0.66, 0.86, 0.52)],
	["local_business_share","Local Business Share",  Color(0.86, 0.68, 0.42)],
	["avg_wage",           "Average Wage",           Color(0.72, 0.86, 0.52)],
	["reserve",            "Municipal Reserves",     Color(0.56, 0.74, 0.94)],
	["smart_grid",         "Smart Grid",             Color(0.52, 0.78, 0.94)],
	["digital_adoption",   "Digital Adoption",       Color(0.62, 0.82, 0.92)],
]

const UI_SCALE := 1.45

const F_TITLE   := 15.0
const F_HEADER  := 12.0
const F_LABEL   := 13.0
const F_VALUE   := 14.0
const F_UNIT    := 12.0
const F_TIME    := 15.0
const F_BUTTON  := 13.0
const F_SMALL   := 12.0

const C_BG      := Color(0.055, 0.062, 0.078)
const C_PANEL   := Color(0.078, 0.086, 0.105)
const C_BORDER  := Color(0.16, 0.18, 0.22)
const C_TEXT    := Color(0.86, 0.89, 0.93)
const C_DIM     := Color(0.56, 0.60, 0.66)
const C_ACCENT  := Color(0.40, 0.78, 0.98)

const TOPBAR_H     := 46.0
const LEFT_W       := 380.0
const RIGHT_W      := 400.0
const BOTTOM_H     := 340.0
const SPARKLINE_H  := 56.0
const ROW_MIN_H    := 20.0
const KPI_H        := 400.0
const POLICY_H     := 400.0

func setup(sim_ref: CitySim, main_ref: Node, is_mobile: bool = false) -> void:
	sim = sim_ref
	main = main_ref
	mobile = is_mobile
	_refresh_interval = 1.0 / (REFRESH_HZ_MOBILE if mobile else REFRESH_HZ_DESKTOP)
	layer = 10
	_build()

func tick(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum < _refresh_interval:
		return
	_refresh_accum = 0.0
	_refresh()

func _px(v: float) -> float:
	return v * UI_SCALE

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_topbar(root)
	_build_left(root)
	_build_right(root)
	_build_bottom(root)
	_build_policy_panel(root)

func _panel_anchored(parent: Control, anchor: int, offset: Vector2, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(anchor)
	p.offset_left   = offset.x * UI_SCALE
	p.offset_top    = offset.y * UI_SCALE
	p.offset_right  = (offset.x + size.x) * UI_SCALE
	p.offset_bottom = (offset.y + size.y) * UI_SCALE
	p.add_theme_stylebox_override("panel", _style(C_PANEL, C_BORDER))
	parent.add_child(p)
	return p

func _style(bg: Color, border: Color, radius := 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(_px(1.0)))
	sb.set_corner_radius_all(int(_px(radius)))
	sb.content_margin_left   = int(_px(14.0))
	sb.content_margin_right  = int(_px(14.0))
	sb.content_margin_top    = int(_px(12.0))
	sb.content_margin_bottom = int(_px(12.0))
	return sb

# ── TOP BAR ──────────────────────────────────────────────────
func _build_topbar(root: Control) -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, _px(TOPBAR_H))
	bar.add_theme_stylebox_override("panel", _style(C_BG, C_BORDER, 0))
	root.add_child(bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   int(_px(20.0)))
	margin.add_theme_constant_override("margin_right",  int(_px(20.0)))
	margin.add_theme_constant_override("margin_top",    int(_px(6.0)))
	margin.add_theme_constant_override("margin_bottom", int(_px(6.0)))
	bar.add_child(margin)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(_px(20.0)))
	margin.add_child(h)

	var title := Label.new()
	title.text = "SMART CITY SIMULATION"
	title.add_theme_font_size_override("font_size", int(_px(F_TITLE)))
	title.add_theme_color_override("font_color", C_ACCENT)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(title)

	h.add_child(_vsep())

	_time_lbl = Label.new()
	_time_lbl.add_theme_font_size_override("font_size", int(_px(F_TIME)))
	_time_lbl.add_theme_color_override("font_color", C_TEXT)
	_time_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_time_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	# ── DAY / NIGHT toggle ──
	_night_btn = Button.new()
	_night_btn.text = "🌙 NIGHT"
	_night_btn.toggle_mode = true
	_night_btn.add_theme_font_size_override("font_size", int(_px(F_BUTTON)))
	_night_btn.custom_minimum_size = Vector2(_px(110.0), 0)
	_night_btn.toggled.connect(_on_night_toggled)
	h.add_child(_night_btn)

	h.add_child(_vsep())

	# ── WEALTH toggle ──
	_wealth_btn = Button.new()
	_wealth_btn.text = "💰 WEALTH"
	_wealth_btn.toggle_mode = true
	_wealth_btn.add_theme_font_size_override("font_size", int(_px(F_BUTTON)))
	_wealth_btn.custom_minimum_size = Vector2(_px(110.0), 0)
	_wealth_btn.toggled.connect(_on_wealth_toggled)
	h.add_child(_wealth_btn)

	# ── OVERLAY dropdown ──
	var ov_lbl := Label.new()
	ov_lbl.text = "OVERLAY"
	ov_lbl.add_theme_font_size_override("font_size", int(_px(F_LABEL)))
	ov_lbl.add_theme_color_override("font_color", C_DIM)
	ov_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(ov_lbl)

	_overlay_btn = OptionButton.new()
	_overlay_btn.add_theme_font_size_override("font_size", int(_px(F_BUTTON)))
	for n in CityBuilder.OVERLAY_NAMES:
		_overlay_btn.add_item(n)
	_overlay_btn.selected = 0
	_overlay_btn.item_selected.connect(func(i): _on_overlay_picked(i))
	h.add_child(_overlay_btn)

	h.add_child(_vsep())

	for i in _speed_names.size():
		var b := Button.new()
		b.text = _speed_names[i]
		b.add_theme_font_size_override("font_size", int(_px(F_BUTTON)))
		b.custom_minimum_size = Vector2(_px(64.0), 0)
		b.pressed.connect(func(): _set_speed(i))
		h.add_child(b)

	_speed_lbl = Label.new()
	_speed_lbl.add_theme_font_size_override("font_size", int(_px(F_LABEL)))
	_speed_lbl.add_theme_color_override("font_color", C_DIM)
	_speed_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_speed_lbl)

func _vsep() -> Control:
	var c := ColorRect.new()
	c.color = C_BORDER
	c.custom_minimum_size = Vector2(max(1, int(_px(1.0))), int(_px(26.0)))
	return c

func _set_speed(i: int) -> void:
	_speed_index = i
	_speed_lbl.text = "  " + _speed_names[i]

func speed_hours_per_second() -> float:
	return _speeds[_speed_index]

func _on_night_toggled(pressed: bool) -> void:
	_is_night = pressed
	_night_btn.text = "☀️ DAY" if pressed else "🌙 NIGHT"
	main.set_force_night(pressed)

func _on_wealth_toggled(pressed: bool) -> void:
	_wealth_on = pressed
	if pressed:
		_overlay_before_wealth = _overlay_btn.selected
		main.set_overlay(CityBuilder.Overlay.WEALTH)
		_overlay_btn.selected = CityBuilder.Overlay.WEALTH
	else:
		main.set_overlay(_overlay_before_wealth)
		_overlay_btn.selected = _overlay_before_wealth

func _on_overlay_picked(index: int) -> void:
	if _wealth_on:
		_wealth_on = false
		_wealth_btn.set_pressed_no_signal(false)
	main.set_overlay(index)

# ── LEFT: KPI PANEL ──────────────────────────────────────────
func _build_left(root: Control) -> void:
	var top := TOPBAR_H + 12.0
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.position = Vector2(12 * UI_SCALE, top * UI_SCALE)
	p.size = Vector2(LEFT_W * UI_SCALE, KPI_H * UI_SCALE)
	p.add_theme_stylebox_override("panel", _style(C_PANEL, C_BORDER))
	root.add_child(p)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)

	_kpi_box = VBoxContainer.new()
	_kpi_box.add_theme_constant_override("separation", int(_px(2.0)))
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
	c.add_theme_constant_override("margin_top",    int(_px(10.0)))
	c.add_theme_constant_override("margin_bottom", int(_px(3.0)))
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", int(_px(F_HEADER)))
	l.add_theme_color_override("font_color", C_ACCENT)
	c.add_child(l)
	return c

func _metric_row(key: String) -> Control:
	var d: Array = CitySim.METRICS[key]
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, _px(ROW_MIN_H))

	var name_l := Label.new()
	name_l.text = d[1]
	name_l.add_theme_font_size_override("font_size", int(_px(F_LABEL)))
	name_l.add_theme_color_override("font_color", C_DIM)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_l)

	var val_l := Label.new()
	val_l.add_theme_font_size_override("font_size", int(_px(F_VALUE)))
	val_l.add_theme_color_override("font_color", C_TEXT)
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val_l.custom_minimum_size = Vector2(_px(150.0), 0)
	row.add_child(val_l)

	_kpi_labels[key] = val_l
	return row

# ── RIGHT: TRENDS ────────────────────────────────────────────
func _build_right(root: Control) -> void:
	var top := TOPBAR_H + 12.0
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	p.offset_left   = (-RIGHT_W - 12) * UI_SCALE
	p.offset_top    = top * UI_SCALE
	p.offset_right  = -12 * UI_SCALE
	p.offset_bottom = -12 * UI_SCALE
	p.add_theme_stylebox_override("panel", _style(C_PANEL, C_BORDER))
	root.add_child(p)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", int(_px(8.0)))
	p.add_child(outer)

	var hdr := Label.new()
	hdr.text = "TRENDS"
	hdr.add_theme_font_size_override("font_size", int(_px(F_HEADER)))
	hdr.add_theme_color_override("font_color", C_ACCENT)
	outer.add_child(hdr)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(_px(12.0)))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	for c in CHART_DEFS:
		v.add_child(_chart_block(c[0], c[1], c[2]))

func _chart_block(key: String, label: String, col: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(_px(2.0)))

	var head := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", int(_px(F_LABEL)))
	l.add_theme_color_override("font_color", C_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)

	var v := Label.new()
	v.add_theme_font_size_override("font_size", int(_px(F_VALUE)))
	v.add_theme_color_override("font_color", C_TEXT)
	head.add_child(v)
	_charts[key + "_val"] = v

	box.add_child(head)

	var sp := Sparkline.new()
	sp.line_color = col
	sp.fill_color = Color(col.r, col.g, col.b, 0.13)
	sp.custom_minimum_size = Vector2(0, _px(SPARKLINE_H))
	box.add_child(sp)
	_charts[key] = sp
	return box

# ── BOTTOM: REPORT TABS ──────────────────────────────────────
func _build_bottom(root: Control) -> void:
	var p := _panel_anchored(root, Control.PRESET_BOTTOM_WIDE,
		Vector2(0, 0), Vector2(0, BOTTOM_H))
	p.offset_left   = (LEFT_W + 24) * UI_SCALE
	p.offset_right  = (-RIGHT_W - 24) * UI_SCALE
	p.offset_top    = -BOTTOM_H * UI_SCALE - 12 * UI_SCALE
	p.offset_bottom = -12 * UI_SCALE

	var tabs := TabContainer.new()
	tabs.add_theme_font_size_override("font_size", int(_px(F_BUTTON)))
	p.add_child(tabs)

	for group in ["Society", "Economy", "Infrastructure", "Environment", "Smart Systems"]:
		var scroll := ScrollContainer.new()
		scroll.name = group
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)

		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", int(_px(36.0)))
		grid.add_theme_constant_override("v_separation", int(_px(6.0)))
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(grid)

		var table := {}
		for k in CitySim.METRICS:
			if CitySim.METRICS[k][0] != group: continue
			var nl := Label.new()
			nl.text = CitySim.METRICS[k][1]
			nl.add_theme_font_size_override("font_size", int(_px(F_LABEL)))
			nl.add_theme_color_override("font_color", C_DIM)
			grid.add_child(nl)

			var vl := Label.new()
			vl.add_theme_font_size_override("font_size", int(_px(F_VALUE)))
			vl.add_theme_color_override("font_color", C_TEXT)
			vl.custom_minimum_size = Vector2(_px(140.0), 0)
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(vl)
			table[k] = vl

			var ul := Label.new()
			ul.text = CitySim.METRICS[k][2]
			ul.add_theme_font_size_override("font_size", int(_px(F_UNIT)))
			ul.add_theme_color_override("font_color", Color(0.40, 0.44, 0.50))
			grid.add_child(ul)

		_tables[group] = table
		_last_tab_text[group] = {}

# ── POLICY PANEL ─────────────────────────────────────────────
func _build_policy_panel(root: Control) -> void:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var panel_y: float = (TOPBAR_H + 12.0 + KPI_H + 12.0) * UI_SCALE
	p.position = Vector2(12 * UI_SCALE, panel_y)
	p.size = Vector2(LEFT_W * UI_SCALE, POLICY_H * UI_SCALE)
	p.add_theme_stylebox_override("panel", _style(C_PANEL, C_BORDER))
	root.add_child(p)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", int(_px(4.0)))
	p.add_child(outer)

	var hdr_row := HBoxContainer.new()
	var hdr := Label.new()
	hdr.text = "POLICY LEVERS"
	hdr.add_theme_font_size_override("font_size", int(_px(F_HEADER)))
	hdr.add_theme_color_override("font_color", C_ACCENT)
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_row.add_child(hdr)

	var reset_btn := Button.new()
	reset_btn.text = "RESET"
	reset_btn.add_theme_font_size_override("font_size", int(_px(F_SMALL)))
	reset_btn.pressed.connect(_on_reset_policies)
	hdr_row.add_child(reset_btn)
	outer.add_child(hdr_row)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", int(_px(6.0)))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for row_def in POLICY_ROWS:
		var key: String = row_def[0]
		var label: String = row_def[1]
		list.add_child(_policy_row(key, label))

func _policy_row(key: String, label: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)

	var top_row := HBoxContainer.new()
	var name_l := Label.new()
	name_l.text = label
	name_l.add_theme_font_size_override("font_size", int(_px(F_LABEL)))
	name_l.add_theme_color_override("font_color", C_DIM)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(name_l)

	var val_l := Label.new()
	val_l.add_theme_font_size_override("font_size", int(_px(F_VALUE)))
	val_l.add_theme_color_override("font_color", C_TEXT)
	val_l.custom_minimum_size = Vector2(_px(70.0), 0)
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_l.text = "%.0f%%" % (sim.s.get(key, 0.5) * 100.0)
	top_row.add_child(val_l)
	_slider_labels[key] = val_l

	box.add_child(top_row)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = sim.s.get(key, 0.5)
	slider.custom_minimum_size = Vector2(0, _px(18.0))
	slider.value_changed.connect(func(v: float): _on_slider_changed(key, v))
	box.add_child(slider)
	_sliders[key] = slider

	return box

func _on_slider_changed(key: String, value: float) -> void:
	sim.s[key] = value
	var lbl: Label = _slider_labels.get(key)
	if lbl:
		lbl.text = "%.0f%%" % (value * 100.0)
	_refresh_accum = _refresh_interval

func _on_reset_policies() -> void:
	for row_def in POLICY_ROWS:
		var key: String = row_def[0]
		sim.s[key] = 0.5
		var lbl: Label = _slider_labels.get(key)
		if lbl:
			lbl.text = "50%"
		var sl: HSlider = _sliders.get(key)
		if sl:
			sl.set_value_no_signal(0.5)
	_refresh_accum = _refresh_interval

# ─────────────────────────────────────────────────────────────
#  REFRESH
# ─────────────────────────────────────────────────────────────
func _refresh() -> void:
	_time_lbl.text = sim.date_string()

	for k in _kpi_labels:
		var v := _fmt(k)
		if _last_kpi_text.get(k, "") != v:
			_kpi_labels[k].text = v
			_last_kpi_text[k] = v

	for group in _tables:
		var gd: Dictionary = _last_tab_text[group]
		for k in _tables[group]:
			var v := _fmt(k)
			if gd.get(k, "") != v:
				_tables[group][k].text = v
				gd[k] = v

	var cur_day: int = sim.tick / CitySim.HOURS_PER_DAY
	var refetch := cur_day != _last_series_day
	for key in _charts:
		if key.ends_with("_val"):
			continue
		var sp: Sparkline = _charts[key]
		if refetch:
			var arr := sim.metrics.series(key)
			_cached_series[key] = arr
			sp.set_values(arr)
		var vl: Label = _charts.get(key + "_val")
		if vl:
			vl.text = _fmt(key)

	if refetch:
		_last_series_day = cur_day

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
