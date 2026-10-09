class_name CameraRig
extends Node3D

var pivot: Node3D
var cam: Camera3D

var _yaw := 0.0
var _pitch := -52.0
var _dist := 780.0
var _target := Vector3.ZERO
var _orbiting := false
var _panning := false

func _ready() -> void:
	pivot = Node3D.new()
	add_child(pivot)

	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 1.0
	cam.far = 4000.0
	pivot.add_child(cam)

	_apply()

func set_mobile_defaults() -> void:
	_dist = 780.0
	_pitch = -58.0
	_apply()

func _apply() -> void:
	pivot.position = _target
	pivot.rotation_degrees = Vector3(_pitch, _yaw, 0.0)
	cam.position = Vector3(0, 0, _dist)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_dist = clampf(_dist * 0.88, 90.0, 2200.0)
			_apply()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_dist = clampf(_dist * 1.14, 90.0, 2200.0)
			_apply()

	elif event is InputEventMouseMotion:
		if _orbiting:
			_yaw -= event.relative.x * 0.28
			_pitch = clampf(_pitch - event.relative.y * 0.22, -88.0, -12.0)
			_apply()
		elif _panning:
			var right := Vector3(cos(deg_to_rad(_yaw)), 0, -sin(deg_to_rad(_yaw)))
			var fwd := Vector3(sin(deg_to_rad(_yaw)), 0, cos(deg_to_rad(_yaw)))
			var speed := _dist * 0.0016
			_target -= right * event.relative.x * speed
			_target -= fwd * event.relative.y * speed
			_apply()

	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().quit()
