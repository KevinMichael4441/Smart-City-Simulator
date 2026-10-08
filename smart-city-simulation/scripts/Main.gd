extends Node3D

const SPEEDS := [0.0, 1.0, 3.0, 12.0, 48.0]

var sim: CitySim
var builder: CityBuilder
var rig: CameraRig
var dash: Dashboard

var _accum := 0.0
var _visual_timer := 0.0

func _ready() -> void:
	sim = CitySim.new()
	sim.generate(randi())

	builder = CityBuilder.new()
	add_child(builder)
	builder.setup(sim)

	rig = CameraRig.new()
	add_child(rig)

	dash = Dashboard.new()
	add_child(dash)
	dash.setup(sim, self)

	# settle the economy before the first frame
	for i in 48:
		sim.step_hour()

	builder.refresh_all()
	dash.refresh()

func _process(delta: float) -> void:
	var hps: float = dash.speed_hours_per_second()
	if hps > 0.0:
		_accum += delta * hps
		var steps := 0
		while _accum >= 1.0 and steps < 240:
			sim.step_hour()
			_accum -= 1.0
			steps += 1
		if steps >= 240:
			_accum = 0.0

	_visual_timer += delta
	if _visual_timer >= 0.20:
		_visual_timer = 0.0
		builder._refresh_sun()
		if sim.tick % CitySim.HOURS_PER_DAY < 4:
			builder._refresh_buildings()

	dash.refresh()

func set_overlay(index: int) -> void:
	builder.set_overlay(index)
