extends Node

var failures := 0
var mod: Node
var left: XRPositionalTracker
var right: XRPositionalTracker

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("PAUSE_QA ", "PASS " if ok else "FAIL ", label)

func tracker(hand: StringName) -> XRPositionalTracker:
	var t := XRPositionalTracker.new()
	t.type = XRServer.TRACKER_CONTROLLER
	t.name = hand
	t.profile = "/interaction_profiles/valve/index_controller"
	XRServer.add_tracker(t)
	t.set_pose(&"grip", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	return t

func select(row: int) -> void:
	var menu = mod.pause_menu
	var ray: Transform3D = menu.global_transform.orthonormalized()
	ray.origin = menu.to_global(Vector3(0,menu.rows[row].position.y,.4))
	var glove = mod.rig.get_node("RightGlove")
	glove.global_transform = ray * glove.index_ray.affine_inverse()
	for key in [false,true,false]:
		right.set_input(&"trigger_click",key)
		mod._process(.0)

func toggle(key: StringName) -> void:
	for state in [false,true,false]:
		left.set_input(key,state)
		mod._process(.0)

func _run() -> void:
	mod = get_node("/root/ModLoader/TableVR-Bootstrap")
	get_tree().change_scene_to_file(mod.MAIN)
	while get_tree().current_scene == null or get_tree().current_scene.scene_file_path != mod.MAIN:
		await get_tree().process_frame
	left = tracker(&"left_hand")
	right = tracker(&"right_hand")
	mod._process(0)
	mod.focused = true
	mod.needs_anchor = false
	get_tree().paused = true
	toggle(&"menu_button")
	check(mod.pause_menu.opened and get_tree().paused and Engine.time_scale == 0, "left menu opens over an existing scene pause")
	select(0)
	check(not mod.pause_menu.opened and get_tree().paused, "resume restores the previous scene pause")
	get_tree().paused = false
	mod._process(0)
	mod.needs_anchor = false
	Engine.time_scale = .85
	var timer := get_tree().create_timer(.10)
	var before := timer.time_left
	toggle(&"menu_button")
	await get_tree().process_frame # The in-flight frame already owns its delta.
	before = timer.time_left
	for i in 30: await get_tree().process_frame
	print("PAUSE_QA clock ",before," -> ", timer.time_left," paused=",get_tree().paused," selected=",mod.world_pointer.active)
	check(mod.pause_menu.opened and get_tree().paused and is_equal_approx(timer.time_left,before) and not mod.world_pointer.active, "game and process-always timer freeze, world selection is suspended")
	mod.pause_menu.update(false)
	left.set_input(&"menu_button",true)
	mod.pause_menu.update(true)
	check(mod.pause_menu.opened, "held menu button after focus loss cannot close the panel")
	left.set_input(&"menu_button",false)
	select(1)
	check(mod.pause_menu.options, "right pointer opens Options")
	var volume := AudioServer.get_bus_volume_db(0)
	AudioServer.set_bus_volume_db(0,linear_to_db(.6))
	select(0)
	check(absf(db_to_linear(AudioServer.get_bus_volume_db(0))-.5)<.001, "session volume down changes the master bus")
	select(1)
	check(absf(db_to_linear(AudioServer.get_bus_volume_db(0))-.6)<.001, "session volume up changes the master bus")
	AudioServer.set_bus_volume_db(0,volume)
	select(2)
	select(0)
	check(not get_tree().paused and is_equal_approx(Engine.time_scale,.85), "Resume restores native running state and prior speed")
	Engine.time_scale = 1.0
	toggle(&"primary_click")
	check(mod.pause_menu.opened, "Index-profile left stick click is a usable runtime-menu fallback")
	select(2)
	for i in 150:
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == mod.MENU: break
	for i in 5: await get_tree().process_frame
	check(get_tree().current_scene.scene_file_path == mod.MENU and not get_tree().paused, "Main menu uses the retail exit path")
	get_tree().change_scene_to_file(mod.MAIN)
	while get_tree().current_scene == null or get_tree().current_scene.scene_file_path != mod.MAIN: await get_tree().process_frame
	mod._process(0)
	mod.needs_anchor = false
	toggle(&"menu_button")
	check(mod.pause_menu.opened, "pause available after returning to the game")
	print("PAUSE_QA failures=", failures)
	if failures > 0: get_tree().quit(1)
	else: select(3) # A passing runner also requires this actual quit to return zero.
