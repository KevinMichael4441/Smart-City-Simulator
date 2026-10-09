class_name Sparkline
extends Control

var values := PackedFloat32Array()
var line_color := Color(0.38, 0.76, 0.96)
var fill_color := Color(0.38, 0.76, 0.96, 0.14)
var baseline_color := Color(1, 1, 1, 0.06)

func set_values(v: PackedFloat32Array) -> void:
	values = v
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_line(Vector2(0, h - 1.0), Vector2(w, h - 1.0), baseline_color, 2.0)

	if values.size() < 2:
		return

	var mn := values[0]
	var mx := values[0]
	for v in values:
		mn = minf(mn, v); mx = maxf(mx, v)
	if mx - mn < 0.0001:
		mx = mn + 1.0

	var n := values.size()
	var pts := PackedVector2Array()
	pts.resize(n)
	for i in n:
		var x: float = w * float(i) / float(n - 1)
		var y: float = h - ((values[i] - mn) / (mx - mn)) * (h - 3.0) - 1.5
		pts[i] = Vector2(x, y)

	if pts.size() >= 2:
		var poly := PackedVector2Array()
		poly.append(Vector2(0, h))
		for p in pts: poly.append(p)
		poly.append(Vector2(w, h))
		draw_colored_polygon(poly, fill_color)
		draw_polyline(pts, line_color, 2.6, true)
