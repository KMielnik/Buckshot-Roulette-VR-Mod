extends Node

const RIG := preload("res://mods-unpacked/TableVR-Bootstrap/rig.tscn")
const MenuPanel := preload("res://mods-unpacked/TableVR-Bootstrap/menu_panel.gd")
const WorldPointer := preload("res://mods-unpacked/TableVR-Bootstrap/world_pointer.gd")
const ViewStation := preload("res://mods-unpacked/TableVR-Bootstrap/view_station.gd")
const DealerImpact := preload("res://mods-unpacked/TableVR-Bootstrap/dealer_impact.gd")
const PlayerImpact := preload("res://mods-unpacked/TableVR-Bootstrap/player_impact.gd")
const Haptics := preload("res://mods-unpacked/TableVR-Bootstrap/haptics.gd")
const Cuffs := preload("res://mods-unpacked/TableVR-Bootstrap/cuffs.gd")
const TableText := preload("res://mods-unpacked/TableVR-Bootstrap/table_text.gd")
const MenuBullets := preload("res://mods-unpacked/TableVR-Bootstrap/menu_bullets.gd")
const RetailGrade := preload("res://mods-unpacked/TableVR-Bootstrap/retail_grade.gd")
const Finale := preload("res://mods-unpacked/TableVR-Bootstrap/finale.gd")
const PauseMenu := preload("res://mods-unpacked/TableVR-Bootstrap/pause_menu.gd")
const NearInput := preload("res://mods-unpacked/TableVR-Bootstrap/near_input.gd")
const MENU := "res://scenes/menu.tscn"
const MAIN := "res://scenes/main.tscn"
const TEST_ROOM := "res://tests/room.tscn"
const TURN_DEGREES_PER_SECOND := 40.0
const DEFAULT_WORLD_SIZE := 0.88

var target_scene := MENU
var xr: OpenXRInterface
var rig: XROrigin3D
var base_camera: Camera3D
var viewport: Viewport
var menu_panel: MenuPanel
var world_pointer: WorldPointer
var dealer_impact: DealerImpact
var player_impact: PlayerImpact
var haptics: Haptics
var cuffs: Cuffs
var table_text: TableText
var menu_bullets: MenuBullets
var grade: RetailGrade
var finale: Finale
var pause_menu: PauseMenu
var ending_calibrated := false
var wrists_were_at_rail := false
var saved_scale := 1.0
var calibration: Transform3D
var view_station: ViewStation
var stick_yaw := 0.0
var turn_shift := Vector3.ZERO
var focused := false
var stopped := false
var needs_anchor := true
var inspected_scene: Node


func _ready() -> void:
	set_process(false)
	if not OS.get_cmdline_user_args().has("--buckshot-vr"):
		print("[TableVR] loaded; opt-in absent")
		return
	var engine := Engine.get_version_info()
	if engine.major != 4 or engine.minor != 1 or engine.patch != 1:
		print("[TableVR] unsupported engine")
		return
	if ProjectSettings.get_setting("buckshot_vr/fixture", false):
		target_scene = TEST_ROOM
	else:
		var globals := get_node_or_null("/root/GlobalVariables")
		if globals == null or globals.get("version_to_check") != "v2.2.0.6":
			print("[TableVR] unsupported game")
			return
	print("[TableVR] host accepted")
	xr = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr == null or not (xr.is_initialized() or xr.initialize()):
		print("[TableVR] OpenXR unavailable; desktop camera retained")
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	xr.session_focussed.connect(_set_focus.bind(true))
	xr.session_visible.connect(_set_focus.bind(false))
	xr.session_stopping.connect(_stop_session)
	xr.session_begun.connect(_begin_session)
	xr.pose_recentered.connect(_request_anchor)
	set_process(true)
	print("[TableVR] OpenXR initialized; waiting for supported scene")


func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	if stopped or scene == null:
		return
	if scene != inspected_scene:
		_detach()
		inspected_scene = scene
		if scene.scene_file_path == target_scene or (target_scene == MENU and scene.scene_file_path == MAIN):
			var camera := scene.get_node_or_null("Camera") as Camera3D
			if camera != null and camera.is_current() and not camera.get_viewport().use_xr:
				_attach(scene, camera)
			else:
				print("[TableVR] expected desktop camera unavailable or viewport already owned")
	if is_instance_valid(rig):
		var station_frame := base_camera.global_transform
		var head: XRCamera3D = rig.get_node("Head")
		var ready := focused and not needs_anchor
		if is_instance_valid(pause_menu):
			pause_menu.update(ready)
		var paused := is_instance_valid(pause_menu) and pause_menu.opened
		var playing := ready and not paused
		if is_instance_valid(finale):
			finale.open_if_ready(playing)
		var ending := is_instance_valid(finale) and finale.active
		if ending:
			if finale.in_car():
				var car_units := view_station.units * Finale.CAR_UNITS_RATIO
				if not is_equal_approx(car_units, XRServer.world_scale):
					var ratio := car_units / XRServer.world_scale
					XRServer.world_scale = car_units
					calibration.origin *= ratio
					rig.get_node("LeftGlove").rescale_for_scene(ratio)
					rig.get_node("RightGlove").rescale_for_scene(ratio)
			station_frame = finale.camera_frame(delta if playing else 0.0)
		elif view_station != null:
			var can_interact := playing
			var was_arriving := view_station.arriving
			var can_drive := can_interact and not was_arriving
			var move: Vector2 = rig.get_node("Left").primary_stick(can_drive and not view_station.table_locked, ViewStation.DEADZONE)
			var turn: Vector2 = rig.get_node("Right").primary_stick(can_drive, ViewStation.DEADZONE)
			_turn(turn.x, delta, head)
			station_frame = view_station.update(move, delta, head.global_transform.basis.z, can_interact)
			if not was_arriving and view_station.arriving and can_interact:
				view_station.start_from_eye(head.global_position, _yaw(head.global_transform.basis))
				_calibrate(head)
				station_frame = view_station.station
		if focused and needs_anchor:
			var tracker := XRServer.get_tracker(&"head")
			if tracker != null and tracker.has_pose(&"default"):
				_calibrate(head)
				_align(station_frame, calibration)
				needs_anchor = false
				print("[TableVR] head calibrated")
		elif view_station != null and not needs_anchor and not ending:
			_align(station_frame, calibration)
		if ending and focused and not needs_anchor:
			if not ending_calibrated:
				_calibrate(head)
				ending_calibrated = true
			var frame := station_frame.basis * Basis(Vector3.UP, -_yaw(calibration.basis))
			rig.global_transform = Transform3D(frame, station_frame.origin - frame * calibration.origin)
		if is_instance_valid(finale):
			finale.present(playing, rig.get_node("RightGlove"))
		haptics.set_active(playing)
		var bound := cuffs.update(playing and not ending) if is_instance_valid(cuffs) else false
		var wrists_at_rail := bound and is_instance_valid(cuffs.second) and cuffs.second.visible
		if wrists_at_rail and not wrists_were_at_rail:
			haptics.cue(&"cuffs")
		wrists_were_at_rail = wrists_at_rail
		rig.get_node("Left").sample(playing and not bound)
		rig.get_node("Right").sample(playing and not bound)
		rig.get_node("LeftGlove").sample(playing or (paused and ready))
		rig.get_node("RightGlove").sample(playing or (paused and ready))
		if is_instance_valid(menu_panel):
			menu_panel.update_pointer(playing)
		if is_instance_valid(world_pointer):
			world_pointer.set_active(playing and not ending and not bound and view_station.sequence < 0)
		if is_instance_valid(table_text):
			table_text.set_active(playing and not ending and view_station.table_locked)
		if is_instance_valid(player_impact):
			player_impact.in_ending = ending
			player_impact.set_active(playing)


func _attach(scene: Node, camera: Camera3D) -> void:
	var in_game := scene.scene_file_path == MAIN
	var interaction := scene.get_node_or_null("standalone managers/interaction manager")
	if in_game and (interaction == null or interaction.get("mouseRay") != camera or not interaction.has_method("MainInteractionEvent")):
		print("[TableVR] unsupported main interaction layout")
		return
	if in_game:
		var world_size = ProjectSettings.get_setting("buckshot_vr/world_size", DEFAULT_WORLD_SIZE)
		var units := gameplay_units_per_metre(world_size)
		view_station = ViewStation.new()
		if not view_station.bind(scene, camera, units):
			view_station = null
			print("[TableVR] unsupported camera station layout")
			return
	base_camera = camera
	viewport = camera.get_viewport()
	saved_scale = XRServer.world_scale
	if in_game:
		XRServer.world_scale = view_station.units
		print("[TableVR] gameplay world size ", snappedf(WorldPointer.UNITS_PER_METRE / view_station.units, .001))
	rig = RIG.instantiate()
	scene.add_child(rig)
	haptics = Haptics.new()
	rig.add_child(haptics)
	haptics.mount(rig)
	_align(view_station.station if in_game else camera.global_transform, Transform3D.IDENTITY)
	rig.get_node("Head").make_current()
	viewport.use_xr = true
	var ui := camera.get_node_or_null("dialogue UI")
	if in_game or scene.scene_file_path == MENU:
		grade = RetailGrade.new()
		if grade.mount(camera):
			print("[TableVR] retail posterization enabled")
	if in_game:
		finale = Finale.new()
		rig.add_child(finale)
		if not finale.mount(camera, interaction):
			finale.queue_free()
			finale = null
		var exit_node := camera.get_node_or_null("dialogue UI/hold to exit label/hold to exit")
		if exit_node != null and exit_node.has_method("ExitGame"):
			pause_menu = PauseMenu.new()
			rig.add_child(pause_menu)
			pause_menu.mount(rig, exit_node)
		cuffs = Cuffs.new()
		rig.add_child(cuffs)
		if not cuffs.mount(scene, rig):
			cuffs.queue_free()
			cuffs = null
			print("[TableVR] cuff layout unavailable")
		table_text = TableText.new()
		rig.add_child(table_text)
		if not table_text.mount(scene, view_station.desk, view_station.units):
			table_text.queue_free()
			table_text = null
			print("[TableVR] text layout unavailable")
		world_pointer = WorldPointer.new()
		rig.add_child(world_pointer)
		world_pointer.mount(camera, interaction, rig.get_node("Right"))
		world_pointer.target_entered.connect(haptics.cue.bind(&"hover"))
		world_pointer.selected.connect(haptics.world_press)
		world_pointer.near_selected.connect(haptics.near_press)
		var near_input := NearInput.new()
		world_pointer.add_child(near_input)
		near_input.mount(world_pointer, rig, view_station)
		world_pointer.near_input = near_input
		view_station.kick_contact.connect(haptics.cue.bind(&"kick"))
		dealer_impact = DealerImpact.new()
		rig.add_child(dealer_impact)
		if not dealer_impact.mount(scene):
			dealer_impact.queue_free()
			dealer_impact = null
			print("[TableVR] dealer impact layout unavailable")
		player_impact = PlayerImpact.new()
		rig.get_node("Head").add_child(player_impact)
		if not player_impact.mount(scene):
			player_impact.queue_free()
			player_impact = null
			print("[TableVR] player impact layout unavailable")
		else:
			player_impact.player_hit.connect(haptics.cue.bind(&"hit"))
			player_impact.revived.connect(haptics.cue.bind(&"revival"))
			player_impact.heartbeat.connect(haptics.heartbeat)
	elif ui != null and ui.has_node("menu ui"):
		var menu := scene.get_node_or_null("standalone managers/menu manager")
		if menu != null and menu.get("viewing_intro") == true and menu.has_method("SkipIntro"):
			menu.SkipIntro()
		menu_panel = MenuPanel.new()
		rig.add_child(menu_panel)
		menu_panel.mount(ui.get_node("menu ui"), camera, rig.get_node("Right"))
		menu_panel.feedback.connect(haptics.cue)
		if scene.scene_file_path == MENU:
			menu_bullets = MenuBullets.new()
			rig.add_child(menu_bullets)
			if not menu_bullets.mount(scene):
				menu_bullets.queue_free()
				menu_bullets = null
				print("[TableVR] menu casing layout unavailable")
	needs_anchor = true
	scene.tree_exiting.connect(_detach)
	print("[TableVR] rig attached ", scene.scene_file_path)


func gameplay_units_per_metre(world_size: Variant) -> float:
	var ratio := DEFAULT_WORLD_SIZE
	if (world_size is float or world_size is int) and is_finite(float(world_size)):
		ratio = clampf(float(world_size), 0.80, 1.20)
	return WorldPointer.UNITS_PER_METRE / ratio


func _align(station_frame: Transform3D, head_local: Transform3D) -> void:
	var yaw := _yaw(station_frame.basis) - _yaw(head_local.basis) + stick_yaw
	var level := Basis(Vector3.UP, yaw)
	rig.global_transform = Transform3D(level, station_frame.origin + turn_shift - level * head_local.origin)


func _yaw(frame: Basis) -> float:
	if Vector2(frame.z.x, frame.z.z).length_squared() < 0.0001:
		return atan2(-frame.x.z, frame.x.x)
	return atan2(frame.z.x, frame.z.z)


func _calibrate(head: XRCamera3D) -> void:
	calibration = head.transform
	stick_yaw = 0.0
	turn_shift = Vector3.ZERO


func _turn(axis: float, delta: float, head: XRCamera3D) -> void:
	if absf(axis) <= ViewStation.DEADZONE:
		return
	var strength := inverse_lerp(ViewStation.DEADZONE, 1.0, minf(1.0, absf(axis)))
	var angle := -signf(axis) * deg_to_rad(TURN_DEGREES_PER_SECOND) * strength * minf(delta, .05)
	# Rotate about the current head even if the player has leaned away from calibration.
	var lean := rig.global_transform.basis * (head.position - calibration.origin)
	turn_shift += lean - lean.rotated(Vector3.UP, angle)
	stick_yaw = wrapf(stick_yaw + angle, -PI, PI)


func _set_focus(value: bool) -> void:
	if focused != value:
		print("[TableVR] session focused=", value)
	focused = value
	if not value and is_instance_valid(rig):
		haptics.set_active(false)
		if is_instance_valid(pause_menu):
			pause_menu.update(false)
		if is_instance_valid(finale):
			finale.continue_armed = false
		if is_instance_valid(cuffs):
			cuffs.update(false)
		if is_instance_valid(table_text):
			table_text.set_active(false)
		if is_instance_valid(player_impact):
			player_impact.set_active(false)
		rig.get_node("Left").sample(false)
		rig.get_node("Right").sample(false)
		rig.get_node("LeftGlove").sample(false)
		rig.get_node("RightGlove").sample(false)
		if is_instance_valid(world_pointer):
			world_pointer.set_active(false)


func _request_anchor() -> void:
	needs_anchor = true


func _stop_session() -> void:
	_set_focus(false)
	stopped = true
	_detach()
	inspected_scene = null


func _begin_session() -> void:
	stopped = false
	_request_anchor()


func _detach() -> void:
	if not is_instance_valid(viewport):
		return
	if is_instance_valid(pause_menu):
		pause_menu.close_pause()
	pause_menu = null
	if is_instance_valid(finale): finale.unmount()
	finale = null
	ending_calibrated = false
	if is_instance_valid(haptics):
		haptics.set_active(false)
		haptics = null
	if is_instance_valid(cuffs):
		cuffs.unmount()
		cuffs = null
	wrists_were_at_rail = false
	if is_instance_valid(table_text):
		table_text.unmount()
		table_text = null
	if is_instance_valid(menu_bullets):
		menu_bullets.unmount()
		menu_bullets = null
	if is_instance_valid(menu_panel):
		menu_panel.unmount()
		menu_panel = null
	if is_instance_valid(world_pointer):
		world_pointer.unmount()
		# The scene camera may already be outside the tree when scene.tree_exiting fires.
		viewport.canvas_cull_mask = world_pointer.old_canvas_mask
		world_pointer = null
	if is_instance_valid(player_impact):
		player_impact.unmount()
		player_impact = null
	if grade != null:
		grade.unmount()
		grade = null
	if is_instance_valid(dealer_impact):
		dealer_impact.unmount()
		dealer_impact = null
	if view_station != null:
		view_station.unbind()
	XRServer.world_scale = saved_scale
	viewport.use_xr = false
	if is_instance_valid(base_camera) and base_camera.is_inside_tree():
		base_camera.make_current()
	if is_instance_valid(rig):
		var scene := rig.get_parent()
		if is_instance_valid(scene) and scene.tree_exiting.is_connected(_detach):
			scene.tree_exiting.disconnect(_detach)
		rig.get_node("Left").sample(false)
		rig.get_node("Right").sample(false)
		rig.queue_free()
	rig = null
	view_station = null
	stick_yaw = 0.0
	turn_shift = Vector3.ZERO
	base_camera = null
	viewport = null
	print("[TableVR] rig detached")


func _exit_tree() -> void:
	_detach()
