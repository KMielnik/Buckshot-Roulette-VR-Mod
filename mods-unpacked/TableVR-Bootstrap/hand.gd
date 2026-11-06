extends XRController3D

signal select_changed(phase)

enum RaySource { LOST, CONTROLLER, FINGER }
const BEAM_LENGTH_METRES := 0.19
@onready var glove = get_node_or_null("../RightGlove") if tracker == &"right_hand" else null
@onready var beam := get_node_or_null("Direction") as MeshInstance3D
var ray_source := RaySource.LOST
var source_revision := 0
var focused := false
var armed := false
var held := false
var stick_armed := false
var cuffs: Node


func _ready() -> void:
	visible = false
	button_pressed.connect(_pressed)
	button_released.connect(_released)


func sample(can_interact: bool) -> void:
	var current := _tracking_source()
	if current != ray_source:
		ray_source = current
		source_revision += 1
		armed = false
		if held:
			_set_held(false, "cancel")
	focused = can_interact and current != RaySource.LOST and not _bound()
	if focused != visible:
		var device := XRServer.get_tracker(tracker)
		print("[TableVR] ", tracker, " input_active=", focused, " profile=", device.profile if device != null else "")
	visible = focused
	if not focused:
		armed = false
		stick_armed = false
		if held:
			_set_held(false, "cancel")
	elif not held and not is_button_pressed(&"trigger_click"):
		# A held trigger across tracking/focus loss must return to neutral.
		armed = true
	if beam != null:
		beam.visible = focused
		if focused:
			var frame := pointer_pose()
			var units := XRServer.world_scale
			beam.global_transform = Transform3D(frame.basis.scaled(Vector3.ONE * units),
				frame.origin - frame.basis.z * (0.5 * BEAM_LENGTH_METRES * units))


func _tracking_source() -> RaySource:
	if glove != null and glove.get_has_tracking_data():
		return RaySource.FINGER
	return RaySource.CONTROLLER if get_has_tracking_data() else RaySource.LOST


func can_point() -> bool:
	return focused and not _bound() and ray_source != RaySource.LOST and _tracking_source() == ray_source


func _bound() -> bool:
	return is_instance_valid(cuffs) and cuffs.is_bound()


func pointer_pose() -> Transform3D:
	if ray_source == RaySource.FINGER:
		return (glove.global_transform * glove.index_ray).orthonormalized()
	return global_transform.orthonormalized()


func primary_stick(enabled: bool, deadzone: float) -> Vector2:
	if not enabled or _tracking_source() == RaySource.LOST:
		stick_armed = false
		return Vector2.ZERO
	var raw := get_vector2(&"primary")
	if raw.length() <= deadzone:
		stick_armed = true
	return raw if stick_armed else Vector2.ZERO


func _pressed(action: String) -> void:
	if action == "trigger_click" and armed and can_point():
		armed = false
		_set_held(true, "press")


func _released(action: String) -> void:
	if action != "trigger_click":
		return
	if held:
		_set_held(false, "release" if can_point() else "cancel")
	armed = can_point()


func _set_held(value: bool, phase: String) -> void:
	held = value
	select_changed.emit(phase)
