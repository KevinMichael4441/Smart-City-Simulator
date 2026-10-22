extends Node3D

const MAX_STEPS_PER_FRAME := 8
const SAVE_PATH := "user://savegame.save"

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

	rig = CameraRig.new()
	add_child(rig)
	if mobile and rig.has_method("set_mobile_defaults"):
		rig.set_mobile_defaults()

	# Try to load, otherwise generate new
	sim = CitySim.new()
	if sim.load_game(SAVE_PATH):
		print("Save game loaded successfully.")
	else:
		print("No save found. Generating new city.")
		sim.generate(randi())

	_build_visuals()
	_fast_forward(48)

func _build_visuals() -> void:
	# Clean up if this is called from a reset
	if is_instance_valid(builder): remove_child(builder); builder.queue_free()
	if is_instance_valid(dash): remove_child(dash); dash.queue_free()
	if is_instance_valid(air_traffic): remove_child(air_traffic); air_traffic.queue_free()

	builder = CityBuilder.new()
	add_child(builder)
	builder.setup(sim, mobile)

	air_traffic = AirTraffic.new()
	add_child(air_traffic)
	air_traffic.setup()

	dash = Dashboard.new()
	add_child(dash)
	dash.setup(sim, self, mobile)

func _fast_forward(hours: int) -> void:
	for i in hours:
		sim.step_hour()
	builder.refresh_all()
	dash._refresh()

func reset_simulation() -> void:
	if is_instance_valid(sim): sim.save_game(SAVE_PATH) # Backup before wiping
	sim = CitySim.new()
	sim.generate(randi())
	_build_visuals()
	_fast_forward(48)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_instance_valid(sim):
			sim.save_game(SAVE_PATH)
		get_tree().quit()

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

func export_report() -> void:
	ReportGenerator.export(sim)
	var abs_path := ProjectSettings.globalize_path("user://city_report.html")
	OS.shell_open(abs_path)

func manual_save() -> void:
	sim.save_game(SAVE_PATH)
