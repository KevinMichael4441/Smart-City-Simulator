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
var _footpath_mm: MultiMeshInstance3D
var _zebra_mm: MultiMeshInstance3D

var _tile_mesh: BoxMesh
var _bld_mesh: BoxMesh
var _pier_mesh: BoxMesh
var _warehouse_mesh: BoxMesh
var _stop_mesh: BoxMesh
var _footpath_mesh: BoxMesh
var _zebra_mesh: BoxMesh

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
var _bld_jitter: PackedFloat32Array = PackedFloat32Array()

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
var _road_neighbors: Array = []
var _road_lookup: Dictionary = {}
var _stop_cells: PackedInt32Array = PackedInt32Array()
var _river_path: PackedInt32Array = PackedInt32Array()
var _harbour_origin: Vector2i = Vector2i(-1, -1)
var _pier_cells: PackedInt32Array = PackedInt32Array()

# weather particles
var _rain_particles: CPUParticles3D
var _snow_particles: CPUParticles3D
var weather_visuals_enabled := true

# ── day / night toggle ──────────────────────────────────────
var is_night_mode := false

# ── traffic lights ─────────────────────────────────────────
var _intersection_cells: PackedInt32Array = PackedInt32Array()
var _light_phases: PackedFloat32Array = PackedFloat32Array()
var _light_pole_mm: MultiMeshInstance3D
var _light_bulb_mm: MultiMeshInstance3D
var _light_pole_mesh: BoxMesh
var _light_bulb_mesh: BoxMesh

const LIGHT_GREEN_TIME := 6.0
const LIGHT_YELLOW_TIME := 1.5
const LIGHT_RED_TIME := 6.0
const LIGHT_CYCLE := 15.0

# ── lane / footpath geometry ────────────────────────────────
const ROAD_HALF := 10.0
const CAR_LANE_OFFSET := 4.5
const CAR_LANE_HALF := 3.25
const FOOTPATH_OFFSET := 8.0
const FOOTPATH_HALF := 1.0

const VEHICLE_MIN_GAP := 0.80
const STUCK_THRESHOLD := 3.0

const PED_CROSS_TIME := 4.0
const PED_WAIT_MAX := 5.0

enum LightPhase { GREEN_NS, YELLOW_NS, RED_NS, GREEN_EW, YELLOW_EW, RED_EW }

class Car:
	var cell_idx: int = 0
	var prev_cell_idx: int = -1
	var next_cell_idx: int = 0
	var t: float = 0.0
	var speed: float = 3.0
	var turn: float = 0.0
	var color: Color = Color.WHITE
	var stuck_time: float = 0.0

class Ped:
	var from: Vector3 = Vector3.ZERO
	var to: Vector3 = Vector3.ZERO
	var t: float = 0.0
	var speed: float = 1.0
	var wait: float = 0.0
	var color: Color = Color.WHITE
	var stuck_time: float = 0.0
	var heading_x: bool = true
	# cross_state: 0 = walking, 1 = waiting at zebra, 2 = crossing
	var cross_state: int = 0
	var cross_from: Vector3 = Vector3.ZERO
	var cross_to: Vector3 = Vector3.ZERO
	var cross_t: float = 0.0

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

	is_night_mode = false

	_build_environment()
	_build_materials()
	_build_meshes()
	_build_weather_particles()
	_build_harbour()
	_build_bld_indices()
	_build_road_graph()
	_build_footpaths_and_zebras()
	_build_river_path()
	_cache_tile_xforms()
	_build_bld_jitter()
	_build_landmarks()
	_build_traffic_lights()
	refresh_all()
	_seed_agents()
	_apply_day_night()

func _build_materials() -> void:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode cull_disabled, specular_schlick_ggx;\nuniform float night : hint_range(0.0, 1.0) = 0.0;\nvoid fragment() {\n\tvec3 base = COLOR.rgb;\n\tvec3 c = base * mix(1.0, 0.42, night);\n\tc *= mix(vec3(1.0), vec3(0.62, 0.70, 0.86), night);\n\tALBEDO = c;\n\tROUGHNESS = 0.82;\n\tSPECULAR = 0.30;\n}\n"
	_stone_mat = ShaderMaterial.new()
	_stone_mat.shader = sh

func _make_window_shader() -> Shader:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;\nuniform float night : hint_range(0.0, 1.0) = 0.0;\nuniform float flicker_speed : hint_range(0.0, 2.0) = 0.35;\nuniform vec3 lit_color_warm : source_color = vec3(1.0, 0.82, 0.48);\nuniform vec3 lit_color_cool : source_color = vec3(0.80, 0.90, 1.00);\nuniform vec2 window_density = vec2(6.0, 9.0);\nuniform vec2 window_size = vec2(0.62, 0.52);\nuniform float lit_density : hint_range(0.0, 1.0) = 0.55;\nuniform float emission_strength : hint_range(0.0, 6.0) = 2.2;\nvarying vec3 v_instance_color;\nvarying float v_time;\nvoid vertex() {\n\tv_instance_color = COLOR.rgb;\n\tv_time = TIME * flicker_speed;\n}\nfloat hash21(vec2 p) {\n\tp = fract(p * vec2(233.34, 951.73));\n\tp += dot(p, p + 23.45);\n\treturn fract(p.x * p.y);\n}\nvoid fragment() {\n\tvec2 uv = UV;\n\tfloat is_side = 1.0 - step(0.7, abs(NORMAL.y));\n\tvec2 grid = uv * window_density;\n\tvec2 cell = floor(grid);\n\tvec2 local = fract(grid);\n\tvec2 d = abs(local - 0.5);\n\tvec2 half_size = window_size * 0.5;\n\tfloat in_window = step(d.x, half_size.x) * step(d.y, half_size.y) * is_side;\n\tfloat seed = dot(v_instance_color, vec3(37.1, 91.7, 17.3));\n\tfloat r_static = hash21(cell + vec2(seed, seed * 0.37));\n\tfloat phase = r_static * 6.2831 + seed;\n\tfloat freq = 0.7 + 0.6 * hash21(cell * 1.7 + seed);\n\tfloat osc = sin(v_time * freq + phase);\n\tfloat thresh = 1.0 - lit_density * 2.0;\n\tfloat on = step(thresh, osc);\n\tfloat warmness = v_instance_color.r;\n\tvec3 window_on_color = mix(lit_color_cool, lit_color_warm, warmness);\n\tvec3 facade = v_instance_color * 0.45;\n\tvec3 albedo = mix(facade, facade * 0.5, in_window);\n\talbedo = mix(albedo, window_on_color, in_window * on * night * 0.6);\n\tvec3 emis = window_on_color * in_window * on * night * emission_strength;\n\tALBEDO = albedo;\n\tEMISSION = emis;\n\tROUGHNESS = 0.62;\n\tMETALLIC = 0.05;\n\tSPECULAR = 0.35;\n}\n"
	return sh

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
	if mobile: shadow_dist = 600.0
	_sun.directional_shadow_max_distance = shadow_dist
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(_sun)

func _build_meshes() -> void:
	_tile_mesh = BoxMesh.new()
	_tile_mesh.size = Vector3(CitySim.CELL, 0.35, CitySim.CELL)

	var tmat: StandardMaterial3D = StandardMaterial3D.new()
	tmat.vertex_color_use_as_albedo = true
	tmat.roughness = 0.95

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

	var pier_mat: StandardMaterial3D = StandardMaterial3D.new()
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

	var wh_mat: StandardMaterial3D = StandardMaterial3D.new()
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

	_stop_mesh = BoxMesh.new()
	_stop_mesh.size = Vector3(1.4, 2.2, 1.4)

	var stop_mat: StandardMaterial3D = StandardMaterial3D.new()
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

	# ── footpath strips ──
	# Raised ABOVE the road tile (which is 0.35 tall) so they're visible.
	_footpath_mesh = BoxMesh.new()
	_footpath_mesh.size = Vector3(CitySim.CELL, 0.55, FOOTPATH_HALF * 2.0)

	var fp_mat: StandardMaterial3D = StandardMaterial3D.new()
	fp_mat.vertex_color_use_as_albedo = true
	fp_mat.roughness = 0.85

	_footpath_mm = MultiMeshInstance3D.new()
	var fpmm: MultiMesh = MultiMesh.new()
	fpmm.transform_format = MultiMesh.TRANSFORM_3D
	fpmm.use_colors = true
	fpmm.mesh = _footpath_mesh
	fpmm.instance_count = 0
	_footpath_mm.multimesh = fpmm
	_footpath_mm.material_override = fp_mat
	add_child(_footpath_mm)

	# ── zebra crossings ──
	_zebra_mesh = BoxMesh.new()
	_zebra_mesh.size = Vector3(CAR_LANE_HALF * 2.0 + FOOTPATH_HALF * 2.0, 0.06, 2.2)

	var zb_mat: StandardMaterial3D = StandardMaterial3D.new()
	zb_mat.vertex_color_use_as_albedo = true
	zb_mat.roughness = 0.7

	_zebra_mm = MultiMeshInstance3D.new()
	var zbmm: MultiMesh = MultiMesh.new()
	zbmm.transform_format = MultiMesh.TRANSFORM_3D
	zbmm.use_colors = true
	zbmm.mesh = _zebra_mesh
	zbmm.instance_count = 0
	_zebra_mm.multimesh = zbmm
	_zebra_mm.material_override = zb_mat
	add_child(_zebra_mm)

	_agent_mat = StandardMaterial3D.new()
	_agent_mat.vertex_color_use_as_albedo = true
	_agent_mat.roughness = 0.7

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

func _build_weather_particles() -> void:
	var amount_rain := 800 if mobile else 2500
	var amount_snow := 400 if mobile else 1200

	_rain_particles = CPUParticles3D.new()
	_rain_particles.amount = amount_rain
	_rain_particles.lifetime = 1.2
	_rain_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain_particles.emission_box_extents = Vector3(400, 0, 400)
	_rain_particles.direction = Vector3(0, -1, 0)
	_rain_particles.spread = 5.0
	_rain_particles.initial_velocity_min = 40.0
	_rain_particles.initial_velocity_max = 60.0
	_rain_particles.gravity = Vector3(0, -30, 0)
	var rain_mesh := BoxMesh.new()
	rain_mesh.size = Vector3(0.2, 2.0, 0.2)
	_rain_particles.mesh = rain_mesh
	var rain_mat := StandardMaterial3D.new()
	rain_mat.albedo_color = Color(0.6, 0.7, 0.9, 0.4)
	rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_particles.material_override = rain_mat
	_rain_particles.position = Vector3(0, 150, 0)
	_rain_particles.emitting = false
	add_child(_rain_particles)

	_snow_particles = CPUParticles3D.new()
	_snow_particles.amount = amount_snow
	_snow_particles.lifetime = 8.0
	_snow_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_snow_particles.emission_box_extents = Vector3(400, 0, 400)
	_snow_particles.direction = Vector3(0, -1, 0)
	_snow_particles.spread = 20.0
	_snow_particles.initial_velocity_min = 2.0
	_snow_particles.initial_velocity_max = 5.0
	_snow_particles.gravity = Vector3(0, -1.5, 0)
	_snow_particles.scale_amount_min = 0.5
	_snow_particles.scale_amount_max = 1.5
	var snow_mesh := BoxMesh.new()
	snow_mesh.size = Vector3(0.5, 0.5, 0.5)
	_snow_particles.mesh = snow_mesh
	var snow_mat := StandardMaterial3D.new()
	snow_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.8)
	snow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	snow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_snow_particles.material_override = snow_mat
	_snow_particles.position = Vector3(0, 150, 0)
	_snow_particles.emitting = false
	add_child(_snow_particles)

func set_weather_visuals(enabled: bool) -> void:
	weather_visuals_enabled = enabled
	if not enabled:
		_rain_particles.emitting = false
		_snow_particles.emitting = false
	else:
		_apply_weather_particles()

# ─────────────────────────────────────────────────────────────
#  HARBOUR / ROAD GRAPH / FOOTPATHS / ZEBRAS / RIVER / LANDMARKS
# ─────────────────────────────────────────────────────────────
func _build_harbour() -> void:
	var best_x := -1
	var best_y := -1
	var best_score := -1

	for x in CitySim.N:
		for y in CitySim.N:
			var i: int = y * CitySim.N + x
			if sim.terrain[i] != CitySim.T.WATER: continue
			var land_count := 0
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or ny < 0 or nx >= CitySim.N or ny >= CitySim.N: continue
					if sim.terrain[ny * CitySim.N + nx] == CitySim.T.LAND:
						land_count += 1
			var centre_bonus: int = -abs(x - CitySim.N / 2)
			var score := land_count + centre_bonus
			if score > best_score:
				best_score = score
				best_x = x
				best_y = y

	if best_x < 0: return

	_harbour_origin = Vector2i(best_x, best_y)
	_pier_cells.clear()
	var pier_xforms: Array = []
	var pier_colors: Array = []

	for k in 3:
		var px: int = best_x - 2 + k * 2
		var py: int = best_y - 1
		if px < 0 or py < 0 or px >= CitySim.N or py >= CitySim.N: continue
		var pi: int = py * CitySim.N + px
		if sim.terrain[pi] != CitySim.T.WATER: continue
		var p: Vector3 = sim.world_pos(px, py)
		pier_xforms.append(Transform3D(Basis().scaled(Vector3(1.0, 1.0, 1.0)), Vector3(p.x, 0.3, p.z)))
		pier_colors.append(Color(0.30, 0.28, 0.24))
		_pier_cells.append(pi)

	var wh_xforms: Array = []
	var wh_colors: Array = []

	for k in 3:
		var wx: int = best_x - 3 + k * 3
		var wy: int = best_y - 3
		if wx < 0 or wy < 0 or wx >= CitySim.N or wy >= CitySim.N: continue
		var wi: int = wy * CitySim.N + wx
		if sim.terrain[wi] != CitySim.T.LAND: continue
		if sim.util[wi] != CitySim.U.NONE: continue

		sim.zone[wi] = CitySim.Z.IND
		sim.floors[wi] = 2
		sim.occupancy[wi] = 0.95

		var p: Vector3 = sim.world_pos(wx, wy)
		var wsize: float = CitySim.CELL * 0.85
		wh_xforms.append(Transform3D(Basis().scaled(Vector3(wsize, 6.0, wsize)), Vector3(p.x, 3.0, p.z)))
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

func _build_road_graph() -> void:
	_road_cells.clear()
	_road_lookup.clear()
	for i in CitySim.CELLS:
		if sim.terrain[i] == CitySim.T.ROAD:
			_road_lookup[i] = _road_cells.size()
			_road_cells.append(i)

	_road_neighbors.clear()
	_road_neighbors.resize(_road_cells.size())

	var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	for k in _road_cells.size():
		var i: int = int(_road_cells[k])
		var x: int = i % CitySim.N
		var y: int = i / CitySim.N
		var n: Array = []
		for off in offsets:
			var nx: int = x + off.x
			var ny: int = y + off.y
			if nx < 0 or ny < 0 or nx >= CitySim.N or ny >= CitySim.N: continue
			var ni: int = ny * CitySim.N + nx
			if _road_lookup.has(ni): n.append(_road_lookup[ni])
		_road_neighbors[k] = n

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
#  FOOTPATHS AND ZEBRA CROSSINGS — visual geometry
# ─────────────────────────────────────────────────────────────
func _build_footpaths_and_zebras() -> void:
	var fp_xforms: Array = []
	var fp_colors: Array = []
	var z_xforms: Array = []
	var z_colors: Array = []

	var fp_color := Color(0.62, 0.61, 0.58)
	var zebra_color := Color(0.95, 0.95, 0.92)

	for y in CitySim.N:
		for x in CitySim.N:
			var i: int = y * CitySim.N + x
			if sim.terrain[i] != CitySim.T.ROAD: continue
			var p: Vector3 = sim.world_pos(x, y)

			# Footpaths on the outer band of each road cell (where no road continues).
			if y == 0 or sim.terrain[i - CitySim.N] != CitySim.T.ROAD:
				fp_xforms.append(Transform3D(
					Basis(),
					Vector3(p.x, 0.28, p.z - FOOTPATH_OFFSET)))
				fp_colors.append(fp_color)

			if y == CitySim.N - 1 or sim.terrain[i + CitySim.N] != CitySim.T.ROAD:
				fp_xforms.append(Transform3D(
					Basis(),
					Vector3(p.x, 0.28, p.z + FOOTPATH_OFFSET)))
				fp_colors.append(fp_color)

			if x == 0 or sim.terrain[i - 1] != CitySim.T.ROAD:
				fp_xforms.append(Transform3D(
					Basis(Vector3.UP, PI * 0.5),
					Vector3(p.x - FOOTPATH_OFFSET, 0.28, p.z)))
				fp_colors.append(fp_color)

			if x == CitySim.N - 1 or sim.terrain[i + 1] != CitySim.T.ROAD:
				fp_xforms.append(Transform3D(
					Basis(Vector3.UP, PI * 0.5),
					Vector3(p.x + FOOTPATH_OFFSET, 0.28, p.z)))
				fp_colors.append(fp_color)

			# Zebra crossings on every approach to an intersection.
			if sim.intersections[i] == 1:
				if y > 0 and sim.intersections[i - CitySim.N] == 0:
					z_xforms.append(Transform3D(
						Basis(),
						Vector3(p.x, 0.60, p.z - ROAD_HALF + 1.2)))
					z_colors.append(zebra_color)
				if y < CitySim.N - 1 and sim.intersections[i + CitySim.N] == 0:
					z_xforms.append(Transform3D(
						Basis(),
						Vector3(p.x, 0.60, p.z + ROAD_HALF - 1.2)))
					z_colors.append(zebra_color)
				if x > 0 and sim.intersections[i - 1] == 0:
					z_xforms.append(Transform3D(
						Basis(Vector3.UP, PI * 0.5),
						Vector3(p.x - ROAD_HALF + 1.2, 0.60, p.z)))
					z_colors.append(zebra_color)
				if x < CitySim.N - 1 and sim.intersections[i + 1] == 0:
					z_xforms.append(Transform3D(
						Basis(Vector3.UP, PI * 0.5),
						Vector3(p.x + ROAD_HALF - 1.2, 0.60, p.z)))
					z_colors.append(zebra_color)

	var fmm: MultiMesh = _footpath_mm.multimesh
	fmm.instance_count = fp_xforms.size()
	for k in fp_xforms.size():
		fmm.set_instance_transform(k, fp_xforms[k])
		fmm.set_instance_color(k, fp_colors[k])

	var zmm: MultiMesh = _zebra_mm.multimesh
	zmm.instance_count = z_xforms.size()
	for k in z_xforms.size():
		zmm.set_instance_transform(k, z_xforms[k])
		zmm.set_instance_color(k, z_colors[k])

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

func _build_landmarks() -> void:
	_landmark_root = Node3D.new()
	_landmark_root.name = "Landmarks"
	add_child(_landmark_root)

# ─────────────────────────────────────────────────────────────
#  AGENTS — seed
# ─────────────────────────────────────────────────────────────
func _seed_agents() -> void:
	if _road_cells.is_empty(): return

	var pop: float = sim.s["population"]
	var congestion: float = sim.s["traffic_congestion"]
	var transit: float = sim.s["transit_share"]

	var n_cars: int = clampi(int(pop / 80.0 * (0.6 + 0.7 * congestion)), 60, MAX_CARS)
	for k in n_cars: _cars.append(_make_vehicle())

	var bus_palette := [Color(0.78, 0.42, 0.15), Color(0.30, 0.55, 0.72), Color(0.42, 0.65, 0.38), Color(0.85, 0.72, 0.30)]
	var n_buses: int = clampi(int(pop / 1400.0) + 8, 8, MAX_BUSES)
	for k in n_buses:
		var b: Car = _make_vehicle()
		b.color = bus_palette[k % bus_palette.size()]
		_buses.append(b)

	var n_trams: int = clampi(int(transit * 55.0) - 3, 0, MAX_TRAMS)
	for k in n_trams:
		var tr := _make_vehicle()
		tr.color = Color(0.85, 0.85, 0.88)
		_trams.append(tr)

	var n_peds: int = clampi(int(pop / 40.0), 80, 600)
	for k in n_peds: _peds.append(_spawn_ped())

	var trade: float = maxf(sim.s["exports_value"], sim.s["imports_value"])
	var n_boats: int = clampi(3 + int(trade / 18000.0), 3, MAX_BOATS)
	for k in n_boats: _boats.append(_make_boat(k))

	_cars_mm.multimesh.instance_count = n_cars
	_buses_mm.multimesh.instance_count = n_buses
	_trams_mm.multimesh.instance_count = n_trams
	_peds_mm.multimesh.instance_count = n_peds
	_boats_mm.multimesh.instance_count = n_boats

func _random_vehicle_color() -> Color:
	var palette := [Color(0.75, 0.15, 0.15), Color(0.20, 0.32, 0.72), Color(0.24, 0.24, 0.26), Color(0.88, 0.88, 0.90), Color(0.55, 0.58, 0.62), Color(0.85, 0.72, 0.30), Color(0.30, 0.55, 0.35), Color(0.65, 0.35, 0.15)]
	return palette[_rng.randi_range(0, palette.size() - 1)]

func _make_vehicle() -> Car:
	var c := Car.new()
	var rk: int = -1
	for attempt in 64:
		var probe: int = _rng.randi_range(0, _road_cells.size() - 1)
		var probe_world: int = int(_road_cells[probe])
		if sim.terrain[probe_world] != CitySim.T.ROAD: continue
		var has_neigh := false
		for n in _road_neighbors[probe]:
			if sim.terrain[int(_road_cells[n])] == CitySim.T.ROAD:
				has_neigh = true
				break
		if has_neigh:
			rk = probe
			break

	if rk < 0:
		for probe in _road_cells.size():
			if sim.terrain[int(_road_cells[probe])] != CitySim.T.ROAD: continue
			for n in _road_neighbors[probe]:
				if sim.terrain[int(_road_cells[n])] == CitySim.T.ROAD:
					rk = probe
					break
			if rk >= 0: break

	if rk < 0: rk = 0

	c.cell_idx = rk
	c.prev_cell_idx = -1
	c.next_cell_idx = rk
	c.t = _rng.randf_range(0.05, 0.35)
	c.speed = _rng.randf_range(2.5, 4.5)
	c.turn = 0.0
	c.color = _random_vehicle_color()
	c.stuck_time = 0.0
	_choose_next(c)
	c.prev_cell_idx = -1
	return c

func _random_person_color() -> Color:
	var palette := [Color(0.18, 0.20, 0.26), Color(0.30, 0.26, 0.22), Color(0.55, 0.55, 0.58), Color(0.72, 0.68, 0.62), Color(0.75, 0.30, 0.28), Color(0.24, 0.42, 0.62), Color(0.42, 0.55, 0.36), Color(0.62, 0.42, 0.30), Color(0.85, 0.78, 0.62), Color(0.42, 0.28, 0.42)]
	return palette[_rng.randi_range(0, palette.size() - 1)]

func _spawn_ped() -> Ped:
	var p := Ped.new()
	var rk: int = _rng.randi_range(0, _road_cells.size() - 1)
	var ri: int = int(_road_cells[rk])
	var rx: int = ri % CitySim.N
	var ry: int = ri / CitySim.N
	var origin: Vector3 = sim.world_pos(rx, ry)

	var best_rk: int = -1
	for attempt in 12:
		var try_rk: int = _rng.randi_range(0, _road_cells.size() - 1)
		var ti: int = int(_road_cells[try_rk])
		var tx: int = ti % CitySim.N
		var ty: int = ti / CitySim.N
		if tx == rx and ty == ry: continue
		if abs(tx - rx) <= 6 and abs(ty - ry) <= 6:
			best_rk = try_rk
			break
	if best_rk < 0:
		var nri: int = ri - CitySim.N if ry > 0 else ri + CitySim.N
		if _road_lookup.has(nri):
			best_rk = _road_lookup[nri]
		else:
			best_rk = rk
			var off: Vector3 = Vector3(0.0, 0.0, -FOOTPATH_OFFSET)
			p.from = origin + off
			p.from.y = 1.0
			p.to = p.from
			p.t = 1.0
			p.speed = _rng.randf_range(0.8, 1.5)
			p.wait = _rng.randf_range(0.1, 0.5)
			p.color = _random_person_color()
			p.stuck_time = 0.0
			p.heading_x = true
			p.cross_state = 0
			return p

	var tgt_i: int = int(_road_cells[best_rk])
	var target: Vector3 = sim.world_pos(tgt_i % CitySim.N, tgt_i / CitySim.N)

	var from_off: Vector3 = _footpath_offset_for(ri, tgt_i)
	var to_off: Vector3 = _footpath_offset_for(ri, tgt_i)

	p.from = origin + from_off
	p.from.y = 1.0
	p.to = target + to_off
	p.to.y = 1.0
	p.t = 0.0
	p.speed = _rng.randf_range(0.8, 1.5)
	p.wait = _rng.randf_range(0.0, 0.5)
	p.color = _random_person_color()
	p.stuck_time = 0.0
	p.heading_x = absf(p.to.x - p.from.x) > absf(p.to.z - p.from.z)
	p.cross_state = 0
	return p

func _make_boat(k: int) -> Boat:
	var b := Boat.new()
	b.path_pos = float(k) / float(MAX_BOATS) * float(_river_path.size())
	b.speed = _rng.randf_range(0.6, 1.4)
	b.color = Color(_rng.randf_range(0.4, 0.85), _rng.randf_range(0.4, 0.85), _rng.randf_range(0.4, 0.85))
	return b

# ─────────────────────────────────────────────────────────────
#  LANE / FOOTPATH HELPERS
# ─────────────────────────────────────────────────────────────

func _cell_world(i: int) -> Vector3:
	var x: int = i % CitySim.N
	var y: int = i / CitySim.N
	return sim.world_pos(x, y)

func _lane_offset_for(from_world_i: int, to_world_i: int) -> Vector3:
	var a: Vector3 = _cell_world(from_world_i)
	var b: Vector3 = _cell_world(to_world_i)
	var d: Vector3 = b - a
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return Vector3.ZERO
	d = d.normalized()
	var right := Vector3(-d.z, 0.0, d.x)
	return right * CAR_LANE_OFFSET

func _footpath_offset_for(from_world_i: int, to_world_i: int) -> Vector3:
	var a: Vector3 = _cell_world(from_world_i)
	var b: Vector3 = _cell_world(to_world_i)
	var d: Vector3 = b - a
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -FOOTPATH_OFFSET)
	d = d.normalized()
	var right := Vector3(-d.z, 0.0, d.x)
	return right * FOOTPATH_OFFSET

func _is_intersection(world_i: int) -> bool:
	return sim.intersections[world_i] == 1

func _light_is_green_for(intersection_world_i: int, heading_x: bool) -> bool:
	for k in _intersection_cells.size():
		if int(_intersection_cells[k]) == intersection_world_i:
			var t: float = _light_phases[k]
			var ns_green := t < LIGHT_GREEN_TIME
			var ew_green := t >= LIGHT_GREEN_TIME + LIGHT_YELLOW_TIME + LIGHT_RED_TIME \
				and t < LIGHT_GREEN_TIME + LIGHT_YELLOW_TIME + LIGHT_RED_TIME + LIGHT_GREEN_TIME
			if heading_x:
				return ew_green
			else:
				return ns_green
	return true

func _light_is_yellow_for(intersection_world_i: int, heading_x: bool) -> bool:
	for k in _intersection_cells.size():
		if int(_intersection_cells[k]) == intersection_world_i:
			var t: float = _light_phases[k]
			var ns_yellow := t >= LIGHT_GREEN_TIME and t < LIGHT_GREEN_TIME + LIGHT_YELLOW_TIME
			var ew_yellow := t >= LIGHT_GREEN_TIME + LIGHT_YELLOW_TIME + LIGHT_RED_TIME + LIGHT_GREEN_TIME \
				and t < LIGHT_GREEN_TIME + LIGHT_YELLOW_TIME + LIGHT_RED_TIME + LIGHT_GREEN_TIME + LIGHT_YELLOW_TIME
			if heading_x:
				return ew_yellow
			else:
				return ns_yellow
	return false

func _vehicle_ahead(arr: Array, k: int, cur_world_i: int, nxt_world_i: int) -> bool:
	var self_t: float = (arr[k] as Car).t
	var self_cur: int = cur_world_i
	var self_nxt: int = nxt_world_i

	for j in arr.size():
		if j == k: continue
		var other: Car = arr[j]

		var o_cur: int = int(_road_cells[other.cell_idx])
		var o_nxt: int = int(_road_cells[other.next_cell_idx])

		if o_cur == self_cur and o_nxt == self_nxt:
			if other.t > self_t + 0.02:
				return true
		elif o_cur == self_nxt and o_nxt != self_cur:
			return true

	return false

# ─────────────────────────────────────────────────────────────
#  TRAFFIC LIGHTS — poles at each corner of every intersection
# ─────────────────────────────────────────────────────────────
func _build_traffic_lights() -> void:
	_intersection_cells.clear()
	_light_phases.clear()

	for i in CitySim.CELLS:
		if sim.intersections[i] == 1 and sim.roundabouts[i] == 0:
			_intersection_cells.append(i)
			_light_phases.append(_rng.randf() * LIGHT_CYCLE)

	print("=== TRAFFIC LIGHTS ===")
	print("Intersections in sim: ", sim.intersections.count(1))
	print("Roundabouts in sim: ", sim.roundabouts.count(1))
	print("Traffic light intersections: ", _intersection_cells.size())
	print("======================")
	var n: int = _intersection_cells.size()
	if n == 0:
		return

	_light_pole_mesh = BoxMesh.new()
	_light_pole_mesh.size = Vector3(0.3, 4.5, 0.3)

	var pole_mat: StandardMaterial3D = StandardMaterial3D.new()
	pole_mat.vertex_color_use_as_albedo = true
	pole_mat.roughness = 0.6
	pole_mat.metallic = 0.4

	_light_pole_mm = MultiMeshInstance3D.new()
	var pmm: MultiMesh = MultiMesh.new()
	pmm.transform_format = MultiMesh.TRANSFORM_3D
	pmm.use_colors = true
	pmm.mesh = _light_pole_mesh
	pmm.instance_count = n * 4
	_light_pole_mm.multimesh = pmm
	_light_pole_mm.material_override = pole_mat
	add_child(_light_pole_mm)

	_light_bulb_mesh = BoxMesh.new()
	_light_bulb_mesh.size = Vector3(0.8, 0.8, 0.8)

	var bulb_mat: StandardMaterial3D = StandardMaterial3D.new()
	bulb_mat.vertex_color_use_as_albedo = true
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1, 1, 1)
	bulb_mat.emission_energy_multiplier = 2.5
	bulb_mat.roughness = 0.4
	bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_light_bulb_mm = MultiMeshInstance3D.new()
	var bmm: MultiMesh = MultiMesh.new()
	bmm.transform_format = MultiMesh.TRANSFORM_3D
	bmm.use_colors = true
	bmm.mesh = _light_bulb_mesh
	bmm.instance_count = n * 4
	_light_bulb_mm.multimesh = bmm
	_light_bulb_mm.material_override = bulb_mat
	add_child(_light_bulb_mm)

	var corner_offset: float = ROAD_HALF - 1.0

	for k in n:
		var i: int = int(_intersection_cells[k])
		var x: int = i % CitySim.N
		var y: int = i / CitySim.N
		var p: Vector3 = sim.world_pos(x, y)

		var corners: Array[Vector3] = [
			Vector3(p.x - corner_offset, 2.25, p.z - corner_offset),
			Vector3(p.x + corner_offset, 2.25, p.z - corner_offset),
			Vector3(p.x - corner_offset, 2.25, p.z + corner_offset),
			Vector3(p.x + corner_offset, 2.25, p.z + corner_offset),
		]
		for ci in 4:
			var c: Vector3 = corners[ci]
			var idx: int = k * 4 + ci
			pmm.set_instance_transform(idx, Transform3D(Basis(), c))
			pmm.set_instance_color(idx, Color(0.20, 0.20, 0.22))

			var bulb_pos: Vector3 = c + Vector3(0, 2.35, 0)
			bmm.set_instance_transform(idx, Transform3D(Basis(), bulb_pos))
			bmm.set_instance_color(idx, Color(0.2, 1.0, 0.3))

func _refresh_traffic_lights(delta: float) -> void:
	if _light_phases.is_empty():
		return

	var bmm: MultiMesh = _light_bulb_mm.multimesh
	var n: int = _light_phases.size()

	for k in n:
		var t: float = fmod(_light_phases[k] + delta, LIGHT_CYCLE)
		_light_phases[k] = t

		var phase: int
		if t < LIGHT_GREEN_TIME:
			phase = LightPhase.GREEN_NS
		elif t < LIGHT_GREEN_TIME + LIGHT_YELLOW_TIME:
			phase = LightPhase.YELLOW_NS
		elif t < LIGHT_GREEN_TIME + LIGHT_YELLOW_TIME + LIGHT_RED_TIME:
			phase = LightPhase.RED_NS
		elif t < LIGHT_GREEN_TIME + LIGHT_YELLOW_TIME + LIGHT_RED_TIME + LIGHT_GREEN_TIME:
			phase = LightPhase.GREEN_EW
		elif t < LIGHT_GREEN_TIME + LIGHT_YELLOW_TIME + LIGHT_RED_TIME + LIGHT_GREEN_TIME + LIGHT_YELLOW_TIME:
			phase = LightPhase.YELLOW_EW
		else:
			phase = LightPhase.RED_EW

		var col: Color
		match phase:
			LightPhase.GREEN_NS:  col = Color(0.15, 1.00, 0.25)
			LightPhase.YELLOW_NS: col = Color(1.00, 0.85, 0.10)
			LightPhase.GREEN_EW:  col = Color(0.15, 1.00, 0.25)
			LightPhase.YELLOW_EW: col = Color(1.00, 0.85, 0.10)
			_: col = Color(1.00, 0.15, 0.15)

		for corner in 4:
			bmm.set_instance_color(k * 4 + corner, col)

# ─────────────────────────────────────────────────────────────
#  REFRESH / VISUALS
# ─────────────────────────────────────────────────────────────
func refresh_all() -> void:
	_refresh_tiles()
	_refresh_buildings()
	_apply_day_night()

func _refresh_tiles() -> void:
	var mm: MultiMesh = _tiles_mm.multimesh
	for i in CitySim.CELLS:
		mm.set_instance_transform(i, _tile_xforms[i])
		mm.set_instance_color(i, _tile_color(i))

func _tile_color(i: int) -> Color:
	if overlay != Overlay.NATURAL: return _overlay_color(i)

	if sim.zebra_crossings.size() > i and sim.zebra_crossings[i] == 1:
		return Color(0.55, 0.55, 0.55)

	if sim.roundabouts.size() > i and sim.roundabouts[i] == 1:
		return Color(0.30, 0.32, 0.34)

	if sim.bridges.size() > i and sim.bridges[i] == 1:
		return Color(0.45, 0.27, 0.13)

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
		Overlay.AIR:        v = clampf(sim.air_pol[i] / 45.0, 0.0, 1.0)
		Overlay.WATER:      v = 1.0 - clampf(sim.water_pol[i] / 3.0, 0.0, 1.0)
		Overlay.ENERGY:     v = clampf(float(sim.floors[i]) / 26.0, 0.0, 1.0) * sim.occupancy[i]
		Overlay.TRAFFIC:
			v = clampf(sim.s["traffic_congestion"], 0.0, 1.0) if sim.terrain[i] == CitySim.T.ROAD else 0.0
		Overlay.SAFETY:     v = 1.0 - clampf(sim.s["crime_rate"] / 55.0, 0.0, 1.0)
		Overlay.GREEN:
			v = 1.0 if sim.terrain[i] == CitySim.T.PARK else clampf(sim.s["green_m2_capita"] / 30.0, 0.0, 1.0)
		Overlay.POPULATION: v = clampf(float(sim.floors[i]) * sim.occupancy[i] / 26.0, 0.0, 1.0)
		Overlay.LAND_VALUE: v = clampf(sim.land_value[i] / 1_200_000.0, 0.0, 1.0)
	return _heat(v)

func _heat(v: float) -> Color:
	if v < 0.25: return Color(0.08, 0.14, 0.38).lerp(Color(0.10, 0.55, 0.75), v / 0.25)
	if v < 0.50: return Color(0.10, 0.55, 0.75).lerp(Color(0.20, 0.72, 0.36), (v - 0.25) / 0.25)
	if v < 0.75: return Color(0.20, 0.72, 0.36).lerp(Color(0.92, 0.82, 0.20), (v - 0.50) / 0.25)
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
		if sim.zone[i] == zone_res: fl = max(1, fl + res_floor_delta)
		var h: float = float(fl) * 3.2

		var fw: float = cell_size * (0.50 + 0.22 * sim.occupancy[i])
		if sim.zone[i] == zone_ind: fw = cell_size * 0.72

		var o: Vector3 = _tile_xforms[i].origin
		bmm.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3(fw, h, fw)), Vector3(o.x, h * 0.5, o.z)))

		var base: Color = _building_base_color(i)
		var j: float = _bld_jitter[i]
		if j >= 0.0: base = base.lightened(j)
		else: base = base.darkened(-j)

		var lit: float = night * sim.occupancy[i]
		var c: Color = base.lerp(lit_color, lit * 0.48)
		c = c * (1.0 - 0.45 * night) + dark_color * (0.45 * night)
		bmm.set_instance_color(idx, c)

		var cap_h: float = 0.9
		var cap_w: float = fw * 1.06
		cmm.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3(cap_w, cap_h, cap_w)), Vector3(o.x, h + cap_h * 0.5 - 0.2, o.z)))
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
		CitySim.Z.RES: return Color(0.62, 0.57, 0.50).lerp(Color(0.76, 0.72, 0.66), sim.occupancy[i] - 0.82)
		CitySim.Z.COM: return Color(0.34, 0.42, 0.54).lerp(Color(0.54, 0.64, 0.76), sim.occupancy[i] - 0.8)
		CitySim.Z.IND: return Color(0.34, 0.32, 0.29)
		CitySim.Z.CIVIC: return Color(0.70, 0.74, 0.76)
	return Color(0.5, 0.5, 0.5)

func _night_factor() -> float:
	return 1.0 if is_night_mode else 0.0

func _apply_day_night() -> void:
	var night: float = _night_factor()

	if night > 0.5:
		_sun.rotation_degrees = Vector3(-35.0, 115.0, 0.0)
		_sun.light_energy = 0.10
		_sun.light_color = Color(0.55, 0.62, 0.86)
	else:
		_sun.rotation_degrees = Vector3(-52.0, 115.0, 0.0)
		_sun.light_energy = 1.20
		_sun.light_color = Color(1.0, 0.96, 0.88)

	var target_amb := 0.55
	var target_fog_col := Color(0.42, 0.50, 0.62)
	var target_fog_den := 0.0016
	var target_sky_top := Color(0.15, 0.22, 0.38)
	var target_sky_horizon := Color(0.42, 0.48, 0.58)

	if weather_visuals_enabled:
		match sim.s["weather"]:
			CitySim.WEATHER_CLOUDY:
				target_amb = 0.40
				target_fog_col = Color(0.55, 0.58, 0.62); target_fog_den = 0.004
				target_sky_top = Color(0.30, 0.34, 0.40); target_sky_horizon = Color(0.60, 0.64, 0.70)
			CitySim.WEATHER_RAIN:
				target_amb = 0.30
				target_fog_col = Color(0.40, 0.44, 0.50); target_fog_den = 0.006
				target_sky_top = Color(0.20, 0.24, 0.30); target_sky_horizon = Color(0.45, 0.50, 0.58)
			CitySim.WEATHER_STORM:
				target_amb = 0.20
				target_fog_col = Color(0.25, 0.28, 0.35); target_fog_den = 0.010
				target_sky_top = Color(0.10, 0.12, 0.18); target_sky_horizon = Color(0.30, 0.34, 0.42)
			CitySim.WEATHER_SNOW:
				target_amb = 0.55
				target_fog_col = Color(0.70, 0.75, 0.85); target_fog_den = 0.008
				target_sky_top = Color(0.40, 0.45, 0.55); target_sky_horizon = Color(0.75, 0.80, 0.88)

	if night > 0.5:
		target_amb = 0.22
		target_fog_col = Color(0.06, 0.08, 0.14)
		target_sky_top = Color(0.05, 0.05, 0.10)
		target_sky_horizon = Color(0.10, 0.12, 0.18)

	var e: Environment = _env.environment
	e.ambient_light_energy = target_amb

	if not mobile:
		e.fog_density = target_fog_den
		e.fog_light_color = target_fog_col
		var sky_mat: ProceduralSkyMaterial = e.sky.sky_material
		sky_mat.sky_top_color = target_sky_top
		sky_mat.sky_horizon_color = target_sky_horizon
	else:
		e.background_color = target_sky_top

	_bld_mat.set_shader_parameter("night", night)
	if _stone_mat: _stone_mat.set_shader_parameter("night", night)

	_apply_weather_particles()

func _apply_weather_particles() -> void:
	if weather_visuals_enabled:
		_rain_particles.emitting = (sim.s["weather"] == CitySim.WEATHER_RAIN or sim.s["weather"] == CitySim.WEATHER_STORM)
		_snow_particles.emitting = (sim.s["weather"] == CitySim.WEATHER_SNOW)
	else:
		_rain_particles.emitting = false
		_snow_particles.emitting = false

func set_day_mode(night: bool) -> void:
	is_night_mode = night
	_apply_day_night()
	_refresh_buildings()

func refresh_buildings_smooth() -> void:
	pass

func set_overlay(o: int) -> void:
	overlay = o
	_refresh_tiles()

# ─────────────────────────────────────────────────────────────
#  AGENT UPDATE
# ─────────────────────────────────────────────────────────────
func tick_agents(delta: float, hours_per_second: float) -> void:
	if hours_per_second <= 0.0:
		return
	var spd_scale: float = clampf(hours_per_second / 3.0, 0.2, 4.0)
	var d: float = delta * spd_scale

	_refresh_traffic_lights(delta)

	_update_vehicles(_cars, _cars_mm, d, 1.0)
	_update_vehicles(_buses, _buses_mm, d, 0.55)
	_update_vehicles(_trams, _trams_mm, d, 0.7)
	_update_peds(d)
	_update_boats(d)

# ─────────────────────────────────────────────────────────────
#  VEHICLES
# ─────────────────────────────────────────────────────────────
func _update_vehicles(arr: Array, mmi: MultiMeshInstance3D, delta: float, speed_mult: float) -> void:
	if arr.is_empty(): return
	var mm: MultiMesh = mmi.multimesh
	var congestion: float = sim.s["traffic_congestion"]
	var cong_slow: float = 1.0 - 0.7 * congestion

	for k in arr.size():
		var c: Car = arr[k]

		if c.turn > 0.0:
			c.turn -= delta
			_render_vehicle(c, k, mm)
			continue

		var cur_w: int = int(_road_cells[c.cell_idx])
		var nxt_w: int = int(_road_cells[c.next_cell_idx])

		# ── Approach check: are we about to enter a red intersection? ──
		var blocked: bool = false
		if sim.intersections[nxt_w] == 1 and sim.roundabouts[nxt_w] == 0:
			var dvec: Vector3 = _cell_world(nxt_w) - _cell_world(cur_w)
			var hx: bool = absf(dvec.x) > absf(dvec.z)
			if not _light_is_green_for(nxt_w, hx):
				blocked = true

		var advance: float = delta * c.speed * speed_mult * cong_slow
		var new_t: float = c.t + advance

		if blocked:
			# Freeze at 0.85. Do not advance toward the boundary.
			if c.t > 0.85:
				c.t = 0.85
			c.stuck_time += delta
			_render_vehicle(c, k, mm)
			continue

		# ── Advance / wrap ──
		if new_t >= 1.0:
			c.t = new_t - 1.0
			c.prev_cell_idx = c.cell_idx
			c.cell_idx = c.next_cell_idx
			_choose_next(c)
			if _rng.randf() < 0.12: c.turn = _rng.randf_range(0.2, 0.5)
		else:
			c.t = new_t

		# ── Sanity check ──
		var cur_world_i: int = int(_road_cells[c.cell_idx])
		var nxt_world_i: int = int(_road_cells[c.next_cell_idx])
		if sim.terrain[cur_world_i] != CitySim.T.ROAD or sim.terrain[nxt_world_i] != CitySim.T.ROAD:
			c.prev_cell_idx = -1
			_choose_next(c)
			c.t = 0.0
			cur_world_i = int(_road_cells[c.cell_idx])
			nxt_world_i = int(_road_cells[c.next_cell_idx])

		# ── Queue discipline — skipped inside intersections ──
		if sim.intersections[cur_world_i] == 0:
			if c.t > VEHICLE_MIN_GAP and _vehicle_ahead(arr, k, cur_world_i, nxt_world_i):
				c.t = VEHICLE_MIN_GAP

		_render_vehicle(c, k, mm)


func _render_vehicle(c: Car, k: int, mm: MultiMesh) -> void:
	var cur_world_i: int = int(_road_cells[c.cell_idx])
	var nxt_world_i: int = int(_road_cells[c.next_cell_idx])
	var lane: Vector3 = _lane_offset_for(cur_world_i, nxt_world_i)
	var a: Vector3 = _cell_world(cur_world_i)
	var b: Vector3 = _cell_world(nxt_world_i)
	var cl: float = clampf(c.t, 0.0, 1.0)
	var pos: Vector3 = a.lerp(b, cl) + lane
	pos.y = 1.1

	var dir: Vector3 = (b - a)
	dir.y = 0.0
	var yaw: float = 0.0
	if dir.length_squared() > 0.001: yaw = atan2(dir.x, dir.z)

	mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, yaw), pos))
	mm.set_instance_color(k, c.color)

func _choose_next(c: Car) -> void:
	var neigh: Array = _road_neighbors[c.cell_idx]
	if neigh.is_empty():
		c.next_cell_idx = c.cell_idx
		return

	var candidates: Array = []
	for n_idx in neigh:
		var ni: int = int(_road_cells[n_idx])
		if sim.terrain[ni] != CitySim.T.ROAD: continue
		if n_idx == c.prev_cell_idx: continue
		candidates.append(n_idx)

	if candidates.is_empty():
		for n_idx in neigh:
			var ni: int = int(_road_cells[n_idx])
			if sim.terrain[ni] == CitySim.T.ROAD:
				candidates.append(n_idx)

	if candidates.is_empty():
		var rk: int = _rng.randi_range(0, _road_cells.size() - 1)
		c.cell_idx = rk
		c.prev_cell_idx = -1
		c.next_cell_idx = rk
		c.t = 0.0
		return

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
				if d.length_squared() < 0.001: continue
				d = d.normalized()
				var dot_val: float = heading.dot(d)
				if dot_val > best_dot:
					best_dot = dot_val
					chosen = cand

	if chosen < 0:
		chosen = candidates[_rng.randi_range(0, candidates.size() - 1)]

	c.next_cell_idx = chosen

# ─────────────────────────────────────────────────────────────
#  PEDESTRIANS
# ─────────────────────────────────────────────────────────────
func _update_peds(delta: float) -> void:
	if _peds.is_empty(): return
	var mm: MultiMesh = _peds_mm.multimesh

	for k in _peds.size():
		var p: Ped = _peds[k]

		# ── crossing phase ──
		if p.cross_state == 2:
			p.cross_t += delta / PED_CROSS_TIME
			var pos: Vector3 = p.cross_from.lerp(p.cross_to, clampf(p.cross_t, 0.0, 1.0))
			pos.y = 1.0
			var dir: Vector3 = (p.cross_to - p.cross_from)
			dir.y = 0.0
			var yaw: float = 0.0
			if dir.length_squared() > 0.001: yaw = atan2(dir.x, dir.z)
			mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, yaw), pos))
			mm.set_instance_color(k, p.color)
			if p.cross_t >= 1.0:
				p.cross_state = 0
				p.from = p.cross_to
				p.to = p.cross_to
				p.t = 1.0
				p.wait = _rng.randf_range(0.2, 1.0)
				p.cross_t = 0.0
				p.stuck_time = 0.0
			continue

		# ── waiting at zebra ──
		if p.cross_state == 1:
			p.wait -= delta
			p.stuck_time += delta

			# Find the intersection the ped is waiting at (nearest).
			var zebra_cell: int = -1
			var best_d: float = 999.0
			for kk in _intersection_cells.size():
				var i: int = int(_intersection_cells[kk])
				var cw: Vector3 = _cell_world(i)
				var dd: float = Vector2(cw.x - p.from.x, cw.z - p.from.z).length()
				if dd < best_d:
					best_d = dd
					zebra_cell = i

			# Re-check the light every frame. If it's red for cars AND
			# no car is in the intersection, cross.
			var can_cross := false
			if zebra_cell >= 0:
				var cars_moving := false
				for car in _cars:
					var c_cur: int = int(_road_cells[car.cell_idx])
					var c_nxt: int = int(_road_cells[car.next_cell_idx])
					if c_cur == zebra_cell or c_nxt == zebra_cell:
						if car.t > 0.05 and car.t < 0.95:
							cars_moving = true
							break
				var any_green: bool = _light_is_green_for(zebra_cell, true) \
					or _light_is_green_for(zebra_cell, false)
				can_cross = not cars_moving and not any_green

			if can_cross:
				p.cross_state = 2
				p.cross_t = 0.0
				p.cross_from = p.from
				var zebra_to: Vector3 = _zebra_position_near(p.from, zebra_cell)
				if zebra_to == Vector3.ZERO:
					zebra_to = p.from
				zebra_to.y = 1.0
				p.cross_to = zebra_to
				p.stuck_time = 0.0
				continue

			# If we've been stuck too long, teleport to the footpath.
			if p.stuck_time > STUCK_THRESHOLD:
				var fx: int = int(round(p.from.x / CitySim.CELL + CitySim.N * 0.5 - 0.5))
				var fz: int = int(round(p.from.z / CitySim.CELL + CitySim.N * 0.5 - 0.5))
				fx = clampi(fx, 0, CitySim.N - 1)
				fz = clampi(fz, 0, CitySim.N - 1)
				var fcell: int = fz * CitySim.N + fx
				if _road_lookup.has(fcell):
					var off: Vector3 = Vector3(0.0, 0.0, -FOOTPATH_OFFSET)
					p.from = _cell_world(fcell) + off
					p.from.y = 1.0
					p.to = p.from
					p.t = 0.0
					p.cross_state = 0
					p.stuck_time = 0.0
					p.wait = 0.3

			# Hold position
			var pos_w: Vector3 = p.from
			pos_w.y = 1.0
			mm.set_instance_transform(k, Transform3D(Basis(), pos_w))
			mm.set_instance_color(k, p.color)
			continue

		# ── walking on footpath ──
		if p.wait > 0.0:
			p.wait -= delta
			continue

		p.t += delta * p.speed * 0.30
		if p.t >= 1.0:
			p.from = p.to

			var from_x: int = int(round(p.from.x / CitySim.CELL + CitySim.N * 0.5 - 0.5))
			var from_z: int = int(round(p.from.z / CitySim.CELL + CitySim.N * 0.5 - 0.5))
			from_x = clampi(from_x, 0, CitySim.N - 1)
			from_z = clampi(from_z, 0, CitySim.N - 1)

			var candidates: Array = []
			var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			for dd in dirs:
				var nx: int = from_x + dd.x
				var nz: int = from_z + dd.y
				if nx < 0 or nz < 0 or nx >= CitySim.N or nz >= CitySim.N: continue
				var ni: int = nz * CitySim.N + nx
				if not _road_lookup.has(ni): continue
				candidates.append(ni)

			if candidates.is_empty():
				p.t = 0.0
				p.wait = 0.4
				continue

			var next_target_world: int = candidates[_rng.randi_range(0, candidates.size() - 1)]
			var to_x: int = next_target_world % CitySim.N
			var to_z: int = next_target_world / CitySim.N

			if sim.intersections[next_target_world] == 1:
				var cars_moving: bool = false
				for car in _cars:
					var c_cur: int = int(_road_cells[car.cell_idx])
					var c_nxt: int = int(_road_cells[car.next_cell_idx])
					if c_cur == next_target_world or c_nxt == next_target_world:
						if car.t > 0.05 and car.t < 0.95:
							cars_moving = true
							break
				var any_green: bool = _light_is_green_for(next_target_world, to_x != from_x) \
					or _light_is_green_for(next_target_world, to_z != from_z)

				if cars_moving or any_green:
					p.cross_state = 1
					p.wait = _rng.randf_range(0.3, 0.7)
					p.stuck_time = 0.0
					var zp: Vector3 = _zebra_position_near(p.from, next_target_world)
					if zp != Vector3.ZERO:
						p.from = zp
					continue
				else:
					p.cross_state = 2
					p.cross_t = 0.0
					p.cross_from = p.from
					var zebra_to: Vector3 = _zebra_position_near(_cell_world(next_target_world), next_target_world)
					if zebra_to == Vector3.ZERO:
						zebra_to = _cell_world(next_target_world)
					zebra_to.y = 1.0
					p.cross_to = zebra_to
					continue

			var cur_world_i: int = from_z * CitySim.N + from_x
			var off: Vector3 = _footpath_offset_for(cur_world_i, next_target_world)
			var target: Vector3 = _cell_world(next_target_world) + off
			target.y = 1.0
			p.to = target
			p.t = 0.0
			p.heading_x = absf(p.to.x - p.from.x) > absf(p.to.z - p.from.z)
			p.wait = _rng.randf_range(0.1, 0.6)

		var pos: Vector3 = p.from.lerp(p.to, clampf(p.t, 0.0, 1.0))
		var dir: Vector3 = (p.to - p.from)
		dir.y = 0.0
		var yaw: float = 0.0
		if dir.length_squared() > 0.001: yaw = atan2(dir.x, dir.z)
		var basis := Basis(Vector3.UP, yaw)
		mm.set_instance_transform(k, Transform3D(basis, pos))
		mm.set_instance_color(k, p.color)

func _pick_next_ped_target(p: Ped) -> int:
	var cur_x: int = int(round(p.from.x / CitySim.CELL + CitySim.N * 0.5 - 0.5))
	var cur_z: int = int(round(p.from.z / CitySim.CELL + CitySim.N * 0.5 - 0.5))
	var candidates: Array = []
	for dx in [-2, -1, 0, 1, 2]:
		for dz in [-2, -1, 0, 1, 2]:
			if dx == 0 and dz == 0: continue
			var nx: int = cur_x + dx
			var nz: int = cur_z + dz
			if nx < 0 or nz < 0 or nx >= CitySim.N or nz >= CitySim.N: continue
			var ni: int = nz * CitySim.N + nx
			if not _road_lookup.has(ni): continue
			candidates.append(ni)
	if candidates.is_empty():
		return _road_cells[_rng.randi_range(0, _road_cells.size() - 1)]
	return candidates[_rng.randi_range(0, candidates.size() - 1)]

func _pick_next_ped_target_same_cell(p: Ped) -> int:
	var cur_x: int = int(round(p.from.x / CitySim.CELL + CitySim.N * 0.5 - 0.5))
	var cur_z: int = int(round(p.from.z / CitySim.CELL + CitySim.N * 0.5 - 0.5))
	var candidates: Array = []
	for dx in [-2, -1, 1, 2]:
		var nx: int = cur_x + dx
		if nx < 0 or nx >= CitySim.N: continue
		var ni: int = cur_z * CitySim.N + nx
		if _road_lookup.has(ni): candidates.append(ni)
	for dz in [-2, -1, 1, 2]:
		var nz: int = cur_z + dz
		if nz < 0 or nz >= CitySim.N: continue
		var ni: int = nz * CitySim.N + cur_x
		if _road_lookup.has(ni): candidates.append(ni)
	if candidates.is_empty():
		return _pick_next_ped_target(p)
	return candidates[_rng.randi_range(0, candidates.size() - 1)]

func _prev_world_cell(world_pos_vec: Vector3) -> int:
	var cx: int = int(round(world_pos_vec.x / CitySim.CELL + CitySim.N * 0.5 - 0.5))
	var cz: int = int(round(world_pos_vec.z / CitySim.CELL + CitySim.N * 0.5 - 0.5))
	cx = clampi(cx, 0, CitySim.N - 1)
	cz = clampi(cz, 0, CitySim.N - 1)
	return cz * CitySim.N + cx

func _zebra_position_near(from_pos: Vector3, _target_world: int) -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_d: float = 1e9
	for k in _intersection_cells.size():
		var i: int = int(_intersection_cells[k])
		var x: int = i % CitySim.N
		var y: int = i / CitySim.N
		var p: Vector3 = sim.world_pos(x, y)
		var zebra_offsets: Array = [
			Vector3(p.x, 0.60, p.z - ROAD_HALF + 1.2),
			Vector3(p.x, 0.60, p.z + ROAD_HALF - 1.2),
			Vector3(p.x - ROAD_HALF + 1.2, 0.60, p.z),
			Vector3(p.x + ROAD_HALF - 1.2, 0.60, p.z),
		]
		for zp in zebra_offsets:
			var d: float = Vector2(zp.x - from_pos.x, zp.z - from_pos.z).length()
			if d < best_d:
				best_d = d
				best = zp
	return best

# ─────────────────────────────────────────────────────────────
#  BOATS
# ─────────────────────────────────────────────────────────────
func _update_boats(delta: float) -> void:
	if _boats.is_empty() or _river_path.is_empty(): return
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
		if dir.length_squared() > 0.001: yaw = atan2(dir.x, dir.z)

		var basis := Basis(Vector3.UP, yaw)
		mm.set_instance_transform(k, Transform3D(basis, pos))
		mm.set_instance_color(k, b.color)
