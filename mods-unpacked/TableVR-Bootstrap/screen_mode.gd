extends "res://mods-unpacked/TableVR-Bootstrap/menu_panel.gd"

# Compatibility presentation for the separate multiplayer scene family.
# The native game retains Steam, UI, turn permissions and action dispatch.
const SCREEN_LAYER := 1 << 19
const RAY_SCRIPT := "res://multiplayer/scripts/user scripts/MP_MouseRaycast.gd"
var desktop: Camera3D
var capture: Camera3D
var head: XRCamera3D
var old_process := {}
var menu_armed := false
var menu_down := false
var allowed := false
var station := Transform3D.IDENTITY
var look_down := false
var look_armed := false

func mount_screen(scene: Node, camera: Camera3D, right: XRController3D) -> void:
	super.mount(scene, camera, right)
	desktop = camera
	station = camera.global_transform
	head = get_parent().get_node("Head")
	head.cull_mask = SCREEN_LAYER
	var backdrop := Environment.new()
	backdrop.background_mode = Environment.BG_COLOR
	backdrop.background_color = Color(.008, .008, .008)
	head.environment = backdrop
	surface.disable_3d = false
	surface.transparent_bg = false
	surface.world_3d = root_view.world_3d
	# Include dynamically created lobby controls and the active player's UI.
	surface.canvas_cull_mask = original_mask
	capture = Camera3D.new()
	surface.add_child(capture)
	capture.make_current()
	var caption := Label3D.new()
	caption.text = "MULTIPLAYER  /  SCREEN MODE"
	caption.font_size = 40
	caption.pixel_size = .0008
	caption.position = Vector3(0, -HEIGHT / 2 - .065, .004)
	caption.no_depth_test = true
	caption.render_priority = 3
	add_child(caption)
	update_screen(false)
	print("[TableVR] multiplayer screen mode attached")

func update_screen(value: bool) -> void:
	allowed = value
	# A newly spawned local user or outro can select another native camera.
	var selected := root_view.get_camera_3d()
	if selected != null and selected != head: desktop = selected
	if is_instance_valid(desktop):
		capture.global_transform = desktop.global_transform
		for property in [&"projection", &"keep_aspect", &"fov", &"size", &"frustum_offset", &"h_offset", &"v_offset", &"near", &"far", &"environment", &"attributes"]:
			capture.set(property, desktop.get(property))
		capture.cull_mask = desktop.cull_mask & ~SCREEN_LAYER
		if desktop.get_script() != null and desktop.get_script().resource_path == RAY_SCRIPT:
			if not old_process.has(desktop):
				old_process[desktop] = desktop.is_processing()
				desktop.set_process(false)
			_update_ray()
	head.make_current()
	for visual in get_parent().find_children("*", "VisualInstance3D", true, false):
		visual.layers = SCREEN_LAYER
	var left: XRController3D = get_parent().get_node("LeftGlove")
	var tracked := left.get_has_tracking_data()
	var pressed_menu := left.is_button_pressed(&"menu_button")
	var tracker := XRServer.get_tracker(left.tracker)
	if tracker != null and tracker.profile == "/interaction_profiles/valve/index_controller":
		pressed_menu = pressed_menu or left.is_button_pressed(&"primary_click")
	if not allowed or not tracked:
		menu_armed = false
		if menu_down: _menu_event(false)
	elif not pressed_menu:
		menu_armed = true
		if menu_down: _menu_event(false)
	elif menu_armed and not menu_down:
		menu_armed = false
		_menu_event(true)
	var right: XRController3D = get_parent().get_node("RightGlove")
	var grip := right.get_float(&"grip")
	if not allowed or not right.get_has_tracking_data():
		look_armed = false
		if look_down: _look_event(false)
	elif grip < .30:
		look_armed = true
		if look_down: _look_event(false)
	elif grip > .65 and look_armed and not look_down:
		look_armed = false
		_look_event(true)

func _look_event(down: bool) -> void:
	look_down = down
	var event := InputEventAction.new()
	event.action = &"free look toggle"
	event.pressed = down
	root_view.push_input(event, true)

func _menu_event(down: bool) -> void:
	menu_down = down
	var event := InputEventAction.new()
	event.action = &"exit game"
	event.pressed = down
	root_view.push_input(event, true)

func _update_ray() -> void:
	if desktop.get_script() == null or desktop.get_script().resource_path != RAY_SCRIPT: return
	if not allowed or last_pixel == OUTSIDE or not desktop.properties.is_active or not desktop.getting_selection:
		desktop.result = {}
	else:
		# The native ray camera belongs to the XR viewport. Use the screen camera's
		# projection for 960x540 mouse coordinates, keeping native hover/dispatch.
		var start := capture.project_ray_origin(last_pixel)
		var end := start + capture.project_ray_normal(last_pixel) * 20000.0
		desktop.result = desktop.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, end))
	desktop.properties.interaction.CheckPickupLerp()
	desktop.properties.interaction.CheckInteractionBranch()

func _send_gui(event: InputEvent) -> void:
	if is_instance_valid(desktop) and is_instance_valid(capture): _update_ray()
	super._send_gui(event)

func unmount() -> void:
	if menu_down and is_instance_valid(root_view): _menu_event(false)
	if look_down and is_instance_valid(root_view): _look_event(false)
	# Release the shared world before the native scene removes its cameras and
	# environment. A render viewport must not outlive those scene-owned objects.
	if is_instance_valid(surface):
		surface.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if is_instance_valid(capture):
			capture.clear_current(false)
			capture.environment = null
		surface.world_3d = World3D.new()
		surface.world_2d = World2D.new()
	for camera in old_process:
		if is_instance_valid(camera): camera.set_process(old_process[camera])
	old_process.clear()
	super.unmount()
	if is_instance_valid(desktop) and desktop.is_inside_tree(): desktop.make_current()
