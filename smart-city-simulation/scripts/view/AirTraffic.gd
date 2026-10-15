class_name AirTraffic
extends Node3D

# Real-time seconds. Independent of sim speed — planes cross at 220-340 u/s.
const ALT_MIN := 180.0
const ALT_MAX := 220.0
const SPEED_MIN := 220.0
const SPEED_MAX := 340.0
const SPAWN_MIN := 3.0
const SPAWN_MAX := 8.0
const MAX_ACTIVE := 3
const CITY_HALF := 400.0
const SPAWN_MARGIN := 280.0
const DESPAWN_DIST := CITY_HALF + SPAWN_MARGIN * 2.0

# Set by Main.gd each frame. When true, planes freeze in place and
# no new ones spawn.
var paused := false

var _planes: Array[MeshInstance3D] = []
var _velocities: Array[Vector3] = []
var _mesh: ArrayMesh
var _mat: StandardMaterial3D

var _spawn_timer := 0.0
var _next_spawn := 0.0

func setup() -> void:
	_mesh = _make_plane_mesh()
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.55
	_mat.metallic = 0.15
	_mat.specular = 0.55
	# First plane arrives almost immediately so you see the effect
	_next_spawn = randf_range(0.5, 1.5)

# Scaling exponent. 1.0 = linear (speed exactly matches sim speed).
# Lower it (0.6, 0.5) for a gentler ramp at high speeds.
const SPEED_EXPONENT := 1.0

var sim_speed := 1.0   # set by Main.gd each frame

func _process(delta: float) -> void:
	if paused or sim_speed <= 0.0:
		return

	# Scale simulation delta by sim speed^exponent.
	# At 1× → planes move at base speed.
	# At 12× → 12× base speed. At 48× → 48× base speed.
	var scale: float = pow(sim_speed, SPEED_EXPONENT)
	var sdelta: float = delta * scale

	var i := _planes.size() - 1
	while i >= 0:
		var p: MeshInstance3D = _planes[i]
		p.position += _velocities[i] * sdelta
		var horiz := Vector2(p.position.x, p.position.z).length()
		if horiz > DESPAWN_DIST:
			p.queue_free()
			_planes.remove_at(i)
			_velocities.remove_at(i)
		i -= 1

	_spawn_timer += sdelta
	if _spawn_timer >= _next_spawn and _planes.size() < MAX_ACTIVE:
		_spawn_plane()
		_spawn_timer = 0.0
		_next_spawn = randf_range(SPAWN_MIN, SPAWN_MAX)

func _spawn_plane() -> void:
	var angle := randf() * TAU
	var dir := Vector3(cos(angle), 0.0, sin(angle))
	var perp := Vector3(-sin(angle), 0.0, cos(angle))

	var alt := randf_range(ALT_MIN, ALT_MAX)
	var start := -dir * (CITY_HALF + SPAWN_MARGIN) + Vector3(0, alt, 0)
	start += perp * randf_range(-CITY_HALF * 0.75, CITY_HALF * 0.75)

	var speed := randf_range(SPEED_MIN, SPEED_MAX)

	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _mat

	# Build the transform by hand. Transform3D.looking_at() is pure math
	# (no tree dependency) so it can't misbehave the way Node3D.look_at()
	# sometimes does on not-yet-parented nodes.
	# looking_at makes local -Z point at the target, and the mesh's nose
	# is at -Z, so the nose will point exactly along `dir`.
	var xf := Transform3D(Basis(), start)
	xf = xf.looking_at(start + dir, Vector3.UP)
	mi.transform = xf

	add_child(mi)

	_planes.append(mi)
	_velocities.append(dir * speed)

func _make_plane_mesh() -> ArrayMesh:
	# Nose points toward -Z. Tail is +Z.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var body      := Color(0.88, 0.89, 0.92)
	var body_dark := Color(0.62, 0.64, 0.70)
	var wing      := Color(0.72, 0.74, 0.78)
	var engine    := Color(0.34, 0.36, 0.40)
	var accent    := Color(0.24, 0.36, 0.58)
	var glass     := Color(0.40, 0.55, 0.72)
	var nose_acc  := Color(0.92, 0.42, 0.16)   # bright orange — direction cue

	# fuselage
	Landmarks.add_box(st, Vector3(0, 0, 0), Vector3(2.2, 2.2, 24), body)
	# nose cone
	Landmarks.add_box(st, Vector3(0, 0, -12.6), Vector3(1.5, 1.5, 2.0), body_dark)
	# bright nose accent (unmistakable forward indicator)
	Landmarks.add_box(st, Vector3(0, 0, -11.8), Vector3(1.6, 1.6, 0.5), nose_acc)
	# cockpit glass
	Landmarks.add_box(st, Vector3(0, 0.75, -10.0), Vector3(2.05, 0.55, 1.5), glass)
	# tail cone
	Landmarks.add_box(st, Vector3(0, 0.3, 12.6), Vector3(1.5, 1.5, 1.5), body_dark)

	# main wings
	Landmarks.add_box(st, Vector3(0, -0.3, -1.0), Vector3(20, 0.5, 3.6), wing)
	# wingtip accents
	Landmarks.add_box(st, Vector3( 9.7, -0.3, -1.0), Vector3(0.8, 0.55, 3.6), accent)
	Landmarks.add_box(st, Vector3(-9.7, -0.3, -1.0), Vector3(0.8, 0.55, 3.6), accent)

	# tailplane
	Landmarks.add_box(st, Vector3(0, 0.3, 10.0), Vector3(7.5, 0.4, 2.2), wing)
	# vertical stabiliser
	Landmarks.add_box(st, Vector3(0, 1.7, 10.0), Vector3(0.5, 3.0, 2.8), wing)
	# rudder accent
	Landmarks.add_box(st, Vector3(0, 2.3, 11.2), Vector3(0.55, 1.8, 0.45), accent)

	# engines under wings
	Landmarks.add_box(st, Vector3( 5.5, -1.3, -1.0), Vector3(1.6, 1.5, 3.5), engine)
	Landmarks.add_box(st, Vector3(-5.5, -1.3, -1.0), Vector3(1.6, 1.5, 3.5), engine)

	st.generate_normals()
	return st.commit()
