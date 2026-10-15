class_name CityBuilder
extends Node3D

var sim: CitySim
var mobile: bool = false

# bulk building layers (only two now)
var _tiles_mm: MultiMeshInstance3D
var _bld_mm: MultiMeshInstance3D
var _cap_mm: MultiMeshInstance3D          # thin dark parapet on top of every building

var _tile_mesh: BoxMesh
var _bld_mesh: BoxMesh

var overlay: int = 0

enum Overlay { NATURAL, AIR, WATER, ENERGY, TRAFFIC, SAFETY, GREEN, POPULATION, LAND_VALUE }

const OVERLAY_NAMES: Array = ["Natural", "Air Quality", "Water Quality", "Energy Load",
	"Traffic", "Safety", "Green Space", "Density", "Land Value"]

var _sun: DirectionalLight3D
var _env: WorldEnvironment

var _bld_cells: PackedInt32Array = PackedInt32Array()
var _tile_xforms: Array[Transform3D] = []
var _bld_night: float = -999.0

# per-cell tint jitter so the skyline reads as varied architecture
var _bld_jitter: PackedFloat32Array = PackedFloat32Array()

# ── landmarks ──
var _landmark_root: Node3D
var _landmark_cells: Dictionary = {}

const LANDMARK_PLACEMENTS := [
	{"cell": [12, 10], "kind": "clock_tower"},   # west edge of downtown — towers over everything
	{"cell": [22, 16], "kind": "cathedral"},     # east of downtown
	{"cell": [15, 21], "kind": "obelisk"},       # south plaza
	{"cell": [33,  6], "kind": "radio_mast"},    # far NE
	{"cell": [23,  7], "kind": "spire_tower"},   # north side of downtown
]

var _stone_mat: ShaderMaterial

func setup(sim_ref: CitySim, is_mobile: bool = false) -> void:
	sim = sim_ref
	mobile = is_mobile
	_build_environment()
	_build_materials()
	_build_meshes()
	_build_bld_indices()
	_cache_tile_xforms()
	_build_bld_jitter()
	_build_landmarks()
	refresh_all()

func _build_materials() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform float night : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// COLOR holds the per-vertex colour baked into the mesh
	vec3 base = COLOR.rgb;
	// Darken at night and shift toward cool blue, matching the bulk buildings
	vec3 c = base * mix(1.0, 0.42, night);
	c *= mix(vec3(1.0), vec3(0.62, 0.70, 0.86), night);
	ALBEDO = c;
	ROUGHNESS = 0.82;
	SPECULAR = 0.30;
}
"""
	_stone_mat = ShaderMaterial.new()
	_stone_mat.shader = sh

func _build_environment() -> void:
	_env = WorldEnvironment.new()
	var e: Environment = Environment.new()

	if mobile:
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.15, 0.22, 0.38)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.45, 0.52, 0.65)
		e.ambient_light_energy = 0.65
		e.fog_enabled = false
	else:
		e.background_mode = Environment.BG_SKY
		var sky: Sky = Sky.new()
		var mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
		mat.sky_top_color = Color(0.15, 0.22, 0.38)
		mat.sky_horizon_color = Color(0.42, 0.48, 0.58)
		mat.ground_bottom_color = Color(0.06, 0.07, 0.09)
		mat.ground_horizon_color = Color(0.20, 0.22, 0.26)
		mat.sun_angle_max = 12.0
		sky.sky_material = mat
		e.sky = sky
		e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		e.ambient_light_sky_contribution = 0.9
		e.ambient_light_energy = 0.55
		e.fog_enabled = true
		e.fog_light_color = Color(0.42, 0.50, 0.62)
		e.fog_density = 0.0016

	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.environment = e
	add_child(_env)

	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.96, 0.88)
	_sun.shadow_enabled = not mobile
	var shadow_dist: float = 1400.0
	if mobile:
		shadow_dist = 600.0
	_sun.directional_shadow_max_distance = shadow_dist
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(_sun)

func _build_meshes() -> void:
	_tile_mesh = BoxMesh.new()
	_tile_mesh.size = Vector3(CitySim.CELL, 0.35, CitySim.CELL)

	var tmat: StandardMaterial3D = StandardMaterial3D.new()
	tmat.vertex_color_use_as_albedo = true
	tmat.roughness = 0.95
	tmat.specular = 0.08

	_tiles_mm = MultiMeshInstance3D.new()
	var tmm: MultiMesh = MultiMesh.new()
	tmm.transform_format = MultiMesh.TRANSFORM_3D
	tmm.use_colors = true
	tmm.mesh = _tile_mesh
	tmm.instance_count = CitySim.CELLS
	_tiles_mm.multimesh = tmm
	_tiles_mm.material_override = tmat
	add_child(_tiles_mm)

	_bld_mesh = BoxMesh.new()
	_bld_mesh.size = Vector3(1.0, 1.0, 1.0)

	var bmat: StandardMaterial3D = StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.roughness = 0.62
	bmat.metallic = 0.05
	bmat.specular = 0.35

	_bld_mm = MultiMeshInstance3D.new()
	var bmm: MultiMesh = MultiMesh.new()
	bmm.transform_format = MultiMesh.TRANSFORM_3D
	bmm.use_colors = true
	bmm.mesh = _bld_mesh
	bmm.instance_count = 0
	_bld_mm.multimesh = bmm
	_bld_mm.material_override = bmat
	add_child(_bld_mm)

	# cap layer — same unit box, scaled flat and wide at the top of each building
	_cap_mm = MultiMeshInstance3D.new()
	var cmm: MultiMesh = MultiMesh.new()
	cmm.transform_format = MultiMesh.TRANSFORM_3D
	cmm.use_colors = true
	cmm.mesh = _bld_mesh
	cmm.instance_count = 0
	_cap_mm.multimesh = cmm
	_cap_mm.material_override = bmat
	add_child(_cap_mm)

func _build_bld_indices() -> void:
	for entry in LANDMARK_PLACEMENTS:
		var c: Array = entry["cell"]
		_landmark_cells[c[1] * CitySim.N + c[0]] = true

	_bld_cells.clear()
	for i in CitySim.CELLS:
		if _landmark_cells.has(i): continue
		if sim.zone[i] == CitySim.Z.NONE or sim.floors[i] <= 0: continue
		_bld_cells.append(i)

	_bld_mm.multimesh.instance_count = _bld_cells.size()
	_cap_mm.multimesh.instance_count = _bld_cells.size()

func _cache_tile_xforms() -> void:
	_tile_xforms.clear()
	_tile_xforms.resize(CitySim.CELLS)
	for y in CitySim.N:
		for x in CitySim.N:
			var i: int = y * CitySim.N + x
			var p: Vector3 = sim.world_pos(x, y)
			_tile_xforms[i] = Transform3D(Basis(), Vector3(p.x, 0.175, p.z))

func _build_bld_jitter() -> void:
	_bld_jitter.resize(CitySim.CELLS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC0FFEE
	for i in CitySim.CELLS:
		_bld_jitter[i] = rng.randf_range(-0.09, 0.09)

# ─────────────────────────────────────────────────────────────
#  LANDMARKS
# ─────────────────────────────────────────────────────────────
func _build_landmarks() -> void:
	_landmark_root = Node3D.new()
	_landmark_root.name = "Landmarks"
	add_child(_landmark_root)

	for entry in LANDMARK_PLACEMENTS:
		var cell: Array = entry["cell"]
		var kind: String = entry["kind"]
		var mesh: ArrayMesh
		match kind:
			"clock_tower": mesh = Landmarks.make_clock_tower()
			"cathedral":   mesh = Landmarks.make_cathedral()
			"obelisk":     mesh = Landmarks.make_obelisk()
			"radio_mast":  mesh = Landmarks.make_radio_mast()
			"spire_tower": mesh = Landmarks.make_spire_tower()
			_: continue

		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _stone_mat
		var wp: Vector3 = sim.world_pos(cell[0], cell[1])
		mi.position = Vector3(wp.x, 0.0, wp.z)
		_landmark_root.add_child(mi)

# ─────────────────────────────────────────────────────────────
func refresh_all() -> void:
	_refresh_tiles()
	_refresh_buildings()
	_refresh_sun()

func _refresh_tiles() -> void:
	var mm: MultiMesh = _tiles_mm.multimesh
	for i in CitySim.CELLS:
		mm.set_instance_transform(i, _tile_xforms[i])
		mm.set_instance_color(i, _tile_color(i))

func _tile_color(i: int) -> Color:
	if overlay != Overlay.NATURAL:
		return _overlay_color(i)

	var t: int = sim.terrain[i]
	match t:
		CitySim.T.WATER: return Color(0.09, 0.20, 0.34)
		CitySim.T.ROAD:  return Color(0.13, 0.13, 0.145)
		CitySim.T.PARK:  return Color(0.15, 0.30, 0.16)
		CitySim.T.PLAZA: return Color(0.24, 0.24, 0.26)
	return Color(0.18, 0.19, 0.17)

func _overlay_color(i: int) -> Color:
	var v: float = 0.0
	match overlay:
		Overlay.AIR:
			v = clampf(sim.air_pol[i] / 45.0, 0.0, 1.0)
		Overlay.WATER:
			v = 1.0 - clampf(sim.water_pol[i] / 3.0, 0.0, 1.0)
		Overlay.ENERGY:
			v = clampf(float(sim.floors[i]) / 26.0, 0.0, 1.0) * sim.occupancy[i]
		Overlay.TRAFFIC:
			if sim.terrain[i] == CitySim.T.ROAD:
				v = clampf(sim.s["traffic_congestion"], 0.0, 1.0)
			else:
				v = 0.0
		Overlay.SAFETY:
			v = 1.0 - clampf(sim.s["crime_rate"] / 55.0, 0.0, 1.0)
		Overlay.GREEN:
			if sim.terrain[i] == CitySim.T.PARK:
				v = 1.0
			else:
				v = clampf(sim.s["green_m2_capita"] / 30.0, 0.0, 1.0)
		Overlay.POPULATION:
			v = clampf(float(sim.floors[i]) * sim.occupancy[i] / 26.0, 0.0, 1.0)
		Overlay.LAND_VALUE:
			v = clampf(sim.land_value[i] / 1_200_000.0, 0.0, 1.0)
	return _heat(v)

func _heat(v: float) -> Color:
	if v < 0.25:
		return Color(0.08, 0.14, 0.38).lerp(Color(0.10, 0.55, 0.75), v / 0.25)
	if v < 0.50:
		return Color(0.10, 0.55, 0.75).lerp(Color(0.20, 0.72, 0.36), (v - 0.25) / 0.25)
	if v < 0.75:
		return Color(0.20, 0.72, 0.36).lerp(Color(0.92, 0.82, 0.20), (v - 0.50) / 0.25)
	return Color(0.92, 0.82, 0.20).lerp(Color(0.88, 0.20, 0.16), (v - 0.75) / 0.25)

func _refresh_buildings() -> void:
	var night: float = _night_factor()
	var lit_color: Color = Color(1.0, 0.84, 0.52)
	var dark_color: Color = Color(0.10, 0.11, 0.16)
	var cell_size: float = CitySim.CELL
	var zone_ind: int = CitySim.Z.IND
	var zone_res: int = CitySim.Z.RES

	var supply_delta: float = (sim.s["pol_housing_supply"] - 0.5) * 2.0
	var res_floor_delta: int = int(supply_delta * 3.0)

	var bmm: MultiMesh = _bld_mm.multimesh
	var cmm: MultiMesh = _cap_mm.multimesh

	for idx in _bld_cells.size():
		var i: int = _bld_cells[idx]
		var fl: int = sim.floors[i]
		if sim.zone[i] == zone_res:
			fl = max(1, fl + res_floor_delta)
		var h: float = float(fl) * 3.2

		var fw: float = cell_size * (0.62 + 0.28 * sim.occupancy[i])
		if sim.zone[i] == zone_ind:
			fw = cell_size * 0.88

		var xf: Transform3D = _tile_xforms[i]
		var o: Vector3 = xf.origin

		# main building mass
		bmm.set_instance_transform(idx,
			Transform3D(Basis().scaled(Vector3(fw, h, fw)),
				Vector3(o.x, h * 0.5, o.z)))

		# per-instance color jitter for architectural variety
		var base: Color = _building_base_color(i)
		var j: float = _bld_jitter[i]
		if j >= 0.0:
			base = base.lightened(j)
		else:
			base = base.darkened(-j)

		var lit: float = night * sim.occupancy[i]
		var c: Color = base.lerp(lit_color, lit * 0.48)
		c = c * (1.0 - 0.45 * night) + dark_color * (0.45 * night)
		bmm.set_instance_color(idx, c)

		# flat roof cap (thin parapet)
		var cap_h: float = 0.9
		var cap_w: float = fw * 1.06
		cmm.set_instance_transform(idx,
			Transform3D(Basis().scaled(Vector3(cap_w, cap_h, cap_w)),
				Vector3(o.x, h + cap_h * 0.5 - 0.2, o.z)))
		var cap_col: Color = base.darkened(0.42)
		cap_col = cap_col * (1.0 - 0.60 * night) + Color(0.06, 0.07, 0.10) * (0.60 * night)
		cmm.set_instance_color(idx, cap_col)

func _building_base_color(i: int) -> Color:
	match sim.util[i]:
		CitySim.U.POWER:       return Color(0.42, 0.30, 0.26)
		CitySim.U.WATER_TREAT: return Color(0.24, 0.38, 0.46)
		CitySim.U.RECYCLE:     return Color(0.28, 0.44, 0.32)
		CitySim.U.LANDFILL:    return Color(0.32, 0.29, 0.22)
		CitySim.U.HOSPITAL:    return Color(0.86, 0.88, 0.90)
		CitySim.U.SCHOOL:      return Color(0.78, 0.72, 0.54)
		CitySim.U.POLICE:      return Color(0.34, 0.42, 0.62)
		CitySim.U.SOLAR:       return Color(0.18, 0.22, 0.34)
		CitySim.U.WIND:        return Color(0.72, 0.76, 0.80)

	match sim.zone[i]:
		CitySim.Z.RES:
			return Color(0.62, 0.57, 0.50).lerp(Color(0.76, 0.72, 0.66), sim.occupancy[i] - 0.82)
		CitySim.Z.COM:
			return Color(0.34, 0.42, 0.54).lerp(Color(0.54, 0.64, 0.76), sim.occupancy[i] - 0.8)
		CitySim.Z.IND:
			return Color(0.34, 0.32, 0.29)
		CitySim.Z.CIVIC:
			return Color(0.70, 0.74, 0.76)
	return Color(0.5, 0.5, 0.5)

func _night_factor() -> float:
	var h: float = float(sim.tick % CitySim.HOURS_PER_DAY)
	if h < 5.0:
		return 1.0
	if h < 7.0:
		return 1.0 - (h - 5.0) / 2.0
	if h < 18.0:
		return 0.0
	if h < 21.0:
		return (h - 18.0) / 3.0
	return 1.0

func _refresh_sun() -> void:
	var t: float = float(sim.tick % CitySim.HOURS_PER_DAY) / 24.0
	var angle: float = t * TAU - PI * 0.5
	var elev: float = sin(angle) * 62.0
	var azim: float = 115.0

	_sun.rotation_degrees = Vector3(-max(elev, -8.0), azim, 0.0)
	var night: float = _night_factor()
	_sun.light_energy = lerpf(1.20, 0.08, night)
	_sun.light_color = Color(1.0, 0.96, 0.88).lerp(Color(0.55, 0.62, 0.86), night)

	var e: Environment = _env.environment
	if mobile:
		e.ambient_light_energy = lerpf(0.65, 0.25, night)
	else:
		e.ambient_light_energy = lerpf(0.55, 0.22, night)
		e.fog_light_color = Color(0.42, 0.50, 0.62).lerp(Color(0.06, 0.08, 0.14), night)

func refresh_buildings_smooth() -> void:
	var n: float = _night_factor()
	var threshold: float = 0.025 if mobile else 0.01
	if absf(n - _bld_night) > threshold:
		_refresh_buildings()
		_bld_night = n
		if _stone_mat:
			_stone_mat.set_shader_parameter("night", n)

func set_overlay(o: int) -> void:
	overlay = o
	_refresh_tiles()
