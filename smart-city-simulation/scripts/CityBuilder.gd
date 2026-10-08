class_name CityBuilder
extends Node3D

var sim: CitySim

var _tiles_mm: MultiMeshInstance3D
var _bld_mm: MultiMeshInstance3D
var _tile_mesh: BoxMesh
var _bld_mesh: BoxMesh

var overlay: int = 0    # OverlayMode enum index

enum Overlay { NATURAL, AIR, WATER, ENERGY, TRAFFIC, SAFETY, GREEN, POPULATION, LAND_VALUE }

const OVERLAY_NAMES := ["Natural", "Air Quality", "Water Quality", "Energy Load",
	"Traffic", "Safety", "Green Space", "Density", "Land Value"]

var _sun: DirectionalLight3D
var _env: WorldEnvironment

# ─────────────────────────────────────────────────────────────
func setup(sim_ref: CitySim) -> void:
	sim = sim_ref
	_build_environment()
	_build_meshes()
	refresh_all()

func _build_environment() -> void:
	_env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
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
	e.ssao_enabled = true
	e.ssao_radius = 6.0
	e.ssao_intensity = 1.4
	e.fog_enabled = true
	e.fog_light_color = Color(0.42, 0.50, 0.62)
	e.fog_density = 0.0016
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.environment = e
	add_child(_env)

	_sun = DirectionalLight3D.new()
	_sun.light_energy = 1.15
	_sun.light_color = Color(1.0, 0.96, 0.88)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 1400.0
	add_child(_sun)

func _build_meshes() -> void:
	# ── tiles ──
	_tile_mesh = BoxMesh.new()
	_tile_mesh.size = Vector3(CitySim.CELL, 0.35, CitySim.CELL)

	var tmat := StandardMaterial3D.new()
	tmat.vertex_color_use_as_albedo = true
	tmat.roughness = 0.95
	tmat.specular = 0.08

	_tiles_mm = MultiMeshInstance3D.new()
	var tmm := MultiMesh.new()
	tmm.transform_format = MultiMesh.TRANSFORM_3D
	tmm.use_colors = true
	tmm.mesh = _tile_mesh
	tmm.instance_count = CitySim.CELLS
	_tiles_mm.multimesh = tmm
	_tiles_mm.material_override = tmat
	add_child(_tiles_mm)

	# ── buildings ──
	_bld_mesh = BoxMesh.new()
	_bld_mesh.size = Vector3(1.0, 1.0, 1.0)

	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.roughness = 0.62
	bmat.metallic = 0.05
	bmat.specular = 0.35

	_bld_mm = MultiMeshInstance3D.new()
	var bmm := MultiMesh.new()
	bmm.transform_format = MultiMesh.TRANSFORM_3D
	bmm.use_colors = true
	bmm.mesh = _bld_mesh
	bmm.instance_count = CitySim.CELLS
	_bld_mm.multimesh = bmm	
	_bld_mm.material_override = bmat
	add_child(_bld_mm)

# ─────────────────────────────────────────────────────────────
func refresh_all() -> void:
	_refresh_tiles()
	_refresh_buildings()
	_refresh_sun()

func _refresh_tiles() -> void:
	var mm: MultiMesh = _tiles_mm.multimesh
	for y in CitySim.N:
		for x in CitySim.N:
			var i: int = y * CitySim.N + x
			var p: Vector3 = sim.world_pos(x, y)
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x, 0.175, p.z)))
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
	var v := 0.0
	match overlay:
		Overlay.AIR:        v = clampf(sim.air_pol[i] / 45.0, 0.0, 1.0)
		Overlay.WATER:      v = 1.0 - clampf(sim.water_pol[i] / 3.0, 0.0, 1.0)
		Overlay.ENERGY:     v = clampf(float(sim.floors[i]) / 26.0, 0.0, 1.0) * sim.occupancy[i]
		Overlay.TRAFFIC:    v = clampf(sim.traffic[i], 0.0, 1.0)
		Overlay.SAFETY:     v = 1.0 - clampf(sim.s["crime_rate"] / 55.0, 0.0, 1.0)
		Overlay.GREEN:      v = 1.0 if sim.terrain[i] == CitySim.T.PARK else clampf(sim.s["green_m2_capita"] / 30.0, 0.0, 1.0)
		Overlay.POPULATION: v = clampf(float(sim.floors[i]) * sim.occupancy[i] / 26.0, 0.0, 1.0)
		Overlay.LAND_VALUE: v = clampf(sim.land_value[i] / 1_200_000.0, 0.0, 1.0)
	return _heat(v)

func _heat(v: float) -> Color:
	# blue → cyan → green → yellow → red
	if v < 0.25: return Color(0.08, 0.14, 0.38).lerp(Color(0.10, 0.55, 0.75), v / 0.25)
	if v < 0.50: return Color(0.10, 0.55, 0.75).lerp(Color(0.20, 0.72, 0.36), (v - 0.25) / 0.25)
	if v < 0.75: return Color(0.20, 0.72, 0.36).lerp(Color(0.92, 0.82, 0.20), (v - 0.50) / 0.25)
	return Color(0.92, 0.82, 0.20).lerp(Color(0.88, 0.20, 0.16), (v - 0.75) / 0.25)

func _refresh_buildings() -> void:
	var mm: MultiMesh = _bld_mm.multimesh
	var night: float = _night_factor()
	var idx := 0

	for y in CitySim.N:
		for x in CitySim.N:
			var i: int = y * CitySim.N + x
			if sim.zone[i] == CitySim.Z.NONE or sim.floors[i] <= 0:
				continue

			var fl: int = sim.floors[i]
			var h: float = float(fl) * 3.2
			var p: Vector3 = sim.world_pos(x, y)

			# footprint varies with density/zone
			var fw: float = CitySim.CELL * (0.62 + 0.28 * sim.occupancy[i])
			if sim.zone[i] == CitySim.Z.IND:
				fw = CitySim.CELL * 0.88
			var basis := Basis().scaled(Vector3(fw, h, fw))
			mm.set_instance_transform(idx, Transform3D(basis, Vector3(p.x, h * 0.5, p.z)))

			var base := _building_base_color(i)
			# night: windows glow
			var lit: float = night * sim.occupancy[i]
			var c: Color = base.lerp(Color(1.0, 0.84, 0.52), lit * 0.48)
			c = c * (1.0 - 0.45 * night) + Color(0.10, 0.11, 0.16) * (0.45 * night)
			mm.set_instance_color(idx, c)
			idx += 1

	# hide unused instances
	for k in range(idx, CitySim.CELLS):
		mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))

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
		CitySim.Z.RES: return Color(0.60, 0.54, 0.46).lerp(Color(0.72, 0.68, 0.62), sim.occupancy[i])
		CitySim.Z.COM: return Color(0.36, 0.44, 0.56).lerp(Color(0.52, 0.62, 0.74), sim.occupancy[i] - 0.8)
		CitySim.Z.IND: return Color(0.34, 0.32, 0.29)
		CitySim.Z.CIVIC: return Color(0.70, 0.74, 0.76)
	return Color(0.5, 0.5, 0.5)

# ─────────────────────────────────────────────────────────────
func _night_factor() -> float:
	var h: float = float(sim.tick % CitySim.HOURS_PER_DAY)
	if h < 5.0:  return 1.0
	if h < 7.0:  return 1.0 - (h - 5.0) / 2.0
	if h < 18.0: return 0.0
	if h < 21.0: return (h - 18.0) / 3.0
	return 1.0

func _refresh_sun() -> void:
	var t: float = float(sim.tick % CitySim.HOURS_PER_DAY) / 24.0
	var angle: float = t * TAU - PI * 0.5
	var elev: float = sin(angle) * 62.0
	var azim: float = 115.0

	_sun.rotation_degrees = Vector3(-max(elev, -8.0), azim, 0.0)
	var night := _night_factor()
	_sun.light_energy = lerpf(1.20, 0.08, night)
	_sun.light_color = Color(1.0, 0.96, 0.88).lerp(Color(0.55, 0.62, 0.86), night)

	var e: Environment = _env.environment
	e.ambient_light_energy = lerpf(0.55, 0.22, night)
	e.fog_light_color = Color(0.42, 0.50, 0.62).lerp(Color(0.06, 0.08, 0.14), night)

func set_overlay(o: int) -> void:
	overlay = o
	_refresh_tiles()
