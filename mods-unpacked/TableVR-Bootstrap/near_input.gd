extends Node3D

const GRIP_PRESS := 0.65
const GRIP_RELEASE := 0.30
const KEY_WITHDRAW_METRES := 0.024
const MAX_POKE_STEP_METRES := 0.20

var pointer: Node
var station: RefCounted
var hands: Array[XRController3D] = []
var grip_armed := [false, false]
var previous_tip := Vector3.ZERO
var have_tip := false
var key_contact := false
var contact_position := Vector3.ZERO


func mount(world_pointer: Node, rig: XROrigin3D, view_station: RefCounted) -> void:
	pointer = world_pointer
	station = view_station
	hands.assign([rig.get_node("LeftGlove"), rig.get_node("RightGlove")])


func cancel() -> void:
	grip_armed.fill(false)
	have_tip = false
	key_contact = false


func tick(enabled: bool) -> bool:
	if not enabled or not station.table_locked:
		cancel()
		return false
	var consumed := false
	for side in hands.size():
		var hand := hands[side]
		if not hand.get_has_tracking_data():
			grip_armed[side] = false
			if side == 1:
				have_tip = false
				key_contact = false
			continue
		var squeeze := hand.get_float(&"grip")
		if squeeze <= GRIP_RELEASE:
			grip_armed[side] = true
		elif squeeze >= GRIP_PRESS and grip_armed[side]:
			grip_armed[side] = false
			if not consumed and not pointer.hand.held:
				consumed = _latch(side)
		if side == 1:
			var tip: Vector3 = hand.global_transform * hand.index_ray.origin
			var can_poke: bool = not consumed and hand.get_float(&"trigger") < 0.35 and not pointer.hand.held
			consumed = _poke(tip, can_poke) or consumed
	return consumed


func _ray(start: Vector3, end: Vector3) -> Dictionary:
	if start.is_equal_approx(end):
		return {}
	var query := PhysicsRayQueryParameters3D.create(start, end)
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _branch(hit: Dictionary) -> Node:
	if hit.is_empty():
		return null
	for child in hit.collider.get_parent().get_children():
		if "interactionAlias" in child:
			return child
	return null


func _allowed(branch: Node) -> bool:
	return is_instance_valid(branch) and branch.interactionAllowed and not branch.interactionInvalid


func _latch(side: int) -> bool:
	var hand := hands[side]
	var units := XRServer.world_scale
	var palm := hand.global_position - hand.global_transform.basis.y.normalized() * 0.045 * units
	var hit := _ray(palm + Vector3.UP * 0.04 * units, palm - Vector3.UP * 0.085 * units)
	var branch := _branch(hit)
	if not _allowed(branch) and side == 1 and pointer.hand.can_point():
		var aim: Transform3D = pointer.hand.pointer_pose()
		hit = _ray(aim.origin, aim.origin - aim.basis.z * 2.0 * units)
		branch = _branch(hit)
	if not _allowed(branch) or branch.interactionAlias not in ["latch left", "latch right"]:
		return false
	return pointer.commit_near(hit, branch, side)


func _poke(tip: Vector3, can_press: bool) -> bool:
	var units := XRServer.world_scale
	if key_contact and tip.distance_to(contact_position) > KEY_WITHDRAW_METRES * units:
		key_contact = false
	var last_tip := previous_tip
	previous_tip = tip
	var had_tip := have_tip
	have_tip = true
	if not can_press or not had_tip or key_contact or tip.distance_to(last_tip) > MAX_POKE_STEP_METRES * units:
		return key_contact
	var hit := _ray(last_tip, tip)
	var key := _branch(hit)
	if not _allowed(key) or key.interactionAlias != "signature machine button" or hit.normal == Vector3.ZERO:
		return false
	if pointer.commit_near(hit, key):
		key_contact = true
		contact_position = hit.position
	return key_contact
