extends Node
const Screen := preload("res://mods-unpacked/TableVR-Bootstrap/screen_mode.gd")

var failures := 0
var mod: Node
var trace: FileAccess

func _ready() -> void:
	trace = FileAccess.open("user://screen-progress.txt", FileAccess.WRITE)
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("SCREEN_QA ", "PASS " if ok else "FAIL ", label)
	trace.store_line(("PASS " if ok else "FAIL ") + label)
	trace.flush()

func enter(path: String) -> void:
	trace.store_line("Entering " + path)
	trace.flush()
	get_tree().change_scene_to_file(path)
	while get_tree().current_scene == null or get_tree().current_scene.scene_file_path != path:
		await get_tree().process_frame
	mod._process(0)
	mod.focused = true
	mod.needs_anchor = false
	mod.calibration = Transform3D.IDENTITY

func snapshot(label: String) -> void:
	var directory := OS.get_environment("BUCKSHOT_VR_QA_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless": return
	# No XR session in this offline test. A separate preview camera inspects
	# screen placement without changing the root viewport's rendering mode.
	var preview := SubViewport.new()
	preview.size = Vector2i(960,540)
	preview.world_3d = get_viewport().world_3d
	preview.canvas_cull_mask = 0
	preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(preview)
	var eye := Camera3D.new()
	preview.add_child(eye)
	eye.global_transform = mod.rig.get_node("Head").global_transform
	eye.environment = mod.rig.get_node("Head").environment
	eye.cull_mask = Screen.SCREEN_LAYER
	eye.make_current()
	await RenderingServer.frame_post_draw
	mod.menu_panel.surface.get_texture().get_image().save_png(directory.path_join(label + "-content.png"))
	preview.get_texture().get_image().save_png(directory.path_join(label + "-view.png"))
	preview.queue_free()

func _run() -> void:
	mod = get_node("/root/ModLoader/TableVR-Bootstrap")
	GlobalVariables.running_short_intro_in_lobby_scene = true
	await enter("res://multiplayer/scenes/mp_lobby.tscn")
	var screen = mod.menu_panel
	check(screen is Screen and get_viewport().use_xr, "lobby keeps XR rendering instead of detaching to black")
	check(screen.capture.get_world_3d() == screen.desktop.get_world_3d() and screen.surface.world_2d == get_viewport().world_2d and not screen.surface.disable_3d, "screen captures the native world and original canvas")
	var fixed_frame: Transform3D = screen.global_transform
	var fixed_rig: Transform3D = mod.rig.global_transform
	for tick in 300:
		await get_tree().process_frame
		mod._process(1.0/90)
	check(screen.global_transform.is_equal_approx(fixed_frame) and mod.rig.global_transform.is_equal_approx(fixed_rig), "lobby camera motion cannot move the physical screen or VR seat")
	check(screen.head.cull_mask == Screen.SCREEN_LAYER and (screen.capture.cull_mask & Screen.SCREEN_LAYER) == 0, "headset and capture cameras cannot see each other's geometry")
	await snapshot("lobby")
	var lobby_ui := get_tree().current_scene.get_node("standalone managers/lobby ui")
	# A native non-network action exercises the actual GUI event path.
	lobby_ui.ShowPopupWindow("VR screen input check")
	for tick in 60: await get_tree().process_frame
	var button: Control = lobby_ui.button_class_popup_close
	var pixel := button.get_global_rect().get_center()
	screen._move(pixel)
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = pixel
		click.pressed = down
		screen._send_gui(click)
	check(not lobby_ui.lobby.viewing_popup, "screen pointer closes the native popup through its own button")
	await enter("res://multiplayer/scenes/buffer_scene.tscn")
	check(mod.menu_panel is Screen, "intermediate multiplayer scene also retains an XR screen")
	await enter("res://multiplayer/scenes/mp_main.tscn")
	screen = mod.menu_panel
	check(screen is Screen, "match scene has an XR screen before a player is spawned")
	var handler := get_tree().current_scene.get_node("standalone managers/initial setup/user instance handler")
	# A local instance only: no lobby, network connection or gameplay request.
	handler.SetupInstances([{"socket_number": 0, "user_id": GlobalSteam.STEAM_ID, "cpu_enabled": false}])
	for tick in 3: await get_tree().process_frame
	var local = handler.instance_property_array[0]
	local.mouse_raycast.make_current()
	mod._process(0)
	check(screen.desktop == local.mouse_raycast and screen.head.is_current() and not local.mouse_raycast.is_processing(), "new local camera is captured and its old mouse projection is suspended")
	check(screen.capture.global_transform.is_equal_approx(local.mouse_raycast.global_transform), "screen follows the native local view inside the fixed panel")
	var target := Node3D.new()
	get_tree().current_scene.add_child(target)
	target.global_position = screen.capture.global_transform * Vector3(.08,.06,-.4)
	var body := StaticBody3D.new()
	target.add_child(body)
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = .025
	body.add_child(shape)
	var branch = load("res://multiplayer/scripts/global scripts/MP_InteractionBranch.gd").new()
	branch.interactionAlias = "QA inert target"
	branch.interactionAllowed = true
	target.add_child(branch)
	local.cursor.SetCursor(true, false)
	local.mouse_raycast.getting_selection = true
	local.major_permission_enabled = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	screen.last_pixel = screen.capture.unproject_position(target.global_position)
	screen._update_ray()
	check(local.mouse_raycast.result.get("collider") == body and local.interaction.activeInteractionBranch == branch, "capture projection resolves an off-centre hit through native hover logic")
	local.major_permission_enabled = false
	screen._update_ray()
	check(not local.major_permission_enabled, "ray projection preserves the native permission gate")
	local.major_permission_enabled = true
	screen.update_screen(false)
	check(local.mouse_raycast.result.is_empty() and local.interaction.activeInteractionBranch == null, "focus loss clears the screen target")
	screen.update_screen(true)
	local.is_allowed_to_free_look = true
	screen._look_event(true)
	check(local.camera_look.looking_active, "grip action enters native free look when permitted")
	screen._look_event(false)
	check(not local.camera_look.looking_active, "grip release leaves native free look")
	screen._menu_event(true)
	screen._menu_event(false)
	check(local.intermediary.ingame_lobby_ui.viewing_ui and not get_tree().paused, "menu action opens the native multiplayer menu without pausing a match")
	await snapshot("match-menu")
	screen._menu_event(true)
	screen._menu_event(false)
	check(not local.intermediary.ingame_lobby_ui.viewing_ui, "menu action can close the native multiplayer menu")
	mod._detach()
	check(local.mouse_raycast.is_processing() and local.mouse_raycast.is_current() and not get_viewport().use_xr, "detach restores local desktop camera and ray processing")
	await enter(mod.MENU)
	check(mod.menu_panel != null and not mod.menu_panel is Screen and mod.rig.get_node("Head").cull_mask != Screen.SCREEN_LAYER, "return to title restores immersive presentation")
	print("SCREEN_QA failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
