extends Node3D

const MAX_STEPS_PER_FRAME := 8

var sim: CitySim
var builder: CityBuilder
var rig: CameraRig
var dash: Dashboard

var mobile: bool = false

var _accum := 0.0
var _visual_timer := 0.0

func _ready() -> void:
	# ── platform detection ──
	mobile = OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]

	if mobile:
		# reduce 3D render resolution to 70% — big GPU win on mobile
		get_viewport().scaling_3d_scale = 0.70
		# reduce MSAA in case project settings have it high
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED

	sim = CitySim.new()
	sim.generate(randi())

	builder = CityBuilder.new()
	add_child(builder)
	builder.setup(sim, mobile)

	rig = CameraRig.new()
	add_child(rig)
	if mobile:
		rig.set_mobile_defaults()

	dash = Dashboard.new()
	add_child(dash)
	dash.setup(sim, self, mobile)

	for i in 48:
		sim.step_hour()

	builder.refresh_all()
	dash._refresh()

func _process(delta: float) -> void:
	# ── simulation stepping ──
	var hps: float = dash.speed_hours_per_second()
	if hps > 0.0:
		_accum += delta * hps
		var steps := 0
		while _accum >= 1.0 and steps < MAX_STEPS_PER_FRAME:
			sim.step_hour()
			_accum -= 1.0
			steps += 1
		if _accum > 2.0:
			_accum = 0.0

	# ── sun moves every frame — one light, one env, negligible cost ──
	builder._refresh_sun()

	# ── buildings re-tint only when the light has moved enough to matter ──
	builder.refresh_buildings_smooth()

	# ── UI ──
	dash.tick(delta)

func set_overlay(index: int) -> void:
	builder.set_overlay(index)
