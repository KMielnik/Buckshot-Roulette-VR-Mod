extends MeshInstance3D

signal feedback(kind: StringName)

const PIXELS := Vector2i(960, 540)
const WIDTH := 1.56
const HEIGHT := WIDTH * 540.0 / 960.0
const PANEL_LAYER := 1 << 18
const OUTSIDE := Vector2(-1000, -1000)

var root_view: Viewport
var original_mask: int
var original_layers := {}
var hand: XRController3D
var dot := MeshInstance3D.new()
var last_pixel := OUTSIDE
var pressed := false
var sending_pointer_input := false


func mount(ui: Node, camera: Camera3D, right: XRController3D) -> void:
	root_view = camera.get_viewport()
	original_mask = root_view.canvas_cull_mask
	hand = right
	var surface := SubViewport.new()
	surface.size = PIXELS
	surface.disable_3d = true
	surface.transparent_bg = true
	surface.gui_disable_input = true
	surface.world_2d = root_view.world_2d
	surface.canvas_cull_mask = PANEL_LAYER
	surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(surface)
	# Share the drawn canvas. Original nodes, GUI ownership and animation paths stay intact.
	var items := ui.find_children("*", "CanvasItem", true, false)
	items.append(ui)
	for item in items:
		original_layers[item] = item.visibility_layer
		item.visibility_layer |= PANEL_LAYER
	root_view.canvas_cull_mask = 0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = 1
	material.albedo_texture = surface.get_texture()
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH, HEIGHT)
	quad.material = material
	mesh = quad
	var dot_material := StandardMaterial3D.new()
	dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_material.albedo_color = Color(0.1, 1.0, 1.0)
	dot_material.no_depth_test = true
	dot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot_material.render_priority = 2
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.006
	dot_mesh.height = 0.012
	dot_mesh.material = dot_material
	dot.mesh = dot_mesh
	dot.visible = false
	add_child(dot)
	top_level = true
	var forward := camera.global_transform.basis.z
	global_transform = Transform3D(Basis(Vector3.UP, atan2(forward.x, forward.z)), camera.global_position)
	translate_object_local(Vector3(0, 0.03, -1.25))
	hand.select_changed.connect(_on_select)
	for button in ui.find_children("*", "BaseButton", true, false):
		for logic in button.get_children():
			if logic.has_signal("is_pressed") and logic.has_method("OnHover"):
				button.mouse_entered.connect(_menu_hover.bind(logic))
				logic.is_pressed.connect(_menu_accept)
	print("[TableVR] menu panel mounted ", original_layers.size(), " canvas items")


func update_pointer(active: bool) -> void:
	var pixel := OUTSIDE
	if active and hand.can_point():
		var pose: Transform3D = hand.pointer_pose()
		var start := to_local(pose.origin)
		var direction := global_transform.basis.inverse() * -pose.basis.z
		if direction.z < -0.0001 and start.z > 0.0:
			var point := start + direction * (-start.z / direction.z)
			var uv := Vector2(0.5 + point.x / WIDTH, 0.5 - point.y / HEIGHT)
			if Rect2(Vector2.ZERO, Vector2.ONE).has_point(uv):
				pixel = uv * Vector2(PIXELS)
				dot.position = Vector3(point.x, point.y, 0.006)
	dot.visible = pixel != OUTSIDE
	_move(pixel)


func _move(pixel: Vector2) -> void:
	if pixel == last_pixel:
		return
	var event := InputEventMouseMotion.new()
	event.position = pixel
	event.global_position = pixel
	event.relative = pixel - last_pixel if last_pixel != OUTSIDE else Vector2.ZERO
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	last_pixel = pixel
	_send_gui(event)


func _on_select(phase: String) -> void:
	if not is_instance_valid(root_view) or not root_view.is_inside_tree():
		return
	if phase == "cancel":
		_move(OUTSIDE)
	else:
		update_pointer(hand.can_point())
	var down := phase == "press"
	if (down and last_pixel == OUTSIDE) or down == pressed:
		return
	pressed = down
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.position = last_pixel
	event.global_position = last_pixel
	_send_gui(event)


func _send_gui(event: InputEvent) -> void:
	sending_pointer_input = true
	root_view.push_input(event, true)
	sending_pointer_input = false


func _menu_hover(logic: Node) -> void:
	if sending_pointer_input and logic.isActive and logic.mainActive:
		feedback.emit(&"hover")


func _menu_accept() -> void:
	if sending_pointer_input:
		feedback.emit(&"key")


func unmount() -> void:
	if is_instance_valid(hand) and hand.select_changed.is_connected(_on_select):
		hand.select_changed.disconnect(_on_select)
	if is_instance_valid(root_view):
		if pressed:
			_on_select("cancel")
		root_view.canvas_cull_mask = original_mask
	for item in original_layers:
		if is_instance_valid(item):
			item.visibility_layer = original_layers[item]
	original_layers.clear()
