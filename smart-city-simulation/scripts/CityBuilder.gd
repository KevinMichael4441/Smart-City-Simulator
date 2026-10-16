class_name CityBuilder
extends Node3D

var sim: CitySim
var mobile: bool = false

# ── static geometry ──────────────────────────────────────────
var _tiles_mm: MultiMeshInstance3D
var _bld_mm: MultiMeshInstance3D
var _harbour_mm: MultiMeshInstance3D
var _stop_mm: MultiMeshInstance3D
var _warehouse_mm: MultiMeshInstance3D
var _cap_mm: MultiMeshInstance3D

var _tile_mesh: BoxMesh
var _bld_mesh: BoxMesh
var _pier_mesh: BoxMesh
var _warehouse_mesh: BoxMesh
var _stop_mesh: BoxMesh

var overlay: int = 0

enum Overlay { NATURAL, AIR, WATER, ENERGY, TRAFFIC, SAFETY, GREEN, POPULATION, LAND_VALUE }

const OVERLAY_NAMES: Array = ["Natural", "Air Quality", "Water Quality", "Energy Load",
	"Traffic", "Safety", "Green Space", "Density", "Land Value"]

var _sun: DirectionalLight3D
var _env: WorldEnvironment

var _bld_cells: PackedInt32Array = PackedInt32Array()
var _tile_xforms: Array[Transform3D] = []
var _bld_night: float = -999.0

var _bld_mat: ShaderMaterial
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

# ── agents ───────────────────────────────────────────────────
var _agent_mat: StandardMaterial3D

var _cars_mm: MultiMeshInstance3D
var _buses_mm: MultiMeshInstance3D
var _trams_mm: MultiMeshInstance3D
var _boats_mm: MultiMeshInstance3D
var _peds_mm: MultiMeshInstance3D

var _car_mesh: BoxMesh
var _bus_mesh: BoxMesh
var _tram_mesh: BoxMesh
var _boat_mesh: BoxMesh
var _ped_mesh: BoxMesh

# road graph
var _road_cells: PackedInt32Array = PackedInt32Array()
var _road_neighbors: Array = []           # per road cell: array of neighbour road array indices
var _road_lookup: Dictionary = {}         # cell index -> road array index

# bus stops (indices into _road_cells)
var _stop_cells: PackedInt32Array = PackedInt32Array()

# river path (ordered cell indices, west to east)
var _river_path: PackedInt32Array = PackedInt32Array()

# harbour
var _harbour_origin: Vector2i = Vector2i(-1, -1)
var _pier_cells: PackedInt32Array = PackedInt32Array()

# ── agent classes ────────────────────────────────────────────
class Car:
	var cell_idx: int = 0
	var prev_cell_idx: int = -1
	var next_cell_idx: int = 0
	var t: float = 0.0
	var speed: float = 3.0
	var turn: float = 0.0
	var color: Color = Color.WHITE

class Ped:
	var from: Vector3 = Vector3.ZERO
	var to: Vector3 = Vector3.ZERO
	var t: float = 0.0
	var speed: float = 1.0
	var wait: float = 0.0
	var color: Color = Color.WHITE

class Boat:
	var path_pos: float = 0.0
	var speed: float = 1.0
	var color: Color = Color.WHITE

var _cars: Array = []
var _buses: Array = []
var _trams: Array = []
var _peds: Array = []
var _boats: Array = []

const MAX_CARS := 700
const MAX_BUSES := 90
const MAX_TRAMS := 30
const MAX_PEDS := 1800
const MAX_BOATS := 8

var _rng := RandomNumberGenerator.new()


# ─────────────────────────────────────────────────────────────
#  SETUP
# ─────────────────────────────────────────────────────────────
func setup(sim_ref: CitySim, is_mobile: bool = false) -> void:
	sim = sim_ref
	mobile = is_mobile
	_rng.seed = hash(sim.tick) ^ 0x9E3779B9

	_build_environment()
	_build_materials()
	_build_meshes()
	_build_harbour()
	_build_bld_indices()
	_build_road_graph()
	_build_river_path()
	_cache_tile_xforms()
	_build_bld_jitter()
	_build_landmarks()
	refresh_all()
	_seed_agents()

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

# ─────────────────────────────────────────────────────────────
#  ENVIRONMENT
# ─────────────────────────────────────────────────────────────
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


# ─────────────────────────────────────────────────────────────
#  MESHES
# ─────────────────────────────────────────────────────────────
func _build_meshes() -> void:
	# ── tiles ──
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

	# ── buildings (window shader) ──
	_bld_mesh = BoxMesh.new()
	_bld_mesh.size = Vector3(1.0, 1.0, 1.0)
	_bld_mesh.subdivide_width = 4
	_bld_mesh.subdivide_height = 4
	_bld_mesh.subdivide_depth = 4

	_bld_mat = ShaderMaterial.new()
	_bld_mat.shader = _make_window_shader()
	_bld_mat.set_shader_parameter("night", 0.0)
	_bld_mat.set_shader_parameter("flicker_speed", 0.35)
	_bld_mat.set_shader_parameter("lit_color_warm", Color(1.00, 0.82, 0.48))
	_bld_mat.set_shader_parameter("lit_color_cool", Color(0.80, 0.90, 1.00))
	_bld_mat.set_shader_parameter("window_density", Vector2(6.0, 9.0))
	_bld_mat.set_shader_parameter("window_size", Vector2(0.62, 0.52))
	_bld_mat.set_shader_parameter("lit_density", 0.55)
	_bld_mat.set_shader_parameter("emission_strength", 2.2)

	_bld_mm = MultiMeshInstance3D.new()
	var bmm: MultiMesh = MultiMesh.new()
	bmm.transform_format = MultiMesh.TRANSFORM_3D
	bmm.use_colors = true
	bmm.mesh = _bld_mesh
	bmm.instance_count = 0
	_bld_mm.multimesh = bmm
	_bld_mm.material_override = _bld_mat
	add_child(_bld_mm)

	# ── harbour geometry ──
	_pier_mesh = BoxMesh.new()
	_pier_mesh.size = Vector3(6.0, 0.6, 6.0)
	# cap layer — same unit box, scaled flat and wide at the top of each building
	_cap_mm = MultiMeshInstance3D.new()
	var cmm: MultiMesh = MultiMesh.new()
	cmm.transform_format = MultiMesh.TRANSFORM_3D
	cmm.use_colors = true
	cmm.mesh = _bld_mesh
	cmm.instance_count = 0
	_cap_mm.multimesh = cmm
	#_cap_mm.material_override = bmat
	add_child(_cap_mm)

	var pier_mat := StandardMaterial3D.new()
	pier_mat.vertex_color_use_as_albedo = true
	pier_mat.roughness = 0.85

	_harbour_mm = MultiMeshInstance3D.new()
	var hmm: MultiMesh = MultiMesh.new()
	hmm.transform_format = MultiMesh.TRANSFORM_3D
	hmm.use_colors = true
	hmm.mesh = _pier_mesh
	hmm.instance_count = 0
	_harbour_mm.multimesh = hmm
	_harbour_mm.material_override = pier_mat
	add_child(_harbour_mm)

	# Warehouses: unit box scaled per-instance.
	_warehouse_mesh = BoxMesh.new()
	_warehouse_mesh.size = Vector3(1.0, 1.0, 1.0)

	var wh_mat := StandardMaterial3D.new()
	wh_mat.vertex_color_use_as_albedo = true
	wh_mat.roughness = 0.8

	_warehouse_mm = MultiMeshInstance3D.new()
	var wmm_setup: MultiMesh = MultiMesh.new()
	wmm_setup.transform_format = MultiMesh.TRANSFORM_3D
	wmm_setup.use_colors = true
	wmm_setup.mesh = _warehouse_mesh
	wmm_setup.instance_count = 0
	_warehouse_mm.multimesh = wmm_setup
	_warehouse_mm.material_override = wh_mat
	add_child(_warehouse_mm)
		# ── bus stop markers ──
	_stop_mesh = BoxMesh.new()
	_stop_mesh.size = Vector3(1.4, 2.2, 1.4)

	var stop_mat := StandardMaterial3D.new()
	stop_mat.vertex_color_use_as_albedo = true
	stop_mat.roughness = 0.75

	_stop_mm = MultiMeshInstance3D.new()
	var stopmm: MultiMesh = MultiMesh.new()
	stopmm.transform_format = MultiMesh.TRANSFORM_3D
	stopmm.use_colors = true
	stopmm.mesh = _stop_mesh
	stopmm.instance_count = 0
	_stop_mm.multimesh = stopmm
	_stop_mm.material_override = stop_mat
	add_child(_stop_mm)
	
	# ── agents ──
	_agent_mat = StandardMaterial3D.new()
	_agent_mat.vertex_color_use_as_albedo = true
	_agent_mat.roughness = 0.7
	_agent_mat.specular = 0.2

	_car_mesh = BoxMesh.new()
	_car_mesh.size = Vector3(2.2, 1.4, 4.0)

	_bus_mesh = BoxMesh.new()
	_bus_mesh.size = Vector3(2.8, 3.0, 9.0)

	_tram_mesh = BoxMesh.new()
	_tram_mesh.size = Vector3(2.4, 3.2, 12.0)

	_boat_mesh = BoxMesh.new()
	_boat_mesh.size = Vector3(4.0, 2.2, 11.0)

	_ped_mesh = BoxMesh.new()
	_ped_mesh.size = Vector3(0.9, 2.0, 0.9)

	_cars_mm  = _make_mm_inst(_car_mesh,  MAX_CARS)
	_buses_mm = _make_mm_inst(_bus_mesh,  MAX_BUSES)
	_trams_mm = _make_mm_inst(_tram_mesh, MAX_TRAMS)
	_boats_mm = _make_mm_inst(_boat_mesh, MAX_BOATS)
	_peds_mm  = _make_mm_inst(_ped_mesh,  MAX_PEDS)


func _make_mm_inst(mesh: Mesh, _cap: int) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = 0
	mmi.multimesh = mm
	mmi.material_override = _agent_mat
	add_child(mmi)
	return mmi


func _make_window_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float flicker_speed : hint_range(0.0, 2.0) = 0.35;
uniform vec3 lit_color_warm : source_color = vec3(1.0, 0.82, 0.48);
uniform vec3 lit_color_cool : source_color = vec3(0.80, 0.90, 1.00);
uniform vec2 window_density = vec2(6.0, 9.0);
uniform vec2 window_size    = vec2(0.62, 0.52);
uniform float lit_density   : hint_range(0.0, 1.0) = 0.55;
uniform float emission_strength : hint_range(0.0, 6.0) = 2.2;

varying vec3 v_instance_color;
varying float v_time;

void vertex() {
    v_instance_color = COLOR.rgb;
    v_time = TIME * flicker_speed;
}

float hash21(vec2 p) {
    p = fract(p * vec2(233.34, 951.73));
    p += dot(p, p + 23.45);
    return fract(p.x * p.y);
}

void fragment() {
    vec2 uv = UV;
    float is_side = 1.0 - step(0.7, abs(NORMAL.y));
    vec2 grid = uv * window_density;
    vec2 cell = floor(grid);
    vec2 local = fract(grid);
    vec2 d = abs(local - 0.5);
    vec2 half_size = window_size * 0.5;
    float in_window = step(d.x, half_size.x) * step(d.y, half_size.y) * is_side;

    float seed = dot(v_instance_color, vec3(37.1, 91.7, 17.3));
    float r_static = hash21(cell + vec2(seed, seed * 0.37));
    float phase = r_static * 6.2831 + seed;
    float freq = 0.7 + 0.6 * hash21(cell * 1.7 + seed);
    float osc = sin(v_time * freq + phase);
    float thresh = 1.0 - lit_density * 2.0;
    float on = step(thresh, osc);

    float warmness = v_instance_color.r;
    vec3 window_on_color = mix(lit_color_cool, lit_color_warm, warmness);

    vec3 facade = v_instance_color * 0.45;
    vec3 albedo = mix(facade, facade * 0.5, in_window);
    albedo = mix(albedo, window_on_color, in_window * on * night * 0.6);

    vec3 emis = window_on_color * in_window * on * night * emission_strength;

    ALBEDO = albedo;
    EMISSION = emis;
    ROUGHNESS = 0.62;
    METALLIC = 0.05;
    SPECULAR = 0.35;
}
"""
	return sh


# ─────────────────────────────────────────────────────────────
#  HARBOUR
# ─────────────────────────────────────────────────────────────
func _build_harbour() -> void:
	var best_x := -1
	var best_y := -1
	var best_score := -1

	for x in CitySim.N:
		for y in CitySim.N:
			var i: int = y * CitySim.N + x
			if sim.terrain[i] != CitySim.T.WATER:
				continue
			var land_count := 0
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or ny < 0 or nx >= CitySim.N or ny >= CitySim.N:
						continue
					if sim.terrain[ny * CitySim.N + nx] == CitySim.T.LAND:
						land_count += 1
			var centre_bonus: int = -abs(x - CitySim.N / 2)
			var score := land_count + centre_bonus
			if score > best_score:
				best_score = score
				best_x = x
				best_y = y

	if best_x < 0:
		return

	_harbour_origin = Vector2i(best_x, best_y)
	_pier_cells.clear()

	# ── piers ──
	var pier_xforms: Array = []
	var pier_colors: Array = []

	for k in 3:
		var px: int = best_x - 2 + k * 2
		var py: int = best_y - 1
		if px < 0 or py < 0 or px >= CitySim.N or py >= CitySim.N:
			continue
		var pi: int = py * CitySim.N + px
		if sim.terrain[pi] != CitySim.T.WATER:
			continue
		var p: Vector3 = sim.world_pos(px, py)
		pier_xforms.append(Transform3D(
			Basis().scaled(Vector3(1.0, 1.0, 1.0)),
			Vector3(p.x, 0.3, p.z)))
		pier_colors.append(Color(0.30, 0.28, 0.24))
		_pier_cells.append(pi)

	# ── warehouses on land, north of the water ──
	var wh_xforms: Array = []
	var wh_colors: Array = []

	for k in 3:
		var wx: int = best_x - 3 + k * 3
		var wy: int = best_y - 3
		if wx < 0 or wy < 0 or wx >= CitySim.N or wy >= CitySim.N:
			continue
		var wi: int = wy * CitySim.N + wx
		if sim.terrain[wi] != CitySim.T.LAND:
			continue
		if sim.util[wi] != CitySim.U.NONE:
			continue

		# carve out an industrial zone patch around the warehouse so it
		# doesn't get overlapped by a residential tower
		sim.zone[wi] = CitySim.Z.IND
		sim.floors[wi] = 2
		sim.occupancy[wi] = 0.95

		var p: Vector3 = sim.world_pos(wx, wy)
		# a warehouse is 1 cell wide, 1 cell deep, and 6m tall
		var wsize: float = CitySim.CELL * 0.85
		wh_xforms.append(Transform3D(
			Basis().scaled(Vector3(wsize, 6.0, wsize)),
			Vector3(p.x, 3.0, p.z)))
		wh_colors.append(Color(0.42, 0.36, 0.28))

	# ── commit to MultiMeshes ──
	var pmm: MultiMesh = _harbour_mm.multimesh
	pmm.instance_count = pier_xforms.size()
	for idx in pier_xforms.size():
		pmm.set_instance_transform(idx, pier_xforms[idx])
		pmm.set_instance_color(idx, pier_colors[idx])

	var wmm: MultiMesh = _warehouse_mm.multimesh
	wmm.instance_count = wh_xforms.size()
	for idx in wh_xforms.size():
		wmm.set_instance_transform(idx, wh_xforms[idx])
		wmm.set_instance_color(idx, wh_colors[idx])

# ─────────────────────────────────────────────────────────────
#  ROAD GRAPH
# ─────────────────────────────────────────────────────────────
func _build_road_graph() -> void:
	_road_cells.clear()
	_road_lookup.clear()
	for i in CitySim.CELLS:
		if sim.terrain[i] == CitySim.T.ROAD:
			_road_lookup[i] = _road_cells.size()
			_road_cells.append(i)

	_road_neighbors.clear()
	_road_neighbors.resize(_road_cells.size())

	var offsets: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]

	for k in _road_cells.size():
		var i: int = int(_road_cells[k])
		var x: int = i % CitySim.N
		var y: int = i / CitySim.N
		var n: Array = []
		for off in offsets:
			var nx: int = x + off.x
			var ny: int = y + off.y
			if nx < 0 or ny < 0 or nx >= CitySim.N or ny >= CitySim.N:
				continue
			var ni: int = ny * CitySim.N + nx
			if _road_lookup.has(ni):
				n.append(_road_lookup[ni])
		_road_neighbors[k] = n

	# bus stops every ~stride road cells
	_stop_cells.clear()
	var stride: int = max(1, _road_cells.size() / 24)
	for k in range(0, _road_cells.size(), stride):
		_stop_cells.append(k)

	var smm: MultiMesh = _stop_mm.multimesh
	smm.instance_count = _stop_cells.size()
	for idx in _stop_cells.size():
		var rk: int = int(_stop_cells[idx])
		var i: int = int(_road_cells[rk])
		var x: int = i % CitySim.N
		var y: int = i / CitySim.N
		var p: Vector3 = sim.world_pos(x, y)
		smm.set_instance_transform(idx, Transform3D(Basis(), Vector3(p.x, 1.1, p.z)))
		smm.set_instance_color(idx, Color(0.85, 0.55, 0.25))


# ─────────────────────────────────────────────────────────────
#  RIVER PATH
# ─────────────────────────────────────────────────────────────
func _build_river_path() -> void:
	_river_path.clear()
	for x in CitySim.N:
		var min_y := CitySim.N
		var max_y := -1
		for y in CitySim.N:
			var i: int = y * CitySim.N + x
			if sim.terrain[i] == CitySim.T.WATER:
				min_y = min(min_y, y)
				max_y = max(max_y, y)
		if max_y >= 0:
			var mid_y: int = (min_y + max_y) / 2
			_river_path.append(mid_y * CitySim.N + x)


# ─────────────────────────────────────────────────────────────
#  SEED AGENTS
# ─────────────────────────────────────────────────────────────
func _seed_agents() -> void:
	if _road_cells.is_empty():
		return

	var pop: float = sim.s["population"]
	var congestion: float = sim.s["traffic_congestion"]
	var transit: float = sim.s["transit_share"]

	var n_cars: int = clampi(int(pop / 80.0 * (0.6 + 0.7 * congestion)), 60, MAX_CARS)
	for k in n_cars:
		_cars.append(_make_vehicle())

	var bus_palette := [
		Color(0.78, 0.42, 0.15),   # orange
		Color(0.30, 0.55, 0.72),   # blue
		Color(0.42, 0.65, 0.38),   # green
		Color(0.85, 0.72, 0.30),   # yellow
	]
	var n_buses: int = clampi(int(pop / 1400.0) + 8, 8, MAX_BUSES)
	for k in n_buses:
		var b: Car = _make_vehicle()
		b.color = bus_palette[k % bus_palette.size()]
		_buses.append(b)

	var n_trams: int = clampi(int(transit * 55.0) - 3, 0, MAX_TRAMS)
	for k in n_trams:
		var tr := _make_vehicle()
		tr.color = Color(0.85, 0.85, 0.88)   # tram silver
		_trams.append(tr)

	var n_peds: int = clampi(int(pop / 9.0), 200, MAX_PEDS)
	for k in n_peds:
		_peds.append(_spawn_ped())

	var trade: float = maxf(sim.s["exports_value"], sim.s["imports_value"])
	var n_boats: int = clampi(3 + int(trade / 18000.0), 3, MAX_BOATS)
	for k in n_boats:
		_boats.append(_make_boat(k))

	_cars_mm.multimesh.instance_count = n_cars
	_buses_mm.multimesh.instance_count = n_buses
	_trams_mm.multimesh.instance_count = n_trams
	_peds_mm.multimesh.instance_count = n_peds
	_boats_mm.multimesh.instance_count = n_boats

func _random_vehicle_color() -> Color:
	var palette := [
		Color(0.75, 0.15, 0.15),   # red
		Color(0.20, 0.32, 0.72),   # blue
		Color(0.24, 0.24, 0.26),   # near-black
		Color(0.88, 0.88, 0.90),   # white
		Color(0.55, 0.58, 0.62),   # silver
		Color(0.85, 0.72, 0.30),   # yellow
		Color(0.30, 0.55, 0.35),   # green
		Color(0.65, 0.35, 0.15),   # orange-brown
	]
	return palette[_rng.randi_range(0, palette.size() - 1)]
func _make_vehicle() -> Car:
	var c := Car.new()

	# bias spawns toward arterial roads
	var rk := 0
	for attempt in 8:
		rk = _rng.randi_range(0, _road_cells.size() - 1)
		var ci: int = int(_road_cells[rk])
		var cx: int = ci % CitySim.N
		var cy: int = ci / CitySim.N
		if cx % 8 == 0 or cy % 8 == 0:
			break

	c.cell_idx = rk
	c.prev_cell_idx = -1
	c.next_cell_idx = rk
	c.t = _rng.randf()
	c.speed = _rng.randf_range(3.0, 5.5)
	c.turn = 0.0
	c.color = _random_vehicle_color()

	_choose_next(c)
	c.prev_cell_idx = -1
	return c


func _choose_next(c: Car) -> void:
	var neigh: Array = _road_neighbors[c.cell_idx]
	if neigh.is_empty():
		c.next_cell_idx = c.cell_idx
		return

	var candidates: Array = []
	for n_idx in neigh:
		if n_idx != c.prev_cell_idx:
			candidates.append(n_idx)

	if candidates.is_empty():
		candidates = neigh.duplicate()

	var chosen: int = -1
	if c.prev_cell_idx >= 0:
		var cur: Vector3 = _cell_world(c.cell_idx)
		var prev: Vector3 = _cell_world(c.prev_cell_idx)
		var heading: Vector3 = cur - prev
		heading.y = 0.0
		if heading.length_squared() > 0.001:
			heading = heading.normalized()
			var best_dot := -2.0
			for cand in candidates:
				var cw: Vector3 = _cell_world(cand)
				var d: Vector3 = cw - cur
				d.y = 0.0
				if d.length_squared() < 0.001:
					continue
				d = d.normalized()
				var dot: float = heading.dot(d)
				if dot > best_dot:
					best_dot = dot
					chosen = cand

	if chosen < 0:
		chosen = candidates[_rng.randi_range(0, candidates.size() - 1)]

	c.next_cell_idx = chosen
func _random_person_color() -> Color:
	var palette := [
		Color(0.18, 0.20, 0.26),   # navy
		Color(0.30, 0.26, 0.22),   # brown
		Color(0.55, 0.55, 0.58),   # grey
		Color(0.72, 0.68, 0.62),   # cream
		Color(0.75, 0.30, 0.28),   # red
		Color(0.24, 0.42, 0.62),   # blue
		Color(0.42, 0.55, 0.36),   # olive
		Color(0.62, 0.42, 0.30),   # tan
		Color(0.85, 0.78, 0.62),   # sand
		Color(0.42, 0.28, 0.42),   # plum
	]
	return palette[_rng.randi_range(0, palette.size() - 1)]

func _spawn_ped() -> Ped:
	var p := Ped.new()

	var rk: int = _rng.randi_range(0, _road_cells.size() - 1)
	var ri: int = int(_road_cells[rk])
	var rx: int = ri % CitySim.N
	var ry: int = ri / CitySim.N
	var origin: Vector3 = sim.world_pos(rx, ry)

	p.from = Vector3(
		origin.x + _rng.randf_range(-3.0, 3.0),
		1.0,
		origin.z + _rng.randf_range(-3.0, 3.0))

	var best_rk: int = rk
	for attempt in 6:
		var try_rk: int = _rng.randi_range(0, _road_cells.size() - 1)
		var ti: int = int(_road_cells[try_rk])
		var tx: int = ti % CitySim.N
		var ty: int = ti / CitySim.N
		if abs(tx - rx) <= 5 and abs(ty - ry) <= 5:
			best_rk = try_rk
			break

	var tgt_i: int = int(_road_cells[best_rk])
	var tgt_x: int = tgt_i % CitySim.N
	var tgt_y: int = tgt_i / CitySim.N
	var target: Vector3 = sim.world_pos(tgt_x, tgt_y)

	p.to = Vector3(
		target.x + _rng.randf_range(-3.0, 3.0),
		1.0,
		target.z + _rng.randf_range(-3.0, 3.0))

	p.t = _rng.randf()
	p.speed = _rng.randf_range(0.8, 1.6)
	p.wait = 0.0
	p.color = _random_person_color()    # ← colour assigned here, before the return

	return p                            # ← returns the Ped
func _make_boat(k: int) -> Boat:
	var b := Boat.new()
	b.path_pos = float(k) / float(MAX_BOATS) * float(_river_path.size())
	b.speed = _rng.randf_range(0.6, 1.4)
	b.color = Color(
		_rng.randf_range(0.4, 0.85),
		_rng.randf_range(0.4, 0.85),
		_rng.randf_range(0.4, 0.85))
	return b


# ─────────────────────────────────────────────────────────────
#  CACHE / REFRESH
# ─────────────────────────────────────────────────────────────
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
		CitySim.T.PLAZA: return Color(0.40, 0.32, 0.20)
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

		
		var zone_i: int = sim.zone[i]
		var warmness := 1.0
		match zone_i:
			CitySim.Z.COM:   warmness = 0.1
			CitySim.Z.CIVIC: warmness = 0.5
			CitySim.Z.IND:   warmness = 0.85
			CitySim.Z.RES:   warmness = 1.0

		var base: Color = _building_base_color(i)
		var grey: float = clampf(base.r * 0.299 + base.g * 0.587 + base.b * 0.114, 0.05, 0.95)

		
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
	_sun.light_energy = lerpf(1.20, 0.35, night)
	_sun.light_color = Color(1.0, 0.96, 0.88).lerp(Color(0.62, 0.68, 0.90), night)

	var e: Environment = _env.environment
	if mobile:
		e.ambient_light_energy = lerpf(0.65, 0.40, night)
	else:
		e.ambient_light_energy = lerpf(0.55, 0.35, night)
		e.fog_light_color = Color(0.42, 0.50, 0.62).lerp(Color(0.10, 0.12, 0.20), night)

	_bld_mat.set_shader_parameter("night", night)

func refresh_buildings_smooth() -> void:
	var n: float = _night_factor()
	var threshold: float = 0.02 if mobile else 0.008
	if absf(n - _bld_night) > threshold:
		_refresh_buildings()
		_bld_night = n
		if _stone_mat:
			_stone_mat.set_shader_parameter("night", n)

func night_factor() -> float:
	return _night_factor()


func set_overlay(o: int) -> void:
	overlay = o
	_refresh_tiles()


# ─────────────────────────────────────────────────────────────
#  AGENT UPDATE  — called from Main._process()
# ─────────────────────────────────────────────────────────────
func tick_agents(delta: float, hours_per_second: float) -> void:
	var scale: float = clampf(hours_per_second / 3.0, 0.2, 4.0)
	var d: float = delta * scale

	_update_vehicles(_cars, _cars_mm, d, 1.0)
	_update_vehicles(_buses, _buses_mm, d, 0.55)
	_update_vehicles(_trams, _trams_mm, d, 0.7)
	_update_peds(d)
	_update_boats(d)


func _update_vehicles(arr: Array, mmi: MultiMeshInstance3D, delta: float, speed_mult: float) -> void:
	if arr.is_empty():
		return
	var mm: MultiMesh = mmi.multimesh
	var congestion: float = sim.s["traffic_congestion"]
	var cong_slow: float = 1.0 - 0.7 * congestion
	var night: float = _night_factor()

	for k in arr.size():
		var c: Car = arr[k]

		if c.turn > 0.0:
			c.turn -= delta
		else:
			c.t += delta * c.speed * speed_mult * cong_slow
			if c.t >= 1.0:
				c.t = 0.0
				c.prev_cell_idx = c.cell_idx
				c.cell_idx = c.next_cell_idx
				_choose_next(c)
				if _rng.randf() < 0.12:
					c.turn = _rng.randf_range(0.2, 0.7)

		var a: Vector3 = _cell_world(c.cell_idx)
		var b: Vector3 = _cell_world(c.next_cell_idx)
		var pos: Vector3 = a.lerp(b, c.t)
		pos.y = 1.1

		var dir: Vector3 = (b - a)
		dir.y = 0.0
		var yaw: float = 0.0
		if dir.length_squared() > 0.001:
			yaw = atan2(dir.x, dir.z)

		var basis := Basis(Vector3.UP, yaw)
		mm.set_instance_transform(k, Transform3D(basis, pos))

		var col: Color = c.color.lerp(Color(1.0, 0.85, 0.55), night * 0.35)
		mm.set_instance_color(k, col)


func _cell_world(i: int) -> Vector3:
	var x: int = i % CitySim.N
	var y: int = i / CitySim.N
	return sim.world_pos(x, y)


func _update_peds(delta: float) -> void:
	if _peds.is_empty():
		return
	var mm: MultiMesh = _peds_mm.multimesh

	for k in _peds.size():
		var p: Ped = _peds[k]

		if p.wait > 0.0:
			p.wait -= delta
		else:
			p.t += delta * p.speed * 0.30
			if p.t >= 1.0:
				var to_stop := _rng.randf() < 0.3 and not _stop_cells.is_empty()
				var target_cell: int = -1
				if to_stop:
					var sk: int = int(_stop_cells[_rng.randi_range(0, _stop_cells.size() - 1)])
					target_cell = int(_road_cells[sk])
				else:
					var cx: int = int((p.to.x / CitySim.CELL) + CitySim.N * 0.5)
					var cy: int = int((p.to.z / CitySim.CELL) + CitySim.N * 0.5)
					var found: int = -1
					for attempt in 12:
						var ox: int = clampi(cx + _rng.randi_range(-4, 4), 0, CitySim.N - 1)
						var oy: int = clampi(cy + _rng.randi_range(-4, 4), 0, CitySim.N - 1)
						var oi: int = oy * CitySim.N + ox
						if _road_lookup.has(oi):
							found = oi
							break
					if found >= 0:
						target_cell = found
					else:
						target_cell = int(_road_cells[_rng.randi_range(0, _road_cells.size() - 1)])

				var tpos: Vector3 = _cell_world(target_cell)
				p.from = p.to
				p.to = Vector3(
					tpos.x + _rng.randf_range(-3.0, 3.0),
					1.0,
					tpos.z + _rng.randf_range(-3.0, 3.0))

				p.wait = _rng.randf_range(0.3, 2.0)
				p.t = 0.0

		var pos: Vector3 = p.from.lerp(p.to, p.t)
		var dir: Vector3 = (p.to - p.from)
		dir.y = 0.0
		var yaw: float = 0.0
		if dir.length_squared() > 0.001:
			yaw = atan2(dir.x, dir.z)
		var basis := Basis(Vector3.UP, yaw)
		mm.set_instance_transform(k, Transform3D(basis, pos))
		mm.set_instance_color(k, p.color)


func _update_boats(delta: float) -> void:
	if _boats.is_empty() or _river_path.is_empty():
		return
	var mm: MultiMesh = _boats_mm.multimesh

	for k in _boats.size():
		var b: Boat = _boats[k]
		b.path_pos += delta * b.speed * 1.5
		if b.path_pos >= float(_river_path.size()):
			b.path_pos -= float(_river_path.size())

		var i0: int = int(b.path_pos)
		var i1: int = (i0 + 1) % _river_path.size()
		var f: float = b.path_pos - float(i0)

		var a: Vector3 = _cell_world(int(_river_path[i0]))
		var bb: Vector3 = _cell_world(int(_river_path[i1]))
		var pos: Vector3 = a.lerp(bb, f)
		pos.y = 0.6

		var dir: Vector3 = (bb - a)
		dir.y = 0.0
		var yaw: float = 0.0
		if dir.length_squared() > 0.001:
			yaw = atan2(dir.x, dir.z)

		var basis := Basis(Vector3.UP, yaw)
		mm.set_instance_transform(k, Transform3D(basis, pos))
		mm.set_instance_color(k, b.color)
