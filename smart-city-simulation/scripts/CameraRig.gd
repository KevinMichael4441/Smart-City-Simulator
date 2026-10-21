class_name CameraRig
extends Node3D

var pivot: Node3D
var cam: Camera3D

# ── camera state ─────────────────────────────────────────────
var _yaw := 0.0
var _pitch := -52.0
var _dist := 780.0
var _target := Vector3.ZERO

# smoothed targets — the camera eases toward these every frame
var _yaw_target := 0.0
var _pitch_target := -52.0
var _dist_target := 780.0
var _target_target := Vector3.ZERO

# ── input state ──────────────────────────────────────────────
var _orbiting := false
var _panning := false

# ── touch ────────────────────────────────────────────────────
var _touches: Dictionary = {}
var _touch_panning := false
var _touch_orbiting := false
var _touch_last_center := Vector2.ZERO
var _touch_last_spread := 0.0

# ── tuning ───────────────────────────────────────────────────
const ZOOM_MIN := 90.0
const ZOOM_MAX := 2200.0
const ZOOM_IN_STEP := 0.88
const ZOOM_OUT_STEP := 1.14
const PITCH_MIN := -88.0
const PITCH_MAX := -12.0
const KEY_PAN_SPEED := 900.0
const DAMPING := 14.0

func _ready() -> void:
	pivot = Node3D.new()
	add_child(pivot)

	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 1.0
	cam.far = 4000.0
	pivot.add_child(cam)

	_yaw_target = _yaw
	_pitch_target = _pitch
	_dist_target = _dist
	_target_target = _target

	_apply()

func set_mobile_defaults() -> void:
	_dist = 780.0
	_dist_target = 780.0
	_pitch = -58.0
	_pitch_target = -58.0
	_apply()

func _apply() -> void:
	pivot.position = _target
	pivot.rotation_degrees = Vector3(_pitch, _yaw, 0.0)
	cam.position = Vector3(0, 0, _dist)

func _process(delta: float) -> void:
	_handle_keyboard(delta)

	var t: float = 1.0 - exp(-DAMPING * delta)
	_yaw = lerp_angle(_yaw, _yaw_target, t)
	_pitch = lerpf(_pitch, _pitch_target, t)
	_dist = lerpf(_dist, _dist_target, t)
	_target = _target.lerp(_target_target, t)

	_apply()

func _handle_keyboard(delta: float) -> void:
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): pan.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): pan.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): pan.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): pan.x += 1.0

	if pan.length_squared() > 0.0:
		pan = pan.normalized()
		var speed: float = KEY_PAN_SPEED * (_dist / 780.0)
		if Input.is_key_pressed(KEY_SHIFT): speed *= 2.5
		var right := Vector3(cos(deg_to_rad(_yaw)), 0, -sin(deg_to_rad(_yaw)))
		var fwd := Vector3(sin(deg_to_rad(_yaw)), 0, cos(deg_to_rad(_yaw)))
		_target_target += (-right * pan.x + fwd * pan.y) * speed * delta

	if Input.is_key_pressed(KEY_Q): _yaw_target += 90.0 * delta
	if Input.is_key_pressed(KEY_E): _yaw_target -= 90.0 * delta
	if Input.is_key_pressed(KEY_R): _pitch_target = clampf(_pitch_target + 60.0 * delta, PITCH_MIN, PITCH_MAX)
	if Input.is_key_pressed(KEY_F): _pitch_target = clampf(_pitch_target - 60.0 * delta, PITCH_MIN, PITCH_MAX)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist_target = clampf(_dist_target * ZOOM_IN_STEP, ZOOM_MIN, ZOOM_MAX)
			get_viewport().set_input_as_handled()

		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist_target = clampf(_dist_target * ZOOM_OUT_STEP, ZOOM_MIN, ZOOM_MAX)
			get_viewport().set_input_as_handled()

		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				if _is_pointer_over_ui(mb.position): return
				_panning = true
			else:
				_panning = false

		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if _is_pointer_over_ui(mb.position): return
				_orbiting = true
			else:
				_orbiting = false

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _orbiting:
			# Direct, snappy orbit (bypasses smoothing)
			_yaw -= mm.relative.x * 0.28
			_pitch = clampf(_pitch - mm.relative.y * 0.22, PITCH_MIN, PITCH_MAX)
			_yaw_target = _yaw
			_pitch_target = _pitch
			_apply()
		elif _panning:
			_apply_pan(mm.relative)

	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE: get_tree().quit()

	elif event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_touch_drag(event)

func _apply_pan(delta_px: Vector2) -> void:
	var speed: float = _dist * 0.0016
	var right := Vector3(cos(deg_to_rad(_yaw)), 0, -sin(deg_to_rad(_yaw)))
	var fwd := Vector3(sin(deg_to_rad(_yaw)), 0, cos(deg_to_rad(_yaw)))
	_target_target -= right * delta_px.x * speed
	_target_target -= fwd * delta_px.y * speed

func _is_pointer_over_ui(pos: Vector2) -> bool:
	return _hit_test_ui(get_tree().root, pos)

func _hit_test_ui(node: Node, pos: Vector2) -> bool:
	if node is Control:
		var c: Control = node
		if c.visible and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			if c.get_global_rect().has_point(pos): return true
	for child in node.get_children():
		if _hit_test_ui(child, pos): return true
	return false

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			_touch_orbiting = true
			_touch_panning = false
			_touch_last_center = _touch_center()
			_touch_last_spread = _touch_spread()
		else:
			if not _is_pointer_over_ui(event.position):
				_touch_panning = true
				_touch_last_center = event.position
	else:
		_touches.erase(event.index)
		if _touches.size() == 0:
			_touch_panning = false
			_touch_orbiting = false
		elif _touches.size() == 1:
			_touch_orbiting = false
			_touch_panning = not _is_pointer_over_ui(_touches.values()[0])
			_touch_last_center = _touches.values()[0]

func _handle_touch_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position
	if _touches.size() >= 2 and _touch_orbiting:
		var center: Vector2 = _touch_center()
		var spread: float = _touch_spread()
		var d: Vector2 = center - _touch_last_center
		_yaw_target -= d.x * 0.28
		_pitch_target = clampf(_pitch_target - d.y * 0.22, PITCH_MIN, PITCH_MAX)
		if _touch_last_spread > 0.0 and spread > 0.0:
			var ratio: float = _touch_last_spread / spread
			_dist_target = clampf(_dist_target * ratio, ZOOM_MIN, ZOOM_MAX)
		_touch_last_center = center
		_touch_last_spread = spread
	elif _touch_panning and _touches.size() == 1:
		_apply_pan(event.relative)

func _touch_center() -> Vector2:
	if _touches.is_empty(): return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in _touches.values(): sum += p
	return sum / float(_touches.size())

func _touch_spread() -> float:
	if _touches.size() < 2: return 0.0
	var vals: Array = _touches.values()
	return (vals[0] - vals[1]).length()
