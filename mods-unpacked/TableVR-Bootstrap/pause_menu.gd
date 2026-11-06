extends Node3D

const WIDTH := .85
const ROW := .112
var opened := false
var options := false
var previous_pause := false
var previous_speed := 1.0
var menu_armed := false
var trigger_armed := false
var down := false
var pressed_row := -1
var hovered := -1
var heading: Label3D
var rows: Array[Label3D] = []
var dot: MeshInstance3D
var rig: XROrigin3D
var exit_manager: Node
var had_focus := false

func mount(origin: XROrigin3D, native_exit: Node) -> void:
	rig = origin
	exit_manager = native_exit
	top_level = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	var mesh_instance := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH, .75)
	var backing := StandardMaterial3D.new()
	backing.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	backing.albedo_color = Color(.08, .055, .044, .98)
	backing.no_depth_test = true
	backing.render_priority = 10
	quad.material = backing
	mesh_instance.mesh = quad
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	heading = _label(.265, 54)
	for i in 4:
		rows.append(_label(.13 - i * ROW, 40))
	dot = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = .005
	ball.height = .010
	var mat := backing.duplicate() as StandardMaterial3D
	mat.render_priority = 13
	mat.albedo_color = Color(.2, 1, 1)
	ball.material = mat
	dot.mesh = ball
	add_child(dot)
	hide()

func _label(y: float, size: int) -> Label3D:
	var label := Label3D.new()
	label.font_size = size
	label.pixel_size = .00085
	label.position = Vector3(0,y,.004)
	label.outline_size = 0
	label.no_depth_test = true
	label.render_priority = 12
	add_child(label)
	return label

func _draw() -> void:
	var volume := roundi(clampf(db_to_linear(AudioServer.get_bus_volume_db(0)), 0, 1) * 100)
	heading.text = "Session volume   %d%%" % volume if options else "Paused"
	var labels := ["Volume down", "Volume up", "Back"] if options else ["Resume", "Options", "Main menu", "Quit to desktop"]
	for i in rows.size():
		rows[i].visible = i < labels.size()
		if rows[i].visible:
			rows[i].text = labels[i]
			rows[i].modulate = Color(.35,1,.95) if i == hovered else Color(1,.93,.81)

func _place() -> void:
	var head: XRCamera3D = rig.get_node("Head")
	var z := head.global_transform.basis.z
	var yaw := Basis(Vector3.UP, atan2(z.x,z.z))
	var units := XRServer.world_scale
	global_transform = Transform3D(yaw.scaled(Vector3.ONE * units), head.global_position + yaw * Vector3(0,-.045,-1.10) * units)

func show_pause() -> void:
	if opened: return
	previous_pause = get_tree().paused
	previous_speed = Engine.time_scale
	get_tree().paused = true
	# Some retail coroutines use process-always timers. Freeze their game
	# clock too; OpenXR tracking and controller polling use the runtime clock.
	Engine.time_scale = 0.0
	opened = true
	options = false
	_reset_selection()
	_place()
	_draw()
	show()
	print("[TableVR] pause opened")

func close_pause() -> void:
	if not opened: return
	opened = false
	hide()
	_reset_selection()
	Engine.time_scale = previous_speed
	get_tree().paused = previous_pause
	print("[TableVR] pause closed")

func _reset_selection() -> void:
	trigger_armed = false
	down = false
	hovered = -1
	pressed_row = -1
	dot.hide()

func update(focus: bool) -> void:
	var left: XRController3D = rig.get_node("LeftGlove")
	var device := XRServer.get_tracker(&"left_hand")
	var alternate := device != null and device.profile.contains("index_controller") and left.is_button_pressed(&"primary_click")
	var toggle := left.is_button_pressed(&"menu_button") or alternate
	if not focus or not left.get_has_tracking_data():
		menu_armed = false
	elif not toggle:
		menu_armed = true
	elif menu_armed:
		menu_armed = false
		if opened: close_pause()
		else: show_pause()
	if opened:
		visible = focus
		if focus and not had_focus: _place()
		var glove: XRController3D = rig.get_node("RightGlove")
		var aim: XRController3D = rig.get_node("Right")
		if focus and (glove.get_has_tracking_data() or aim.get_has_tracking_data()):
			var ray: Transform3D = glove.global_transform * glove.get("index_ray") if glove.get_has_tracking_data() else aim.global_transform
			_pointer(ray, glove.is_button_pressed(&"trigger_click"))
		else:
			_reset_selection()
	had_focus = focus

func _pointer(ray: Transform3D, trigger: bool) -> void:
	var start := to_local(ray.origin)
	var dir := global_transform.basis.inverse() * -ray.basis.z
	var hit := -1
	dot.hide()
	if dir.z < -.00001 and start.z > 0:
		var pos := start + dir * (-start.z / dir.z)
		if absf(pos.x) < WIDTH / 2 and absf(pos.y) < .375:
			dot.position = Vector3(pos.x,pos.y,.008)
			dot.show()
			for i in rows.size():
				if rows[i].visible and absf(pos.y - rows[i].position.y) < ROW * .48: hit = i
	if hit != hovered:
		hovered = hit
		_draw()
	if not trigger_armed:
		trigger_armed = not trigger
		return
	if trigger and not down:
		pressed_row = hit
	elif down and not trigger and hit >= 0 and pressed_row == hit:
		_activate(hit)
	down = trigger

func _activate(row: int) -> void:
	if options:
		if row == 2: options = false
		else:
			var amount := db_to_linear(AudioServer.get_bus_volume_db(0))
			amount = clampf(snappedf(amount + (.10 if row == 1 else -.10), .10), 0, 1)
			AudioServer.set_bus_volume_db(0, linear_to_db(amount))
		_draw()
		return
	match row:
		0: close_pause()
		1:
			options = true
			_draw()
		2:
			close_pause()
			exit_manager.ExitGame()
		3:
			close_pause()
			get_tree().quit()
