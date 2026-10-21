class_name CityBuilder
extends Node3D

var sim: CitySim
var mobile: bool = false

# ── static geometry ──────────────────────────────────────────
var _tiles_mm: MultiMeshInstance3D
var _bld_mm: MultiMeshInstance3D
var _harbour_mm: MultiMeshInstance3D
var _stop_mm: MultiMeshInstance3D
var _shelter_mm: MultiMeshInstance3D
var _pole_mm: MultiMeshInstance3D
var _warehouse_mm: MultiMeshInstance3D
var _cap_mm: MultiMeshInstance3D
var _light_pole_mm: MultiMeshInstance3D
var _light_bulb_mm: MultiMeshInstance3D
var _tl_pole_mm: MultiMeshInstance3D
var _tl_bulb_mm: MultiMeshInstance3D

var _tile_mesh: BoxMesh
var _bld_mesh: BoxMesh
var _pier_mesh: BoxMesh
var _warehouse_mesh: BoxMesh
var _stop_mesh: BoxMesh
var _shelter_mesh: BoxMesh
var _pole_mesh: BoxMesh
var _light_pole_mesh: BoxMesh
var _light_bulb_mesh: BoxMesh
var _tl_pole_mesh: BoxMesh
var _tl_bulb_mesh: BoxMesh

var overlay: int = 0
var is_night_mode: bool = false

enum Overlay { NATURAL, AIR, WATER, ENERGY, TRAFFIC, SAFETY, GREEN, POPULATION, LAND_VALUE, WEALTH }

const OVERLAY_NAMES: Array = ["Natural", "Air Quality", "Water Quality", "Energy Load",
	"Traffic", "Safety", "Green Space", "Density", "Land Value", "Wealth"]

var _sun: DirectionalLight3D
var _env: WorldEnvironment

var _bld_cells: PackedInt32Array = PackedInt32Array()
var _tile_xforms: Array[Transform3D] = []
var _bld_night: float = -999.0

var _bld_mat: ShaderMaterial

# ── landmarks ──
var _landmark_root: Node3D
var _landmark_cells: Dictionary = {}

const LANDMARK_PLACEMENTS := [
	{"cell": [12, 10], "kind": "clock_tower"},
	{"cell": [22, 16], "kind": "cathedral"},
	{"cell": [15, 21], "kind": "obelisk"},
	{"cell": [33,  6], "kind": "radio_mast"},
	{"cell": [23,  7], "kind": "spire_tower"},
]

var _stone_mat: ShaderMaterial

# ── agents ───────────────────────────────────────────────────
var _agent_mat: StandardMaterial3D

var _cars_mm: MultiMeshInstance3D
var _buses_mm: MultiMeshInstance3D
var _boats_mm: MultiMeshInstance3D
var _peds_mm: MultiMeshInstance3D

var _car_mesh: BoxMesh
var _bus_mesh: BoxMesh
var _boat_mesh: BoxMesh
var _ped_mesh: BoxMesh

# road graph
var _road_cells: PackedInt32Array = PackedInt32Array()
var _road_neighbors: Array = []
var _road_lookup: Dictionary = {}

# bus stops
var _stop_cells: PackedInt32Array = PackedInt32Array()
var _stop_info: Array = []

# traffic lights
var _tl_cells: PackedInt32Array = PackedInt32Array()
var _tl_state: Array = []

# street lights
var _streetlight_positions: Array = []

# transit routes (buses only)
var _bus_routes: Array = []

# river path
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

class Bus:
	var route: PackedInt32Array
	var route_pos: int = 0
	var t: float = 0.0
	var speed: float = 2.5
	var color: Color = Color.WHITE
	var dwell: float = 0.0
	var passengers: Array = []

class Ped:
	enum State { WALK_TO_STOP, WAIT_AT_STOP, RIDING, WALK_TO_DEST }

	var state: int = State.WALK_TO_STOP
	var from: Vector3 = Vector3.ZERO
	var to: Vector3 = Vector3.ZERO
	var t: float = 0.0
	var speed: float = 1.0
	var wait: float = 0.0
	var color: Color = Color.WHITE
	var yaw: float = 0.0

	var board_stop_rk: int = -1
	var final_dest: Vector3 = Vector3.ZERO
	var riding_vehicle: int = -1
	var ride_offset: Vector3 = Vector3.ZERO

class Boat:
	var path_pos: float = 0.0
	var speed: float = 1.0
	var color: Color = Color.WHITE

var _cars: Array = []
var _buses: Array = []
var _peds: Array = []
var _boats: Array = []

const MAX_CARS := 200
const MAX_BUSES := 24
const MAX_PEDS := 600
const MAX_BOATS := 8

const BUS_STOP_DWELL := 1.6
const BUS_CAPACITY := 12
const DROPOFF_RADIUS := 10.0

const TL_GREEN_TIME := 6.0
const TL_YELLOW_TIME := 1.5
const TL_RED_TIME := 6.0

var _rng := RandomNumberGenerator.new()
var _stop_set: Dictionary = {}
var _stop_waiters: Dictionary = {}
var _tl_set: Dictionary = {}


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
	_apply_day()
	_build_harbour()
	_build_bld_indices()
	_build_road_graph()
	_build_bus_stops()
	_build_traffic_lights()
	_build_street_lights()
	_build_transit_routes()
	_build_river_path()
	_cache_tile_xforms()
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
	vec3 base = COLOR.rgb;
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

	_cap_mm = MultiMeshInstance3D.new()
	var cmm: MultiMesh = MultiMesh.new()
	cmm.transform_format = MultiMesh.TRANSFORM_3D
	cmm.use_colors = true
	cmm.mesh = _bld_mesh
	cmm.instance_count = 0
	_cap_mm.multimesh = cmm
	var cap_mat: StandardMaterial3D = StandardMaterial3D.new()
	cap_mat.vertex_color_use_as_albedo = true
	cap_mat.roughness = 0.55
	cap_mat.metallic = 0.30
	_cap_mm.material_override = cap_mat
	add_child(_cap_mm)

	_pier_mesh = BoxMesh.new()
	_pier_mesh.size = Vector3(6.0, 0.6, 6.0)

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

	# Bus stop marker
	_stop_mesh = BoxMesh.new()
	_stop_mesh.size = Vector3(0.4, 2.0, 0.4)

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

	# Bus shelter roof
	_shelter_mesh = BoxMesh.new()
	_shelter_mesh.size = Vector3(3.4, 0.2, 2.4)

	var shelter_mat := StandardMaterial3D.new()
	shelter_mat.vertex_color_use_as_albedo = true
	shelter_mat.roughness = 0.45
	shelter_mat.metallic = 0.4

	_shelter_mm = MultiMeshInstance3D.new()
	var shmm: MultiMesh = MultiMesh.new()
	shmm.transform_format = MultiMesh.TRANSFORM_3D
	shmm.use_colors = true
	shmm.mesh = _shelter_mesh
	shmm.instance_count = 0
	_shelter_mm.multimesh = shmm
	_shelter_mm.material_override = shelter_mat
	add_child(_shelter_mm)

	# Shelter poles
	_pole_mesh = BoxMesh.new()
	_pole_mesh.size = Vector3(0.15, 2.4, 0.15)

	_pole_mm = MultiMeshInstance3D.new()
	var pmm: MultiMesh = MultiMesh.new()
	pmm.transform_format = MultiMesh.TRANSFORM_3D
	pmm.use_colors = true
	pmm.mesh = _pole_mesh
	pmm.instance_count = 0
	_pole_mm.multimesh = pmm
	_pole_mm.material_override = shelter_mat
	add_child(_pole_mm)

	# Street light pole + bulb
	_light_pole_mesh = BoxMesh.new()
	_light_pole_mesh.size = Vector3(0.18, 4.5, 0.18)

	_light_pole_mm = MultiMeshInstance3D.new()
	var lpmm: MultiMesh = MultiMesh.new()
	lpmm.transform_format = MultiMesh.TRANSFORM_3D
	lpmm.use_colors = true
	lpmm.mesh = _light_pole_mesh
	lpmm.instance_count = 0
	_light_pole_mm.multimesh = lpmm
	var lp_mat := StandardMaterial3D.new()
	lp_mat.vertex_color_use_as_albedo = true
	lp_mat.roughness = 0.55
	lp_mat.metallic = 0.6
	_light_pole_mm.material_override = lp_mat
	add_child(_light_pole_mm)

	_light_bulb_mesh = BoxMesh.new()
	_light_bulb_mesh.size = Vector3(0.8, 0.4, 0.8)

	_light_bulb_mm = MultiMeshInstance3D.new()
	var lbmm: MultiMesh = MultiMesh.new()
	lbmm.transform_format = MultiMesh.TRANSFORM_3D
	lbmm.use_colors = true
	lbmm.mesh = _light_bulb_mesh
	lbmm.instance_count = 0
	_light_bulb_mm.multimesh = lbmm
	var lb_mat := StandardMaterial3D.new()
	lb_mat.vertex_color_use_as_albedo = true
	lb_mat.emission_enabled = true
	lb_mat.emission = Color(1.0, 0.82, 0.40)
	lb_mat.emission_energy_multiplier = 0.15
	lb_mat.roughness = 0.4
	_light_bulb_mm.material_override = lb_mat
	add_child(_light_bulb_mm)

	# Traffic light pole + bulb
	_tl_pole_mesh = BoxMesh.new()
	_tl_pole_mesh.size = Vector3(0.25, 4.0, 0.25)

	_tl_pole_mm = MultiMeshInstance3D.new()
	var tlpm: MultiMesh = MultiMesh.new()
	tlpm.transform_format = MultiMesh.TRANSFORM_3D
	tlpm.use_colors = true
	tlpm.mesh = _tl_pole_mesh
	tlpm.instance_count = 0
	_tl_pole_mm.multimesh = tlpm
	var tlp_mat := StandardMaterial3D.new()
	tlp_mat.vertex_color_use_as_albedo = true
	tlp_mat.roughness = 0.5
	tlp_mat.metallic = 0.7
	_tl_pole_mm.material_override = tlp_mat
	add_child(_tl_pole_mm)

	_tl_bulb_mesh = BoxMesh.new()
	_tl_bulb_mesh.size = Vector3(0.7, 0.7, 0.7)

	_tl_bulb_mm = MultiMeshInstance3D.new()
	var tlbmm: MultiMesh = MultiMesh.new()
	tlbmm.transform_format = MultiMesh.TRANSFORM_3D
	tlbmm.use_colors = true
	tlbmm.mesh = _tl_bulb_mesh
	tlbmm.instance_count = 0
	_tl_bulb_mm.multimesh = tlbmm
	var tlb_mat := StandardMaterial3D.new()
	tlb_mat.vertex_color_use_as_albedo = true
	tlb_mat.emission_enabled = true
	tlb_mat.emission = Color(1, 1, 1)
	tlb_mat.emission_energy_multiplier = 4.0
	tlb_mat.roughness = 0.4
	_tl_bulb_mm.material_override = tlb_mat
	add_child(_tl_bulb_mm)

	_agent_mat = StandardMaterial3D.new()
	_agent_mat.vertex_color_use_as_albedo = true
	_agent_mat.roughness = 0.7
	_agent_mat.specular = 0.2

	_car_mesh = BoxMesh.new()
	_car_mesh.size = Vector3(2.2, 1.4, 4.0)

	_bus_mesh = BoxMesh.new()
	_bus_mesh.size = Vector3(2.6, 2.8, 6.5)

	_boat_mesh = BoxMesh.new()
	_boat_mesh.size = Vector3(4.0, 2.2, 11.0)

	_ped_mesh = BoxMesh.new()
	_ped_mesh.size = Vector3(0.9, 2.0, 0.9)

	_cars_mm  = _make_mm_inst(_car_mesh,  MAX_CARS)
	_buses_mm = _make_mm_inst(_bus_mesh,  MAX_BUSES)
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

		sim.zone[wi] = CitySim.Z.IND
		sim.floors[wi] = 2
		sim.occupancy[wi] = 0.95

		var p: Vector3 = sim.world_pos(wx, wy)
		var wsize: float = CitySim.CELL * 0.85
		wh_xforms.append(Transform3D(
			Basis().scaled(Vector3(wsize, 6.0, wsize)),
			Vector3(p.x, 3.0, p.z)))
		wh_colors.append(Color(0.42, 0.36, 0.28))

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


# ─────────────────────────────────────────────────────────────
#  BUS STOPS
# ─────────────────────────────────────────────────────────────
func _build_bus_stops() -> void:
	_stop_cells.clear()
	_stop_info.clear()
	_stop_set.clear()

	if _road_cells.is_empty():
		return

	var road_count: int = _road_cells.size()

	var candidates: Array = []
	for k in road_count:
		var neigh: Array = _road_neighbors[k]
		var deg: int = neigh.size()
		if deg < 2:
			continue
		var i: int = int(_road_cells[k])
		var x: int = i % CitySim.N
		var y: int = i / CitySim.N
		# Only place stops on arterial roads (the same main grid buses use).
		if x % 8 != 0 and y % 8 != 0:
			continue
		var score: float = float(deg) * 10.0
		if deg >= 3:
			score += 25.0
		var cdist: float = Vector2(float(x - CitySim.N / 2), float(y - CitySim.N / 2)).length()
		score += maxf(0.0, 40.0 - cdist)
		candidates.append([score, k])

	candidates.sort_custom(func(a, b): return a[0] > b[0])

	var min_spacing: float = CitySim.CELL * 7.0
	var target_stops: int = clampi(road_count / 24, 12, 64)

	for cand in candidates:
		if _stop_cells.size() >= target_stops:
			break
		var k: int = int(cand[1])
		var i: int = int(_road_cells[k])
		var x: int = i % CitySim.N
		var y: int = i / CitySim.N
		var wp: Vector3 = sim.world_pos(x, y)
		var ok := true
		for existing in _stop_cells:
			var ei: int = int(_road_cells[int(existing)])
			var ex: int = ei % CitySim.N
			var ey: int = ei / CitySim.N
			var ep: Vector3 = sim.world_pos(ex, ey)
			if Vector2(wp.x - ep.x, wp.z - ep.z).length() < min_spacing:
				ok = false
				break
		if ok:
			_stop_cells.append(k)
			_stop_set[k] = true

			var neigh: Array = _road_neighbors[k]
			var neighbour_i: int = int(_road_cells[int(neigh[0])])
			var nx_w: Vector3 = _cell_world(neighbour_i)
			var dir: Vector3 = (nx_w - wp)
			dir.y = 0.0
			if dir.length_squared() < 0.001:
				dir = Vector3(1, 0, 0)
			dir = dir.normalized()
			var perp := Vector3(-dir.z, 0, dir.x)
			_stop_info.append({
				"road_rk": k,
				"pos": wp + perp * (CitySim.CELL * 0.55),
				"dir": dir,
				"perp": perp,
			})

	var smm: MultiMesh = _stop_mm.multimesh
	var shmm: MultiMesh = _shelter_mm.multimesh
	var pmm: MultiMesh = _pole_mm.multimesh
	smm.instance_count = _stop_info.size()
	shmm.instance_count = _stop_info.size()
	pmm.instance_count = _stop_info.size() * 2

	for idx in _stop_info.size():
		var info: Dictionary = _stop_info[idx]
		var sp: Vector3 = info["pos"]
		var perp: Vector3 = info["perp"]
		var dir: Vector3 = info["dir"]

		smm.set_instance_transform(idx, Transform3D(Basis(), Vector3(sp.x, 1.0, sp.z)))
		smm.set_instance_color(idx, Color(0.55, 0.55, 0.60))

		var yaw: float = atan2(dir.x, dir.z)
		var roof_basis := Basis(Vector3.UP, yaw)
		shmm.set_instance_transform(idx,
			Transform3D(roof_basis, Vector3(sp.x, 2.6, sp.z)))
		shmm.set_instance_color(idx, Color(0.32, 0.42, 0.55))

		var end_a: Vector3 = sp + dir * 1.3
		var end_b: Vector3 = sp - dir * 1.3
		pmm.set_instance_transform(idx * 2,
			Transform3D(Basis(), Vector3(end_a.x, 1.2, end_a.z)))
		pmm.set_instance_color(idx * 2, Color(0.42, 0.44, 0.48))
		pmm.set_instance_transform(idx * 2 + 1,
			Transform3D(Basis(), Vector3(end_b.x, 1.2, end_b.z)))
		pmm.set_instance_color(idx * 2 + 1, Color(0.42, 0.44, 0.48))


# ─────────────────────────────────────────────────────────────
#  TRAFFIC LIGHTS
# ─────────────────────────────────────────────────────────────
func _build_traffic_lights() -> void:
	_tl_cells.clear()
	_tl_state.clear()
	_tl_set.clear()

	if _road_cells.is_empty():
		return

	var candidates: Array = []
	for k in _road_cells.size():
		var neigh: Array = _road_neighbors[k]
		if neigh.size() < 3:
			continue
		candidates.append(k)

	var placed: Array = []
	var min_dist: float = CitySim.CELL * 6.0
	for k in candidates:
		var i: int = int(_road_cells[k])
		var x: int = i % CitySim.N
		var y: int = i / CitySim.N
		var p: Vector3 = sim.world_pos(x, y)
		var too_close := false
		for q in placed:
			var qi: int = int(_road_cells[int(q)])
			var qx: int = qi % CitySim.N
			var qy: int = qi / CitySim.N
			var qp: Vector3 = sim.world_pos(qx, qy)
			if Vector2(p.x - qp.x, p.z - qp.z).length() < min_dist:
				too_close = true
				break
		if not too_close:
			placed.append(k)
			_tl_cells.append(k)
			_tl_set[k] = true
			var phase: int = _rng.randi_range(0, 2)
			var t: float = 0.0
			match phase:
				0: t = 0.0
				1: t = TL_GREEN_TIME
				2: t = TL_GREEN_TIME + TL_YELLOW_TIME
			_tl_state.append({"timer": t})

	var pm: MultiMesh = _tl_pole_mm.multimesh
	var bm: MultiMesh = _tl_bulb_mm.multimesh
	pm.instance_count = _tl_cells.size()
	bm.instance_count = _tl_cells.size()

	for idx in _tl_cells.size():
		var rk: int = int(_tl_cells[idx])
		var i: int = int(_road_cells[rk])
		var x: int = i % CitySim.N
		var y: int = i / CitySim.N
		var p: Vector3 = sim.world_pos(x, y)

		pm.set_instance_transform(idx, Transform3D(Basis(), Vector3(p.x + 2.5, 2.0, p.z + 2.5)))
		pm.set_instance_color(idx, Color(0.28, 0.28, 0.30))

		bm.set_instance_transform(idx, Transform3D(Basis(), Vector3(p.x + 2.5, 4.2, p.z + 2.5)))


# ─────────────────────────────────────────────────────────────
#  STREET LIGHTS
# ─────────────────────────────────────────────────────────────
func _build_street_lights() -> void:
	_streetlight_positions.clear()
	if _road_cells.is_empty():
		return

	var step_cells: int = 4
	var last_placed := Vector2(-9999, -9999)

	for k in range(0, _road_cells.size(), step_cells):
		var rk: int = k
		var i: int = int(_road_cells[rk])
		var x: int = i % CitySim.N
		var y: int = i / CitySim.N
		var p: Vector3 = sim.world_pos(x, y)

		if Vector2(p.x - last_placed.x, p.z - last_placed.y).length() < CitySim.CELL * 2.5:
			continue
		last_placed = Vector2(p.x, p.z)

		var neigh: Array = _road_neighbors[rk]
		var dir := Vector3(1, 0, 0)
		if not neigh.is_empty():
			var nb: int = int(_road_cells[int(neigh[0])])
			var np: Vector3 = _cell_world(nb)
			var d: Vector3 = np - p
			d.y = 0.0
			if d.length_squared() > 0.001:
				dir = d.normalized()
		var perp := Vector3(-dir.z, 0, dir.x)

		_streetlight_positions.append(p + perp * (CitySim.CELL * 0.42))

	var pm: MultiMesh = _light_pole_mm.multimesh
	var bm: MultiMesh = _light_bulb_mm.multimesh
	pm.instance_count = _streetlight_positions.size()
	bm.instance_count = _streetlight_positions.size()

	for idx in _streetlight_positions.size():
		var sp: Vector3 = _streetlight_positions[idx]
		pm.set_instance_transform(idx, Transform3D(Basis(), Vector3(sp.x, 2.25, sp.z)))
		pm.set_instance_color(idx, Color(0.22, 0.22, 0.24))
		bm.set_instance_transform(idx, Transform3D(Basis(), Vector3(sp.x, 4.6, sp.z)))
		bm.set_instance_color(idx, Color(1.0, 0.82, 0.40))


# ─────────────────────────────────────────────────────────────
#  BUS ROUTES — arterial-only, guaranteed loop, no teleporting
# ─────────────────────────────────────────────────────────────
func _build_transit_routes() -> void:
	_bus_routes.clear()

	if _road_cells.is_empty():
		return

	# Buses only run on arterial roads: the main grid lines at x%8==0 or y%8==0.
	# These correspond to the wide roads the city builder generated, so they
	# pass between building blocks, never through them.
	var arterial_cells: Array = []
	for rk in _road_cells.size():
		var i: int = int(_road_cells[rk])
		var x: int = i % CitySim.N
		var y: int = i / CitySim.N
		if x % 8 == 0 or y % 8 == 0:
			arterial_cells.append(rk)

	if arterial_cells.size() < 4:
		return

	# Build a single rectangular loop from the arterial grid corners.
	# Pick the four arterials bounding the city centre: 8 and 32 on each axis.
	var arterial_coords: Array = [8, 16, 24, 32]

	for ai in range(arterial_coords.size() - 1):
		for bi in range(arterial_coords.size() - 1):
			var x0: int = int(arterial_coords[ai])
			var x1: int = int(arterial_coords[ai + 1])
			var y0: int = int(arterial_coords[bi])
			var y1: int = int(arterial_coords[bi + 1])

			var route: PackedInt32Array = PackedInt32Array()

			# Top edge: left to right
			for x in range(x0, x1 + 1):
				var ci: int = y0 * CitySim.N + x
				if _road_lookup.has(ci):
					route.append(_road_lookup[ci])
			# Right edge: top to bottom (skip top corner)
			for y in range(y0 + 1, y1 + 1):
				var ci: int = y * CitySim.N + x1
				if _road_lookup.has(ci):
					route.append(_road_lookup[ci])
			# Bottom edge: right to left (skip right corner)
			for x in range(x1 - 1, x0 - 1, -1):
				var ci: int = y1 * CitySim.N + x
				if _road_lookup.has(ci):
					route.append(_road_lookup[ci])
			# Left edge: bottom to top (skip bottom + top corners)
			for y in range(y1 - 1, y0, -1):
				var ci: int = y * CitySim.N + x0
				if _road_lookup.has(ci):
					route.append(_road_lookup[ci])

			# Only keep closed loops with enough cells to be useful.
			if route.size() < 8:
				continue

			# Sanity: last cell must neighbour first cell on the grid.
			var first_rk: int = int(route[0])
			var last_rk: int = int(route[route.size() - 1])
			var last_neigh: Array = _road_neighbors[last_rk]
			if not last_neigh.has(first_rk):
				continue

			_bus_routes.append(route)


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

	var n_cars: int = clampi(int(pop / 150.0 * (0.6 + 0.7 * congestion)), 30, MAX_CARS)
	for k in n_cars:
		_cars.append(_make_vehicle())

	var bus_palette := [
		Color(0.78, 0.42, 0.15),
		Color(0.30, 0.55, 0.72),
		Color(0.42, 0.65, 0.38),
		Color(0.85, 0.72, 0.30),
	]
	if not _bus_routes.is_empty():
		var total_buses: int = clampi(int(pop / 2800.0) + 3, 3, MAX_BUSES)
		var per_route: int = maxi(1, total_buses / _bus_routes.size())
		var made: int = 0
		for r_i in _bus_routes.size():
			var route: PackedInt32Array = _bus_routes[r_i]
			var buses_here: int = maxi(1, per_route)
			for b_i in buses_here:
				if made >= MAX_BUSES:
					break
				var b := _make_bus(route, r_i, b_i)
				b.color = bus_palette[r_i % bus_palette.size()]
				_buses.append(b)
				made += 1
			if made >= MAX_BUSES:
				break

	var n_peds: int = clampi(int(pop / 22.0), 80, MAX_PEDS)
	for k in n_peds:
		_peds.append(_spawn_ped())

	var trade: float = maxf(sim.s["exports_value"], sim.s["imports_value"])
	var n_boats: int = clampi(3 + int(trade / 18000.0), 3, MAX_BOATS)
	for k in n_boats:
		_boats.append(_make_boat(k))

	_cars_mm.multimesh.instance_count = _cars.size()
	_buses_mm.multimesh.instance_count = _buses.size()
	_peds_mm.multimesh.instance_count = _peds.size()
	_boats_mm.multimesh.instance_count = _boats.size()


func _random_vehicle_color() -> Color:
	var palette := [
		Color(0.75, 0.15, 0.15),
		Color(0.20, 0.32, 0.72),
		Color(0.24, 0.24, 0.26),
		Color(0.88, 0.88, 0.90),
		Color(0.55, 0.58, 0.62),
		Color(0.85, 0.72, 0.30),
		Color(0.30, 0.55, 0.35),
		Color(0.65, 0.35, 0.15),
	]
	return palette[_rng.randi_range(0, palette.size() - 1)]

func _make_vehicle() -> Car:
	var c := Car.new()

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

	_choose_next_car(c)
	c.prev_cell_idx = -1
	return c


func _choose_next_car(c: Car) -> void:
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


func _make_bus(route: PackedInt32Array, route_id: int, bus_idx: int) -> Bus:
	var b := Bus.new()
	b.route = route
	var offset: int = (bus_idx * maxi(1, int(route.size() / 4))) % route.size()
	b.route_pos = offset
	b.t = _rng.randf() * 0.5
	b.speed = _rng.randf_range(1.6, 2.4)
	b.dwell = 0.0
	b.color = Color(0.80, 0.45, 0.20)
	b.passengers = []
	return b


func _random_person_color() -> Color:
	var palette := [
		Color(0.18, 0.20, 0.26),
		Color(0.30, 0.26, 0.22),
		Color(0.55, 0.55, 0.58),
		Color(0.72, 0.68, 0.62),
		Color(0.75, 0.30, 0.28),
		Color(0.24, 0.42, 0.62),
		Color(0.42, 0.55, 0.36),
		Color(0.62, 0.42, 0.30),
		Color(0.85, 0.78, 0.62),
		Color(0.42, 0.28, 0.42),
	]
	return palette[_rng.randi_range(0, palette.size() - 1)]


func _spawn_ped() -> Ped:
	var p := Ped.new()
	p.color = _random_person_color()
	p.speed = _rng.randf_range(0.9, 1.6)

	var start_rk: int = -1
	if not _stop_cells.is_empty() and _rng.randf() < 0.6:
		start_rk = int(_stop_cells[_rng.randi_range(0, _stop_cells.size() - 1)])
	else:
		start_rk = _rng.randi_range(0, _road_cells.size() - 1)

	var dest_rk: int = -1
	if not _stop_cells.is_empty():
		var tries := 0
		while tries < 12:
			var cand: int = int(_stop_cells[_rng.randi_range(0, _stop_cells.size() - 1)])
			if cand != start_rk:
				dest_rk = cand
				break
			tries += 1

	if dest_rk < 0:
		var a: Vector3 = _cell_world(int(_road_cells[start_rk]))
		p.from = Vector3(a.x + _rng.randf_range(-3.0, 3.0), 1.0, a.z + _rng.randf_range(-3.0, 3.0))
		var b: Vector3 = _cell_world(int(_road_cells[_rng.randi_range(0, _road_cells.size() - 1)]))
		p.to = Vector3(b.x + _rng.randf_range(-3.0, 3.0), 1.0, b.z + _rng.randf_range(-3.0, 3.0))
		p.state = Ped.State.WALK_TO_DEST
		p.t = _rng.randf() * 0.5
		p.wait = 0.0
		return p

	var origin_world: Vector3 = _cell_world(int(_road_cells[start_rk]))
	var dest_world: Vector3 = _cell_world(int(_road_cells[dest_rk]))

	p.board_stop_rk = start_rk
	p.final_dest = Vector3(
		dest_world.x + _rng.randf_range(-6.0, 6.0),
		1.0,
		dest_world.z + _rng.randf_range(-6.0, 6.0))

	var angle: float = _rng.randf() * TAU
	var walk_cells: float = _rng.randf_range(1.5, 3.0)
	var walk_dist: float = walk_cells * CitySim.CELL
	p.from = Vector3(
		origin_world.x + cos(angle) * walk_dist,
		1.0,
		origin_world.z + sin(angle) * walk_dist)
	p.to = origin_world
	p.t = 0.0
	p.wait = 0.0
	p.state = Ped.State.WALK_TO_STOP
	p.color = _random_person_color()

	return p

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
#  DAY / NIGHT APPLY
# ─────────────────────────────────────────────────────────────
func _apply_day() -> void:
	if _sun == null:
		return
	_sun.rotation_degrees = Vector3(-52.0, 115.0, 0.0)
	_sun.light_energy = 1.20
	_sun.light_color = Color(1.0, 0.96, 0.88)
	if _env:
		var e: Environment = _env.environment
		e.ambient_light_energy = 0.65 if mobile else 0.55
		if not mobile:
			e.fog_light_color = Color(0.42, 0.50, 0.62)
	if _bld_mat:
		_bld_mat.set_shader_parameter("night", 0.0)
	if _stone_mat:
		_stone_mat.set_shader_parameter("night", 0.0)
	if _light_bulb_mm != null and _light_bulb_mm.material_override is StandardMaterial3D:
		var lb: StandardMaterial3D = _light_bulb_mm.material_override
		lb.emission_energy_multiplier = 0.15

func _apply_night() -> void:
	if _sun == null:
		return
	_sun.rotation_degrees = Vector3(-35.0, 115.0, 0.0)
	_sun.light_energy = 0.10
	_sun.light_color = Color(0.55, 0.62, 0.86)
	if _env:
		var e: Environment = _env.environment
		e.ambient_light_energy = 0.22
		if not mobile:
			e.fog_light_color = Color(0.06, 0.08, 0.14)
	if _bld_mat:
		_bld_mat.set_shader_parameter("night", 1.0)
	if _stone_mat:
		_stone_mat.set_shader_parameter("night", 1.0)
	if _light_bulb_mm != null and _light_bulb_mm.material_override is StandardMaterial3D:
		var lb: StandardMaterial3D = _light_bulb_mm.material_override
		lb.emission_energy_multiplier = 2.5

func set_day_mode(night: bool) -> void:
	is_night_mode = night
	if night:
		_apply_night()
	else:
		_apply_day()
	_refresh_buildings()


# ─────────────────────────────────────────────────────────────
#  REFRESH
# ─────────────────────────────────────────────────────────────
func refresh_all() -> void:
	_refresh_tiles()
	_refresh_buildings()
	if is_night_mode:
		_apply_night()
	else:
		_apply_day()

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
		Overlay.WEALTH:
			v = sim.wealth[i]
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
	var night: float = 1.0 if is_night_mode else 0.0
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

		bmm.set_instance_transform(idx,
			Transform3D(Basis().scaled(Vector3(fw, h, fw)),
				Vector3(o.x, h * 0.5, o.z)))

		var base: Color = _building_base_color(i)
		var lit: float = night * sim.occupancy[i]
		var c: Color = base.lerp(lit_color, lit * 0.48)
		c = c * (1.0 - 0.45 * night) + dark_color * (0.45 * night)
		bmm.set_instance_color(idx, c)

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
	return 1.0 if is_night_mode else 0.0

func _refresh_sun() -> void:
	if is_night_mode:
		_apply_night()
	else:
		_apply_day()

func refresh_buildings_smooth() -> void:
	if is_night_mode:
		return
	var n: float = _night_factor()
	var threshold: float = 0.02 if mobile else 0.008
	if absf(n - _bld_night) > threshold:
		_refresh_buildings()
		_bld_night = n

func night_factor() -> float:
	return _night_factor()


func set_overlay(o: int) -> void:
	overlay = o
	_refresh_tiles()


# ─────────────────────────────────────────────────────────────
#  AGENT UPDATE
# ─────────────────────────────────────────────────────────────
func tick_agents(delta: float, hours_per_second: float) -> void:
	if hours_per_second <= 0.0:
		return
	var scale: float = clampf(hours_per_second / 3.0, 0.2, 4.0)
	var d: float = delta * scale

	_update_traffic_lights(d)
	_update_cars(_cars, _cars_mm, d, 1.0)
	_update_buses(d)
	_update_peds(d)
	_update_boats(d)


# ── TRAFFIC LIGHTS ─────────────────────────────────────────
func _update_traffic_lights(delta: float) -> void:
	if _tl_state.is_empty():
		return
	var bm: MultiMesh = _tl_bulb_mm.multimesh

	for idx in _tl_state.size():
		var state: Dictionary = _tl_state[idx]
		var timer: float = state["timer"] + delta
		var cycle: float = TL_GREEN_TIME + TL_YELLOW_TIME + TL_RED_TIME
		if timer >= cycle:
			timer -= cycle
		state["timer"] = timer

		var col: Color
		if timer < TL_GREEN_TIME:
			col = Color(0.10, 1.00, 0.20)
		elif timer < TL_GREEN_TIME + TL_YELLOW_TIME:
			col = Color(1.00, 0.90, 0.10)
		else:
			col = Color(1.00, 0.10, 0.10)

		bm.set_instance_color(idx, col)


func _is_light_green(road_rk: int) -> bool:
	if not _tl_set.has(road_rk):
		return true
	for idx in _tl_cells.size():
		if int(_tl_cells[idx]) == road_rk:
			var state: Dictionary = _tl_state[idx]
			var timer: float = state["timer"]
			return timer < TL_GREEN_TIME
	return true


# ── CARS ────────────────────────────────────────────────────
func _update_cars(arr: Array, mmi: MultiMeshInstance3D, delta: float, speed_mult: float) -> void:
	if arr.is_empty():
		return
	var mm: MultiMesh = mmi.multimesh
	var congestion: float = clampf(sim.s["traffic_congestion"], 0.0, 1.0)
	var cong_slow: float = clampf(1.0 - 0.7 * congestion, 0.15, 1.0)
	var night: float = _night_factor()

	for k in arr.size():
		var c: Car = arr[k]

		if c.t > 0.75 and _tl_set.has(c.next_cell_idx):
			if not _is_light_green(c.next_cell_idx):
				c.t = 0.75

		if c.turn > 0.0:
			c.turn -= delta
		else:
			c.t += delta * c.speed * speed_mult * cong_slow
			if c.t >= 1.0:
				c.t = 0.0
				c.prev_cell_idx = c.cell_idx
				c.cell_idx = c.next_cell_idx
				_choose_next_car(c)
				if _rng.randf() < 0.12:
					c.turn = _rng.randf_range(0.2, 0.7)

		var a: Vector3 = _cell_world(c.cell_idx)
		var b: Vector3 = _cell_world(c.next_cell_idx)
		var pos: Vector3 = a.lerp(b, clampf(c.t, 0.05, 0.95))
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


# ── BUSES (arterial loop) ─────────────────────────────────
func _update_buses(delta: float) -> void:
	if _buses.is_empty():
		return
	var mm: MultiMesh = _buses_mm.multimesh
	var pmm: MultiMesh = _peds_mm.multimesh
	var congestion: float = clampf(sim.s["traffic_congestion"], 0.0, 1.0)
	var cong_slow: float = clampf(1.0 - 0.5 * congestion, 0.35, 1.0)
	var night: float = _night_factor()

	for k in _buses.size():
		var b: Bus = _buses[k]
		var rsize: int = b.route.size()
		if rsize < 2:
			continue

		var prev_pos: int = b.route_pos
		var next_pos: int = (b.route_pos + 1) % rsize
		var prev_rk: int = int(b.route[prev_pos])
		var next_rk: int = int(b.route[next_pos])

		if b.dwell > 0.0:
			b.dwell -= delta
			b.t = 0.0
		else:
			b.t += delta * b.speed * cong_slow
			if b.t >= 1.0:
				b.t -= 1.0
				b.route_pos = next_pos
				var arrived_rk: int = int(b.route[b.route_pos])
				if _stop_set.has(arrived_rk):
					b.dwell = BUS_STOP_DWELL
					_do_alighting(arrived_rk, k)
					_do_boarding(arrived_rk, k)

		var a: Vector3 = _cell_world(int(_road_cells[prev_rk]))
		var bpos: Vector3 = _cell_world(int(_road_cells[next_rk]))
		var pos: Vector3 = a.lerp(bpos, clampf(b.t, 0.05, 0.95))
		pos.y = 1.6

		var dir: Vector3 = (bpos - a)
		dir.y = 0.0
		var yaw: float = 0.0
		if dir.length_squared() > 0.001:
			yaw = atan2(dir.x, dir.z)

		var basis := Basis(Vector3.UP, yaw)
		mm.set_instance_transform(k, Transform3D(basis, pos))

		var glow: float = clampf(b.dwell / BUS_STOP_DWELL, 0.0, 1.0) * 0.5
		var col: Color = b.color.lerp(Color(1.0, 0.90, 0.60), night * 0.35 + glow)
		mm.set_instance_color(k, col)

		for ped_i in b.passengers:
			var p: Ped = _peds[ped_i]
			var off: Vector3 = basis * p.ride_offset
			var ppos: Vector3 = pos + off
			ppos.y = 1.2
			pmm.set_instance_transform(ped_i, Transform3D(Basis(Vector3.UP, yaw), ppos))
			pmm.set_instance_color(ped_i, p.color)


func _do_boarding(stop_rk: int, vehicle_idx: int) -> void:
	if not _stop_waiters.has(stop_rk):
		return
	var queue: Array = _stop_waiters[stop_rk]
	if queue.is_empty():
		return

	var stop_world: Vector3 = _cell_world(int(_road_cells[stop_rk]))
	var boarded: int = 0

	for qi in range(queue.size() - 1, -1, -1):
		if boarded >= BUS_CAPACITY:
			break
		var ped_i: int = int(queue[qi])
		var p: Ped = _peds[ped_i]

		var d_dest: float = Vector2(p.final_dest.x - stop_world.x, p.final_dest.z - stop_world.z).length()
		if d_dest < 6.0:
			p.state = Ped.State.WALK_TO_DEST
			p.from = Vector3(stop_world.x, 1.0, stop_world.z)
			p.to = p.final_dest
			p.t = 0.0
			queue.remove_at(qi)
			continue

		p.state = Ped.State.RIDING
		p.riding_vehicle = vehicle_idx
		p.ride_offset = Vector3(
			_rng.randf_range(-0.7, 0.7),
			0.0,
			_rng.randf_range(-2.5, 2.5))
		p.wait = 0.0

		queue.remove_at(qi)
		boarded += 1
		_buses[vehicle_idx].passengers.append(ped_i)

	if boarded > 0:
		sim.s["transit_share"] = clampf(sim.s["transit_share"] + 0.0006 * float(boarded), 0.0, 1.0)


func _do_alighting(stop_rk: int, vehicle_idx: int) -> void:
	var veh_passengers: Array = _buses[vehicle_idx].passengers
	if veh_passengers.is_empty():
		return

	var stop_world: Vector3 = _cell_world(int(_road_cells[stop_rk]))

	for pi in range(veh_passengers.size() - 1, -1, -1):
		var ped_i: int = int(veh_passengers[pi])
		var p: Ped = _peds[ped_i]
		var d: float = Vector2(p.final_dest.x - stop_world.x, p.final_dest.z - stop_world.z).length()
		if d <= DROPOFF_RADIUS:
			p.state = Ped.State.WALK_TO_DEST
			var off_a: float = _rng.randf() * TAU
			var off_d: float = _rng.randf_range(1.5, 3.0) * CitySim.CELL
			p.from = Vector3(
				stop_world.x + cos(off_a) * off_d,
				1.0,
				stop_world.z + sin(off_a) * off_d)
			p.to = p.final_dest
			p.t = 0.0
			p.wait = 0.0
			p.riding_vehicle = -1
			p.ride_offset = Vector3.ZERO
			veh_passengers.remove_at(pi)


func _cell_world(i: int) -> Vector3:
	var x: int = i % CitySim.N
	var y: int = i / CitySim.N
	return sim.world_pos(x, y)


# ── PEDESTRIANS ─────────────────────────────────────────────
func _update_peds(delta: float) -> void:
	if _peds.is_empty():
		return
	var mm: MultiMesh = _peds_mm.multimesh

	for k in _peds.size():
		var p: Ped = _peds[k]

		match p.state:
			Ped.State.WALK_TO_STOP:
				_step_ped_walk(p, delta)
				if p.t >= 1.0:
					if p.board_stop_rk >= 0:
						if not _stop_waiters.has(p.board_stop_rk):
							_stop_waiters[p.board_stop_rk] = []
						if not _stop_waiters[p.board_stop_rk].has(k):
							_stop_waiters[p.board_stop_rk].append(k)
					p.state = Ped.State.WAIT_AT_STOP
					p.t = 0.0
					p.wait = 0.0

			Ped.State.WAIT_AT_STOP:
				var boarded := false
				if p.board_stop_rk >= 0:
					var wlist: Array = _stop_waiters.get(p.board_stop_rk, [])
					if not wlist.has(k):
						p.state = Ped.State.RIDING
						boarded = true
				if not boarded:
					var stop_world: Vector3 = _cell_world(int(_road_cells[p.board_stop_rk]))
					var angle: float = float(k) * 0.7
					var jitter_x: float = cos(angle) * 1.4
					var jitter_z: float = sin(angle) * 1.4
					p.from = Vector3(stop_world.x + jitter_x, 1.0, stop_world.z + jitter_z)
					p.to = p.from

			Ped.State.RIDING:
				pass

			Ped.State.WALK_TO_DEST:
				_step_ped_walk(p, delta)
				if p.t >= 1.0:
					var fresh: Ped = _spawn_ped()
					p.state = fresh.state
					p.from = fresh.from
					p.to = fresh.to
					p.t = fresh.t
					p.speed = fresh.speed
					p.wait = fresh.wait
					p.color = fresh.color
					p.board_stop_rk = fresh.board_stop_rk
					p.final_dest = fresh.final_dest
					p.riding_vehicle = -1
					p.ride_offset = Vector3.ZERO

		if p.state == Ped.State.RIDING:
			continue

		var pos: Vector3 = p.from.lerp(p.to, clampf(p.t, 0.0, 1.0))
		var dir: Vector3 = (p.to - p.from)
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			p.yaw = atan2(dir.x, dir.z)
		var basis := Basis(Vector3.UP, p.yaw)
		mm.set_instance_transform(k, Transform3D(basis, pos))
		mm.set_instance_color(k, p.color)


func _step_ped_walk(p: Ped, delta: float) -> void:
	if p.wait > 0.0:
		p.wait -= delta
		return
	var dist: float = Vector2(p.to.x - p.from.x, p.to.z - p.from.z).length()
	if dist < 0.05:
		p.t = 1.0
		return
	p.t += delta * p.speed / max(dist, 0.5)


# ── BOATS ───────────────────────────────────────────────────
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
