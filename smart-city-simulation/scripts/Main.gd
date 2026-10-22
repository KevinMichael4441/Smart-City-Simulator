extends Node3D

const MAX_STEPS_PER_FRAME := 8

var sim: CitySim
var builder: CityBuilder
var rig: CameraRig
var dash: Dashboard
var air_traffic: AirTraffic

var mobile: bool = false

var _accum := 0.0

func _ready() -> void:
	mobile = OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]
	if mobile:
		get_viewport().scaling_3d_scale = 0.70
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED

	# Camera rig is persistent across resets
	rig = CameraRig.new()
	add_child(rig)
	if mobile and rig.has_method("set_mobile_defaults"):
		rig.set_mobile_defaults()

	reset_simulation()

func reset_simulation() -> void:
	# 1. Tear down old nodes immediately to prevent UI overlap/interaction issues
	if is_instance_valid(builder):
		remove_child(builder)
		builder.queue_free()
	if is_instance_valid(dash):
		remove_child(dash)
		dash.queue_free()
	if is_instance_valid(air_traffic):
		remove_child(air_traffic)
		air_traffic.queue_free()

	# 2. Create brand new simulation state
	sim = CitySim.new()
	sim.generate(randi())

	# 3. Rebuild the visuals
	builder = CityBuilder.new()
	add_child(builder)
	builder.setup(sim, mobile)

	# 4. Rebuild the planes
	air_traffic = AirTraffic.new()
	add_child(air_traffic)
	air_traffic.setup()

	# 5. Rebuild the dashboard
	dash = Dashboard.new()
	add_child(dash)
	dash.setup(sim, self, mobile)

	# 6. Fast-forward 48 hours so the graphs have initial data
	for i in 48:
		sim.step_hour()

	builder.refresh_all()
	dash._refresh()

func _process(delta: float) -> void:
	var hps: float = dash.speed_hours_per_second()
	air_traffic.paused = (hps <= 0.0)
	air_traffic.sim_speed = hps

	if hps > 0.0:
		_accum += delta * hps
		var steps := 0
		while _accum >= 1.0 and steps < MAX_STEPS_PER_FRAME:
			sim.step_hour()
			_accum -= 1.0
			steps += 1
		if _accum > 2.0:
			_accum = 0.0

	builder.tick_agents(delta, hps)
	builder.refresh_buildings_smooth()

	dash.tick(delta)

func set_overlay(index: int) -> void:
	builder.set_overlay(index)

func set_force_night(on: bool) -> void:
	builder.set_day_mode(on)

func set_weather_visuals(enabled: bool) -> void:
	builder.set_weather_visuals(enabled)
