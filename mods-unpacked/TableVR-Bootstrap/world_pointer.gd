extends Node3D

signal target_entered
signal selected(alias: String, item: String, grid: bool)
signal near_selected(side: int, alias: String, item: String, grid: bool)

const UNITS_PER_METRE := 10.0
const REACH := 20000.0

var camera: Camera3D
var manager: Node
var hand: XRController3D
var marker := MeshInstance3D.new()
var active := false
var pending := false
var press_pose: Transform3D
var press_source_revision: int
var was_processing: bool
var old_canvas_mask: int
var hover_id := 0
var near_input: Node


func mount(desktop: Camera3D, interaction: Node, right: XRController3D) -> void:
	camera = desktop
	manager = interaction
	hand = right
	was_processing = camera.is_processing()
	camera.set_process(false) # Only MouseRaycast's poll. CameraManager and animation players run separately.
	old_canvas_mask = camera.get_viewport().canvas_cull_mask
	camera.get_viewport().canvas_cull_mask = 0
	hand.select_changed.connect(_on_select)
	var shape := SphereMesh.new()
	shape.radius = 0.09
	shape.height = 0.18
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.15, 0.95, 1)
	shape.material = material
	marker.mesh = shape
	marker.visible = false
	add_child(marker)


func set_active(value: bool) -> void:
	active = value
	if not active:
		hover_id = 0
		pending = false
		marker.visible = false
		if is_instance_valid(near_input):
			near_input.cancel()


func _on_select(phase: String) -> void:
	if phase == "cancel":
		pending = false
	elif phase == "press" and active and hand.can_point():
		pending = true
		press_pose = hand.pointer_pose()
		press_source_revision = hand.source_revision


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(camera) or not is_instance_valid(manager):
		return
	if is_instance_valid(near_input) and near_input.tick(active and manager.cursor.cursor_visible):
		pending = false
		hover_id = 0
		marker.visible = false
		return
	if not active or not hand.can_point() or not manager.cursor.cursor_visible:
		hover_id = 0
		camera.set("result", {})
		pending = false
		marker.visible = false
		return
	if pending and press_source_revision != hand.source_revision:
		pending = false
	var pose: Transform3D = press_pose if pending else hand.pointer_pose()
	var query := PhysicsRayQueryParameters3D.create(pose.origin, pose.origin - pose.basis.z.normalized() * REACH)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	camera.set("result", hit)
	manager.CheckPickupLerp()
	manager.CheckInteractionBranch()
	var branch = manager.activeInteractionBranch
	marker.visible = branch != null and branch.interactionAllowed and not branch.interactionInvalid
	if marker.visible and branch.interactionAlias in ["bathroom door", "backroom door"]:
		marker.visible = false # Foot travel owns these two proximity triggers.
	var target_id: int = branch.get_instance_id() if marker.visible else 0
	if target_id != hover_id:
		hover_id = target_id
		if hover_id != 0:
			target_entered.emit()
	if marker.visible:
		marker.global_position = hit.position + hit.normal * 0.10
	if pending:
		pending = false
		if marker.visible:
			_commit(branch)


# Optional near-hand input feeds a fresh physical hit through the same native
# branch lookup. Require the expected branch to survive that lookup.
func commit_near(hit: Dictionary, expected: Node, side: int = 1) -> bool:
	if not active or not manager.cursor.cursor_visible or not is_instance_valid(expected) or hit.is_empty():
		return false
	camera.set("result", hit)
	manager.CheckPickupLerp()
	manager.CheckInteractionBranch()
	return manager.activeInteractionBranch == expected and _commit(expected, side)


func _commit(branch: Node, side: int = -1) -> bool:
	if not branch.interactionAllowed or branch.interactionInvalid:
		return false
	var alias: String = branch.interactionAlias
	if alias in ["text dealer", "text you"] and manager.fs_dec:
		return false
	var item: String = branch.itemName if alias == "item" else ""
	var grid: bool = branch.isGrid
	manager.MainInteractionEvent()
	if side < 0: selected.emit(alias, item, grid)
	else: near_selected.emit(side, alias, item, grid)
	return true


func unmount() -> void:
	set_physics_process(false)
	set_active(false)
	if is_instance_valid(hand) and hand.select_changed.is_connected(_on_select):
		hand.select_changed.disconnect(_on_select)
	if is_instance_valid(camera):
		camera.set("result", {})
		camera.set_process(was_processing)
		if camera.is_inside_tree():
			camera.get_viewport().canvas_cull_mask = old_canvas_mask
