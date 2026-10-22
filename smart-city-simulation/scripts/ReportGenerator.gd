class_name ReportGenerator
extends RefCounted

static func export(sim: CitySim) -> void:
	var html := "<!DOCTYPE html><html><head><meta charset='utf-8'>"
	html += "<title>City Report - " + sim.date_string() + "</title>"
	html += "<style>"
	html += "body { background: #0d1117; color: #c9d1d9; font-family: 'Courier New', monospace; padding: 2rem; max-width: 1600px; margin: auto; line-height: 1.5; }"
	html += "h1 { color: #58a6ff; border-bottom: 2px solid #30363d; padding-bottom: 0.5rem; font-size: 1.5rem; }"
	html += "h2 { color: #58a6ff; border-bottom: 1px solid #30363d; padding-bottom: 0.3rem; font-size: 1.1rem; margin-top: 2rem; }"
	html += ".grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(380px, 1fr)); gap: 1rem; }"
	html += ".card { background: #161b22; border: 1px solid #30363d; padding: 0.8rem; border-radius: 6px; }"
	html += ".val { font-size: 1.3rem; font-weight: bold; color: #fff; margin: 0.2rem 0; }"
	html += ".label { font-size: 0.8rem; color: #8b949e; text-transform: uppercase; letter-spacing: 0.05em; }"
	html += ".range { font-size: 0.7rem; color: #6e7681; margin-bottom: 0.5rem; }"
	html += ".spark { display: flex; justify-content: center; margin-top: 0.5rem; }"
	html += "</style></head><body>"

	html += "<h1>CITY REPORT: " + sim.date_string() + "</h1>"
	html += "<p style='color:#8b949e'>Generated from simulation tick " + str(sim.tick) + " | Founded " + str(sim.founded_year) + "</p>"

	var groups := {}
	for k in CitySim.METRICS:
		var g: String = CitySim.METRICS[k][0]
		if not groups.has(g): groups[g] = []
		groups[g].append(k)

	for group_name in groups:
		html += "<h2>" + group_name + "</h2><div class='grid'>"
		for key in groups[group_name]:
			var d: Array = CitySim.METRICS[key]
			var label: String = d[1]
			var unit: String = d[2]
			var mult: float = d[3]
			var is_int: bool = d[4]

			var raw: float = sim.s.get(key, 0.0) * mult
			var val_str := _fmt_num(raw, is_int)
			if unit != "": val_str += " " + unit

			var arr := sim.metrics.series(key)
			var range_str := ""
			var scaled := PackedFloat32Array()

			if arr.size() >= 2:
				for v in arr:
					scaled.append(v * mult)
				var rmn := scaled[0]; var rmx := scaled[0]
				for v in scaled:
					rmn = minf(rmn, v); rmx = maxf(rmx, v)
				range_str = "range: " + _fmt_tick(rmn, is_int) + " → " + _fmt_tick(rmx, is_int)

			html += "<div class='card'>"
			html += "<div class='label'>" + label + "</div>"
			html += "<div class='val'>" + val_str + "</div>"
			html += "<div class='range'>" + range_str + "</div>"

			if arr.size() >= 2:
				var svg := _make_svg(scaled, 340, 160, _color_for_group(group_name), is_int)
				html += "<div class='spark'>" + svg + "</div>"
			html += "</div>"
		html += "</div>"

	html += "</body></html>"

	var file := FileAccess.open("res://city_report.html", FileAccess.WRITE)
	if file:
		file.store_string(html)
		file.close()

static func _make_svg(arr: PackedFloat32Array, w: int, h: int, col: String, is_int: bool) -> String:
	if arr.size() < 2: return ""

	var mn := arr[0]; var mx := arr[0]
	for v in arr:
		mn = minf(mn, v); mx = maxf(mx, v)
	if mx - mn < 0.0001: mx = mn + 1.0

	# Padding: left for Y-axis values, bottom for X-axis time labels
	var pad_l := 45
	var pad_r := 10
	var pad_t := 10
	var pad_b := 22
	var cw := w - pad_l - pad_r
	var ch := h - pad_t - pad_b

	var svg := "<svg width='" + str(w) + "' height='" + str(h) + "' viewBox='0 0 " + str(w) + " " + str(h) + "' xmlns='http://www.w3.org/2000/svg' style='font-family: \"Courier New\", monospace;'>"

	# 1. Horizontal grid lines (Values)
	for i in 4:
		var t: float = float(i) / 3.0
		var y: float = pad_t + ch - t * ch
		var val: float = mn + (mx - mn) * t
		
		# Line
		svg += "<line x1='%d' y1='%.1f' x2='%d' y2='%.1f' stroke='#21262d' stroke-width='1' stroke-dasharray='2,3'/>" % [pad_l, y, pad_l + cw, y]
		
		# Tick and Label
		svg += "<line x1='%d' y1='%.1f' x2='%d' y2='%.1f' stroke='#30363d' stroke-width='1'/>" % [pad_l - 3, y, pad_l, y]
		svg += "<text x='%d' y='%.1f' fill='#8b949e' font-size='8' text-anchor='end' dominant-baseline='middle'>%s</text>" % [pad_l - 5, y, _fmt_tick(val, is_int)]

	# 2. Axes Lines
	svg += "<line x1='%d' y1='%d' x2='%d' y2='%d' stroke='#30363d' stroke-width='1'/>" % [pad_l, pad_t, pad_l, pad_t + ch]
	svg += "<line x1='%d' y1='%d' x2='%d' y2='%d' stroke='#30363d' stroke-width='1'/>" % [pad_l, pad_t + ch, pad_l + cw, pad_t + ch]

	# 3. X-axis time labels (Start, Mid, Now)
	var x_labels := ["start", "mid", "now"]
	for i in 3:
		var x: float = pad_l + (float(i) / 2.0) * cw
		svg += "<line x1='%.1f' y1='%d' x2='%.1f' y2='%d' stroke='#30363d' stroke-width='1'/>" % [x, pad_t + ch, x, pad_t + ch + 3]
		svg += "<text x='%.1f' y='%d' fill='#8b949e' font-size='8' text-anchor='middle'>%s</text>" % [x, pad_t + ch + 13, x_labels[i]]

	# 4. The Line (Time = X, Value = Y)
	var n := arr.size()
	var pts := PackedVector2Array()
	for i in n:
		var v: float = arr[i]
		var x: float = pad_l + (float(i) / float(n - 1)) * cw
		var y: float = pad_t + ch - ((v - mn) / (mx - mn)) * ch
		pts.append(Vector2(x, y))

	var pts_str := ""
	for p in pts:
		pts_str += "%.1f,%.1f " % [p.x, p.y]

	svg += "<polyline points='" + pts_str + "' fill='none' stroke='" + col + "' stroke-width='1.8' stroke-linejoin='round' stroke-linecap='round'/>"

	# 5. Highlight the "Now" point
	if pts.size() > 0:
		var last := pts[pts.size() - 1]
		svg += "<circle cx='%.1f' cy='%.1f' r='3' fill='" + col + "' stroke='#0d1117' stroke-width='1'/>" % [last.x, last.y]

	svg += "</svg>"
	return svg

static func _fmt_tick(v: float, is_int: bool) -> String:
	var av := absf(v)
	if av >= 1_000_000_000.0: return "%.1fB" % (v / 1_000_000_000.0)
	if av >= 1_000_000.0: return "%.1fM" % (v / 1_000_000.0)
	if av >= 1_000.0: return "%.1fk" % (v / 1_000.0)
	if is_int: return str(int(round(v)))
	if av >= 10.0: return "%.1f" % v
	return "%.2f" % v

static func _fmt_num(v: float, is_int: bool) -> String:
	if is_int: return _thousands(int(round(v)))
	var av := absf(v)
	if av >= 1_000.0: return _thousands(int(round(v)))
	if av >= 10.0: return "%.1f" % v
	return "%.2f" % v

static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0: out = "," + out
	return ("-" if n < 0 else "") + out

static func _color_for_group(g: String) -> String:
	match g:
		"Society": return "#3fb950"
		"Economy": return "#d29922"
		"Infrastructure": return "#58a6ff"
		"Environment": return "#a371f7"
		"Smart Systems": return "#f85149"
	return "#c9d1d9"
