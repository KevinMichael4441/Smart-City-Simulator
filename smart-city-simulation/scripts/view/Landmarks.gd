class_name Landmarks
extends RefCounted

# ─────────────────────────────────────────────────────────────
#  PRIMITIVES
# ─────────────────────────────────────────────────────────────
static func add_box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color) -> void:
	var h: Vector3 = size * 0.5
	var v: Array = [
		center + Vector3(-h.x, -h.y, -h.z),
		center + Vector3( h.x, -h.y, -h.z),
		center + Vector3( h.x,  h.y, -h.z),
		center + Vector3(-h.x,  h.y, -h.z),
		center + Vector3(-h.x, -h.y,  h.z),
		center + Vector3( h.x, -h.y,  h.z),
		center + Vector3( h.x,  h.y,  h.z),
		center + Vector3(-h.x,  h.y,  h.z),
	]
	var quads: Array = [
		[0, 1, 2, 3, Vector3(0, 0, -1)],
		[4, 5, 6, 7, Vector3(0, 0,  1)],
		[1, 5, 6, 2, Vector3(1, 0, 0)],
		[0, 4, 7, 3, Vector3(-1, 0, 0)],
		[3, 2, 6, 7, Vector3(0, 1, 0)],
		[0, 1, 5, 4, Vector3(0, -1, 0)],
	]
	for q in quads:
		var n: Vector3 = q[4]
		var a: Vector3 = v[q[0]]
		var b: Vector3 = v[q[1]]
		var c: Vector3 = v[q[2]]
		var d: Vector3 = v[q[3]]
		st.set_normal(n); st.set_color(col); st.add_vertex(a)
		st.set_normal(n); st.set_color(col); st.add_vertex(b)
		st.set_normal(n); st.set_color(col); st.add_vertex(c)
		st.set_normal(n); st.set_color(col); st.add_vertex(a)
		st.set_normal(n); st.set_color(col); st.add_vertex(c)
		st.set_normal(n); st.set_color(col); st.add_vertex(d)

static func add_pyramid(st: SurfaceTool, center: Vector3, base: Vector2, height: float, col: Color) -> void:
	var hx: float = base.x * 0.5
	var hz: float = base.y * 0.5
	var apex: Vector3 = center + Vector3(0, height * 0.5, 0)
	var corners: Array = [
		center + Vector3(-hx, -height * 0.5, -hz),
		center + Vector3( hx, -height * 0.5, -hz),
		center + Vector3( hx, -height * 0.5,  hz),
		center + Vector3(-hx, -height * 0.5,  hz),
	]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var n: Vector3 = (b - a).cross(apex - a).normalized()
		st.set_normal(n); st.set_color(col); st.add_vertex(a)
		st.set_normal(n); st.set_color(col); st.add_vertex(b)
		st.set_normal(n); st.set_color(col); st.add_vertex(apex)

# ─────────────────────────────────────────────────────────────
#  CLOCK TOWER  —  ~115 units tall (≈ 6 cells)
# ─────────────────────────────────────────────────────────────
static func make_clock_tower() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var stone_light := Color(0.86, 0.83, 0.78)
	var stone_mid   := Color(0.72, 0.69, 0.64)
	var stone_dark  := Color(0.52, 0.49, 0.45)
	var housing     := Color(0.20, 0.18, 0.16)
	var face        := Color(0.98, 0.96, 0.90)
	var roof        := Color(0.34, 0.38, 0.44)
	var gold        := Color(0.94, 0.78, 0.32)

	# ── plaza base (three stepped tiers) ──
	add_box(st, Vector3(0, 1.5, 0), Vector3(22, 3, 22), stone_dark)
	add_box(st, Vector3(0, 4.5, 0), Vector3(18, 3, 18), stone_mid)
	add_box(st, Vector3(0, 7.5, 0), Vector3(14, 3, 14), stone_light)

	# ── main shaft (tall and narrow, 60 units) ──
	add_box(st, Vector3(0, 39, 0), Vector3(10, 60, 10), stone_light)

	# ── corner pilasters (vertical ribs) ──
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			add_box(st, Vector3(sx * 4.6, 39, sz * 4.6), Vector3(2, 60, 2), stone_dark)

	# ── mid-height cornice ──
	add_box(st, Vector3(0, 30, 0), Vector3(11.5, 1.2, 11.5), stone_dark)
	add_box(st, Vector3(0, 50, 0), Vector3(11.5, 1.2, 11.5), stone_dark)

	# ── clock housing (wider than shaft) ──
	add_box(st, Vector3(0, 72, 0), Vector3(13, 8, 13), housing)

	# ── clock faces on four sides ──
	for dir in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		var c: Vector3 = Vector3(0, 72, 0) + dir * 6.55
		var face_size: Vector3 = Vector3(6.5, 6.5, 0.3) if absf(dir.z) > 0.5 else Vector3(0.3, 6.5, 6.5)
		add_box(st, c, face_size, face)
		# hour hand (short, thick)
		var hand_c: Vector3 = c + dir * 0.2
		var hh_size: Vector3 = Vector3(2.6, 0.5, 0.4) if absf(dir.z) > 0.5 else Vector3(0.4, 0.5, 2.6)
		add_box(st, hand_c, hh_size, housing)
		# minute hand (long, thin)
		var mh_size: Vector3 = Vector3(0.35, 2.4, 0.4) if absf(dir.z) > 0.5 else Vector3(0.4, 2.4, 0.35)
		add_box(st, hand_c, mh_size, housing)
		# 12 o'clock marker dot
		var dot: Vector3 = c + dir * 0.2 + Vector3(0, 2.6, 0) if absf(dir.z) > 0.5 else c + dir * 0.2 + Vector3(2.6, 0, 0)
		# (skip for simplicity; clock face alone reads fine)

	# ── belfry (open arcade) ──
	add_box(st, Vector3(0, 79, 0), Vector3(12, 6, 12), stone_light)
	for dir in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		var c: Vector3 = Vector3(0, 79, 0) + dir * 6.05
		var op: Vector3 = Vector3(3.5, 4, 0.3) if absf(dir.z) > 0.5 else Vector3(0.3, 4, 3.5)
		add_box(st, c, op, housing)

	# ── cornice over belfry ──
	add_box(st, Vector3(0, 83, 0), Vector3(13.5, 1.5, 13.5), stone_dark)

	# ── upper roof block ──
	add_box(st, Vector3(0, 85, 0), Vector3(11, 3, 11), roof)

	# ── main spire (pyramid, 26 units tall) ──
	add_pyramid(st, Vector3(0, 100, 0), Vector2(10, 10), 26, roof)

	# ── gold finial ──
	add_box(st, Vector3(0, 114, 0), Vector3(1.8, 1.8, 1.8), gold)
	add_box(st, Vector3(0, 117, 0), Vector3(0.4, 4, 0.4), gold)

	st.generate_normals()
	return st.commit()

# ─────────────────────────────────────────────────────────────
#  CATHEDRAL  —  ~70 units tall, wide footprint
# ─────────────────────────────────────────────────────────────
static func make_cathedral() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var stone_light := Color(0.88, 0.85, 0.79)
	var stone_mid   := Color(0.72, 0.68, 0.62)
	var stone_dark  := Color(0.50, 0.47, 0.43)
	var roof        := Color(0.30, 0.38, 0.48)
	var window      := Color(0.48, 0.66, 0.86)
	var gold        := Color(0.90, 0.76, 0.32)

	# ── podium (two tiers, top tier reaches nave base at Y=4) ──
	add_box(st, Vector3(0, 1, 0), Vector3(26, 2, 32), stone_dark)      # Y 0-2
	add_box(st, Vector3(0, 3, 0), Vector3(24, 2, 30), stone_mid)       # Y 2-4

	# ── nave (long body) ──
	add_box(st, Vector3(0, 14, 0), Vector3(12, 20, 26), stone_light)   # Y 4-24

	# ── transept ──
	add_box(st, Vector3(0, 14, 0), Vector3(22, 20, 8), stone_light)    # Y 4-24

	# ── window strips ──
	for i in range(-5, 6):
		var z_pos: float = i * 2.2
		add_box(st, Vector3(6.05, 14, z_pos), Vector3(0.15, 12, 0.9), window)
		add_box(st, Vector3(-6.05, 14, z_pos), Vector3(0.15, 12, 0.9), window)
	for i in range(-4, 5):
		var x_pos: float = i * 2.2
		add_box(st, Vector3(x_pos, 14, 4.05), Vector3(0.9, 12, 0.15), window)
		add_box(st, Vector3(x_pos, 14, -4.05), Vector3(0.9, 12, 0.15), window)

	# ── roofs (bases at Y=24, exactly nave top) ──
	add_pyramid(st, Vector3(0, 26, 0), Vector2(13, 27), 4, roof)       # Y 24-28
	add_pyramid(st, Vector3(0, 26, 0), Vector2(23, 9), 4, roof)        # Y 24-28

	# ── crossing tower ──
	add_box(st, Vector3(0, 30, 0), Vector3(10, 8, 10), stone_mid)      # Y 26-34

	# ── dome (base at Y=33.5, overlaps tower top) ──
	add_pyramid(st, Vector3(0, 38, 0), Vector2(11, 11), 9, roof)       # Y 33.5-42.5

	# ── lantern (base at Y=42, overlaps apex) ──
	add_box(st, Vector3(0, 44, 0), Vector3(3, 4, 3), stone_light)      # Y 42-46
	add_pyramid(st, Vector3(0, 48, 0), Vector2(3.5, 3.5), 4, roof)     # Y 46-50
	add_box(st, Vector3(0, 51, 0), Vector3(0.4, 3, 0.4), gold)         # Y 49.5-52.5

	# ── twin west front towers ──
	for sx in [-1, 1]:
		var tx: float = sx * 8.5
		# tower body (base at Y=3, seated on podium)
		add_box(st, Vector3(tx, 18, -11), Vector3(6, 30, 6), stone_light)   # Y 3-33
		# corner pilasters
		for px in [-1, 1]:
			for pz in [-1, 1]:
				add_box(st, Vector3(tx + px * 2.6, 18, -11 + pz * 2.6),
					Vector3(0.9, 30, 0.9), stone_dark)
		# belfry openings
		add_box(st, Vector3(tx, 30, -8.05), Vector3(2.6, 5, 0.2), stone_dark)
		add_box(st, Vector3(tx, 30, -13.95), Vector3(2.6, 5, 0.2), stone_dark)
		# spires (base at Y=31, overlapping tower top)
		add_pyramid(st, Vector3(tx, 41, -11), Vector2(6.5, 6.5), 20, roof)  # Y 31-51
		add_box(st, Vector3(tx, 51.5, -11), Vector3(0.4, 3, 0.4), gold)      # Y 50-53

	st.generate_normals()
	return st.commit()

# ─────────────────────────────────────────────────────────────
#  RADIO MAST  —  ~140 units tall
# ─────────────────────────────────────────────────────────────
static func make_radio_mast() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var metal      := Color(0.68, 0.70, 0.74)
	var metal_dark := Color(0.42, 0.44, 0.48)
	var concrete   := Color(0.64, 0.62, 0.58)
	var light_red  := Color(0.96, 0.30, 0.28)

	# ── concrete base (wide) ──
	add_box(st, Vector3(0, 2.5, 0), Vector3(14, 5, 14), concrete)       # Y 0-5
	add_box(st, Vector3(0, 5.5, 0), Vector3(10, 1, 10), metal_dark)     # Y 5-6

	# ── tower body — tapering solid column ──
	add_box(st, Vector3(0, 14, 0), Vector3(8, 16, 8), metal)            # Y 6-22
	add_box(st, Vector3(0, 26, 0), Vector3(6.5, 8, 6.5), metal)         # Y 22-30
	add_box(st, Vector3(0, 34, 0), Vector3(5, 8, 5), metal)             # Y 30-38

	# ── horizontal bracing rings ──
	add_box(st, Vector3(0, 11, 0), Vector3(9, 0.6, 9), metal_dark)
	add_box(st, Vector3(0, 20, 0), Vector3(7.5, 0.6, 7.5), metal_dark)
	add_box(st, Vector3(0, 28, 0), Vector3(6, 0.6, 6), metal_dark)
	add_box(st, Vector3(0, 35, 0), Vector3(4.5, 0.6, 4.5), metal_dark)

	# ── antenna cluster at top (cross-array) ──
	add_box(st, Vector3(0, 40, 0), Vector3(3.5, 3, 3.5), metal_dark)    # Y 38.5-41.5
	# central mast
	add_box(st, Vector3(0, 45, 0), Vector3(0.8, 7, 0.8), metal)         # Y 41.5-48.5
	# four side antennas
	add_box(st, Vector3( 2.0, 42.5, 0), Vector3(0.5, 5, 0.5), metal)
	add_box(st, Vector3(-2.0, 42.5, 0), Vector3(0.5, 5, 0.5), metal)
	add_box(st, Vector3(0, 42.5,  2.0), Vector3(0.5, 5, 0.5), metal)
	add_box(st, Vector3(0, 42.5, -2.0), Vector3(0.5, 5, 0.5), metal)

	# ── red warning lights ──
	add_box(st, Vector3(0, 37, 0), Vector3(1.4, 1.4, 1.4), light_red)
	add_box(st, Vector3(0, 48.5, 0), Vector3(1.1, 1.1, 1.1), light_red)

	st.generate_normals()
	return st.commit()

# ─────────────────────────────────────────────────────────────
#  OBELISK  —  ~55 units
# ─────────────────────────────────────────────────────────────
static func make_obelisk() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var stone_light := Color(0.90, 0.86, 0.78)
	var stone_mid   := Color(0.72, 0.68, 0.60)
	var stone_dark  := Color(0.50, 0.46, 0.40)
	var gold        := Color(0.94, 0.78, 0.32)

	# ── plaza base ──
	add_box(st, Vector3(0, 1, 0), Vector3(18, 2, 18), stone_dark)       # Y 0-2
	add_box(st, Vector3(0, 2.75, 0), Vector3(14, 1.5, 14), stone_mid)   # Y 2-3.5

	# ── pedestal ──
	add_box(st, Vector3(0, 6.25, 0), Vector3(9, 6.5, 9), stone_light)   # Y 3-9.5
	add_box(st, Vector3(0, 9.75, 0), Vector3(10, 1, 10), stone_dark)    # Y 9.25-10.25

	# ── tapered shaft — three segments, each overlapping the one below ──
	add_box(st, Vector3(0, 15, 0), Vector3(5, 11, 5), stone_light)      # Y 9.5-20.5
	add_box(st, Vector3(0, 24, 0), Vector3(4.2, 10, 4.2), stone_light)  # Y 19-29
	add_box(st, Vector3(0, 32, 0), Vector3(3.4, 8, 3.4), stone_light)   # Y 28-36

	# ── pyramidion — base at Y=34, apex at Y=44 (2-unit overlap into shaft) ──
	# center Y = 34 + 5 = 39, height 10
	add_pyramid(st, Vector3(0, 39, 0), Vector2(5, 5), 10, stone_light)

	# ── gold cap — base at Y=42, apex at Y=46 (2-unit overlap into pyramidion apex) ──
	# center Y = 42 + 2 = 44, height 4
	add_pyramid(st, Vector3(0, 44, 0), Vector2(1.8, 1.8), 4, gold)

	st.generate_normals()
	return st.commit()

# ─────────────────────────────────────────────────────────────
#  SPIRE TOWER  —  ~130 units tall (glass highrise)
# ─────────────────────────────────────────────────────────────
static func make_spire_tower() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var glass_light := Color(0.46, 0.56, 0.70)
	var glass_mid   := Color(0.30, 0.40, 0.56)
	var glass_dark  := Color(0.20, 0.28, 0.42)
	var metal       := Color(0.40, 0.42, 0.46)
	var spire_col   := Color(0.52, 0.56, 0.62)
	var gold        := Color(0.94, 0.78, 0.30)

	# ── podium + tower body (unchanged — these work) ──
	add_box(st, Vector3(0, 5, 0), Vector3(20, 10, 20), glass_dark)
	add_box(st, Vector3(0, 10.25, 0), Vector3(21, 1.5, 21), metal)
	add_box(st, Vector3(0, 30, 0), Vector3(16, 40, 16), glass_mid)
	add_box(st, Vector3(0, 64, 0), Vector3(13, 32, 13), glass_light)
	add_box(st, Vector3(0, 88, 0), Vector3(10, 20, 10), glass_mid)
	add_box(st, Vector3(0, 100.5, 0), Vector3(9, 9, 9), metal)
	add_box(st, Vector3(0, 105, 0), Vector3(10.5, 2, 10.5), metal)

	# ── THREE STACKED PYRAMIDS with huge overlaps ──
	# Big pyramid: base 11 wide at Y=104, apex at Y=116 (center Y=110, height 12)
	add_pyramid(st, Vector3(0, 110, 0), Vector2(11, 11), 12, spire_col)

	# Mid pyramid: base 7 wide at Y=110, apex at Y=120 (center Y=115, height 10)
	# Big pyramid apex (Y=116) is buried 4 units INSIDE this pyramid.
	add_pyramid(st, Vector3(0, 115, 0), Vector2(7, 7), 10, spire_col)

	# Gold cap: base 3 wide at Y=115, apex at Y=123 (center Y=119, height 8)
	# Mid pyramid apex (Y=120) is buried 3 units INSIDE this pyramid.
	add_pyramid(st, Vector3(0, 119, 0), Vector2(3, 3), 8, gold)

	st.generate_normals()
	return st.commit()
