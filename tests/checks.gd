extends Node3D

var failures := 0
var phases: Array = []
var mouse_edges := 0


func _ready() -> void:
	var button: Button = get_node("Camera/dialogue UI/menu ui/Select")
	button.pressed.connect(func(): button.text = "Selected")
	if OS.get_cmdline_user_args().has("--test-input"):
		call_deferred("_run")


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		mouse_edges += 1


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)


func _run() -> void:
	var bootstrap := get_node("/root/Bootstrap")
	_check(not get_viewport().use_xr and $Camera.is_current(), "desktop startup")
	var right := XRPositionalTracker.new()
	right.type = XRServer.TRACKER_CONTROLLER
	right.name = &"right_hand"
	XRServer.add_tracker(right)
	var aim := Transform3D(Basis(Vector3.UP, PI), Vector3(0.2, 1.0, -0.3))
	right.set_pose(&"aim", aim, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	# Exercise the actual rig, anchor, input handlers and lifecycle without a compositor.
	bootstrap.target_scene = bootstrap.TEST_ROOM
	bootstrap._process(0.0)
	var rig: XROrigin3D = bootstrap.rig
	var hand: XRController3D = rig.get_node("Right")
	hand.select_changed.connect(func(phase): phases.append(phase))
	_check(rig.get_node("Head").is_current() and get_viewport().use_xr, "camera handover")
	_check(hand.tracker == &"right_hand" and hand.pose == &"aim" and hand.transform.is_equal_approx(aim), "right aim pose")
	_check(rig.get_node("Left").tracker == &"left_hand" and rig.get_node("Left").pose == &"grip", "independent left grip")
	var glove = rig.get_node("RightGlove")
	var grip_pose := Transform3D(Basis.IDENTITY, Vector3(0.15, 0.95, -0.25))
	right.set_pose(&"grip", grip_pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	glove.sample(true)
	_check(glove.visible and glove.transform.is_equal_approx(grip_pose) and hand.transform.is_equal_approx(aim), "glove follows grip independently of aim")
	hand.sample(true)
	var pointing: Transform3D = hand.pointer_pose()
	var base: Vector3 = glove.knuckles[0].global_position
	var tip: Vector3 = glove.tips[0].to_global(Vector3.FORWARD * 0.083 * 0.49)
	_check(pointing.origin.distance_to(tip) < 0.0001 and (tip-base).normalized().dot(-pointing.basis.z) > 0.99999, "beam starts at the rendered index fingertip along its length")
	var beam: MeshInstance3D = hand.get_node("Direction")
	var beam_start := beam.to_global(Vector3.BACK * 0.095)
	_check(beam_start.distance_to(tip) < 0.0001 and beam.global_transform.basis.z.normalized().dot(pointing.basis.z) > 0.99999, "beam mesh and index ray coincide")
	_check(glove.shell.basis.is_equal_approx(Basis(Vector3.BACK, Vector3.RIGHT, Vector3.UP)) and (-pointing.basis.z).dot(Vector3.DOWN) > 0.90,
		"original fallback wrist orientation is preserved and the index can point down")
	var index_rest: float = glove.knuckles[0].rotation.x
	var middle_rest: float = glove.knuckles[1].rotation.x
	right.set_input(&"trigger", 1.0)
	glove.sample(true)
	_check(glove.knuckles[0].rotation.x < index_rest and is_equal_approx(glove.knuckles[1].rotation.x, middle_rest), "index finger responds to trigger independently")
	right.set_input(&"grip", 1.0)
	glove.sample(true)
	_check(glove.knuckles[1].rotation.x < middle_rest, "squeeze curls the other fingers")
	_check(hand.pointer_pose().is_equal_approx(pointing), "visual trigger and squeeze leave the pointer stable")
	glove.sample(false)
	_check(not glove.visible, "unfocused glove hidden")
	var head := Transform3D(Basis(Vector3.UP, 0.8), Vector3(0.1, 1.58, -0.2))
	bootstrap._align($Camera.global_transform, head)
	var eye: Transform3D = rig.global_transform * head
	_check(eye.origin.is_equal_approx($Camera.global_position) and eye.basis.z.is_equal_approx(Vector3.BACK), "seated eye position and yaw")
	var hmd: XRCamera3D = rig.get_node("Head")
	bootstrap._calibrate(hmd)
	hmd.position += Vector3(.25, -.1, .08)
	bootstrap._align($Camera.global_transform, bootstrap.calibration)
	var before_turn := hmd.global_transform
	for frame in range(90):
		bootstrap._turn(1.0, 1.0 / 90.0, hmd)
		bootstrap._align($Camera.global_transform, bootstrap.calibration)
	_check(hmd.global_position.distance_to(before_turn.origin) < .0001, "stick turn pivots around the leaned eye")
	_check(hmd.global_transform.basis.z.is_equal_approx(before_turn.basis.z.rotated(Vector3.UP, deg_to_rad(-40.0))), "right stick turns smoothly clockwise at 40 degrees per second")
	bootstrap._turn(.15, .05, hmd)
	_check(is_equal_approx(bootstrap.stick_yaw, deg_to_rad(-40.0)), "turn deadzone")
	bootstrap._turn(-1.0, .05, hmd)
	_check(is_equal_approx(bootstrap.stick_yaw, deg_to_rad(-38.0)), "left turn reverses yaw")
	right.set_input(&"primary", Vector2.RIGHT)
	_check(hand.primary_stick(false, .22) == Vector2.ZERO and hand.primary_stick(true, .22) == Vector2.ZERO, "held right stick suppressed after focus loss")
	right.set_input(&"primary", Vector2.ZERO)
	hand.primary_stick(true, .22)
	right.set_input(&"primary", Vector2.LEFT)
	_check(hand.primary_stick(true, .22) == Vector2.LEFT, "right primary stick accepts fresh motion")
	bootstrap._calibrate(hmd)
	bootstrap._align($Camera.global_transform, bootstrap.calibration)
	hand.sample(true)
	right.set_input(&"grip_click", true)
	right.set_input(&"trigger", 0.85)
	_check(phases.is_empty(), "unrelated boolean and analog inputs ignored")
	right.set_input(&"trigger_click", true)
	hand.sample(true)
	right.set_input(&"trigger_click", true)
	right.set_input(&"trigger_click", false)
	_check(phases == ["press", "release"], "one complete trigger cycle")
	right.set_input(&"trigger_click", true)
	bootstrap._set_focus(false)
	hand.sample(true)
	right.set_input(&"trigger_click", false)
	_check(phases == ["press", "release", "press", "cancel"], "focus loss cancels; held input cannot re-arm")
	right.set_input(&"trigger_click", true)
	right.invalidate_pose(&"grip")
	hand.sample(true)
	_check(hand.visible and phases.back() == "cancel" and not hand.armed and hand.pointer_pose().is_equal_approx(hand.global_transform), "grip loss cancels the press and falls back to tracked aim")
	right.invalidate_pose(&"aim")
	hand.sample(true)
	_check(not hand.visible and not beam.visible and not hand.can_point(), "both poses lost hides beam and blocks selection")
	right.set_pose(&"aim", aim, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	hand.sample(true)
	right.set_input(&"trigger_click", false)
	right.set_input(&"trigger_click", true)
	right.set_input(&"trigger_click", false)
	_check(phases == ["press", "release", "press", "cancel", "press", "cancel", "press", "release"], "fresh press after tracking recovery")
	var left := XRPositionalTracker.new()
	left.type = XRServer.TRACKER_CONTROLLER
	left.name = &"left_hand"
	XRServer.add_tracker(left)
	var grip := Transform3D(Basis.IDENTITY, Vector3(-0.3, 1.15, -0.22))
	left.set_pose(&"grip", grip, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	var left_hand = rig.get_node("Left")
	left_hand.sample(true)
	left.set_input(&"trigger_click", true)
	_check(left_hand.held and not hand.held and left_hand.transform.is_equal_approx(grip) and hand.transform.is_equal_approx(aim), "separate poses and trigger ownership")
	left.set_input(&"trigger_click", false)
	XRServer.remove_tracker(left)
	_check(mouse_edges == 0, "tracking and out-of-panel triggers produce no GUI clicks")
	var panel = bootstrap.menu_panel
	var target_button: Button = get_node("Camera/dialogue UI/menu ui/Select")
	var button_point := Vector3(0, (0.5 - 390.0 / 540.0) * panel.HEIGHT, 0.5)
	var world_aim: Transform3D = panel.global_transform * Transform3D(Basis.IDENTITY, button_point)
	var local_grip: Transform3D = rig.global_transform.affine_inverse() * world_aim * glove.index_ray.affine_inverse()
	right.set_pose(&"grip", local_grip, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	hand.sample(true)
	panel.update_pointer(true)
	_check(panel.last_pixel.distance_to(Vector2(480, 390)) < 0.01, "index ray selects the authored canvas pixel even when native aim points away")
	right.set_input(&"trigger_click", true)
	hand.sample(false)
	_check(target_button.text == "Test selection" and not panel.pressed, "focus loss cancels the captured GUI press")
	hand.sample(true)
	right.set_input(&"trigger_click", false)
	right.set_input(&"trigger_click", true)
	right.set_input(&"trigger_click", false)
	_check(target_button.text == "Selected" and mouse_edges == 4, "one GUI down and up per captured press")
	var original_mask: int = panel.original_mask
	bootstrap._stop_session()
	_check($Camera.is_current() and not get_viewport().use_xr and bootstrap.rig == null, "session stop restores desktop")
	_check(get_viewport().canvas_cull_mask == original_mask and target_button.visibility_layer == 1, "flat canvas and control layer restored")
	XRServer.remove_tracker(right)
	await get_tree().process_frame
	_check(not is_instance_valid(rig), "rig cleanup")
	bootstrap.target_scene = bootstrap.MENU
	bootstrap._begin_session()
	bootstrap._process(0.0)
	_check(bootstrap.rig == null and $Camera.is_current(), "unknown scene stays flat")
	var transient := Node3D.new()
	var other_camera := Camera3D.new()
	transient.add_child(other_camera)
	add_child(transient)
	other_camera.make_current()
	bootstrap._attach(transient, other_camera)
	remove_child(transient)
	_check(bootstrap.rig == null and not get_viewport().use_xr, "scene exit detaches active rig")
	transient.free()
	var station = preload("res://mods-unpacked/TableVR-Bootstrap/view_station.gd").new()
	station.units = 10.0
	station.desk = Transform3D(Basis(Vector3.UP, -PI/2), Vector3(5, 2, 9))
	station._lock_table()
	_check(station.update(Vector2(.1,.1), .016).is_equal_approx(station.desk), "stick deadzone keeps the desk fixed")
	var moved: Transform3D = station.update(Vector2(0, -1), 0.045)
	_check(moved.is_equal_approx(station.desk), "full stick deflection cannot move the table view")
	for i in range(400):
		station.update(Vector2(1, 0), .05, Vector3.RIGHT)
	_check(station.station.is_equal_approx(station.desk), "sustained sideways stick keeps the desk fixed")
	print("TABLEVR_TEST_RESULT failures=", failures)
	get_tree().quit(1 if failures else 0)
