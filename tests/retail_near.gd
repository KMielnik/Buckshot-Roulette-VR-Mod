extends Node

var failures := 0
var mod: Node
var pointer: Node
var gestures: Node
var tracks: Array[XRPositionalTracker] = []
var units := 1.0


func _ready() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("NEAR_QA ", "PASS " if ok else "FAIL ", label)


func center(target: Node) -> Vector3:
	for body in target.get_parent().find_children("*", "StaticBody3D", false, false):
		var shapes := body.find_children("*", "CollisionShape3D", false, false)
		if not shapes.is_empty():
			return shapes[0].global_position
	return target.get_parent().global_position


func contact(target: Node) -> Vector3:
	var position := center(target)
	var hit: Dictionary = gestures._ray(position + Vector3.UP * units * 0.25, position - Vector3.UP * units * 0.08)
	return hit.position if gestures._branch(hit) == target else position


func fingertip(position: Vector3) -> void:
	var glove = gestures.hands[1]
	glove.global_position += position - (glove.global_transform * glove.index_ray.origin)
	gestures.tick(true)


func press_key(key: Node) -> void:
	var position := contact(key)
	fingertip(position + Vector3.UP * 0.065 * units)
	fingertip(position - Vector3.UP * 0.006 * units)


func grip_latch(side: int, target: Node) -> void:
	var hand: XRController3D = gestures.hands[side]
	var palm := hand.global_position - hand.global_transform.basis.y.normalized() * 0.045 * units
	hand.global_position += contact(target) + Vector3.UP * 0.018 * units - palm
	for squeeze in [0.0, 1.0, 1.0]:
		tracks[side].set_input(&"grip", squeeze)
		gestures.tick(true)


func _run() -> void:
	mod = get_node("/root/ModLoader/TableVR-Bootstrap")
	get_tree().change_scene_to_file(mod.MAIN)
	while get_tree().current_scene == null or get_tree().current_scene.scene_file_path != mod.MAIN:
		await get_tree().process_frame
	mod._process(0)
	pointer = mod.world_pointer
	pointer.set_physics_process(false)
	mod.view_station._lock_table()
	pointer.set_active(true)
	gestures = pointer.near_input
	units = XRServer.world_scale
	check(is_instance_valid(gestures), "key and latch adapter is part of the main mod")
	for tracker_name in [&"left_hand", &"right_hand"]:
		var tracker := XRPositionalTracker.new()
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.name = tracker_name
		XRServer.add_tracker(tracker)
		tracker.set_pose(&"grip", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		tracks.append(tracker)
	var signature = pointer.manager.sign
	signature.SetupWaiver()
	signature.PickUpWaiver()
	for frame in 300:
		await get_tree().process_frame
	await get_tree().physics_frame
	var keys := {}
	for key in signature.intbranches:
		keys[key.signatureButton_letterAlias if key.signatureButton_letterAlias != "" else key.signatureButton_specialAlias] = key
	tracks[1].set_input(&"grip", 1.0)
	press_key(keys["a"])
	fingertip(contact(keys["a"]) - Vector3.UP * 0.006 * units)
	check(signature.markerIndex == 1 and signature.letterArray[0].text == "a", "closed grip with extended index pokes once")
	pointer.pending = true
	pointer._physics_process(0)
	check(not pointer.pending and signature.markerIndex == 1, "contact claims simultaneous pointer input")
	pointer.set_active(false)
	fingertip(contact(keys["a"]))
	pointer.set_active(true)
	pointer._physics_process(0)
	check(signature.markerIndex == 1, "focus restoration cannot repeat a resting key")
	press_key(keys["b"])
	press_key(keys["backspace"])
	check(signature.markerIndex == 1 and signature.letterArray[1].text == "", "withdrawal permits another key and backspace")
	press_key(keys["enter"])
	check(signature.fullstring == "a" and not keys["enter"].interactionAllowed, "enter calls the native signature")
	var brief = pointer.manager.brief
	brief.MainRoutine()
	for frame in 800:
		await get_tree().process_frame
	await get_tree().physics_frame
	gestures.cancel()
	grip_latch(0, brief.intbranch_L)
	check(brief.latchRaisedL and not brief.latchRaisedR, "left grip opens only its latch")
	grip_latch(1, brief.intbranch_R)
	check(brief.latchRaisedL and brief.latchRaisedR, "right grip opens the second latch")
	for frame in 50:
		await get_tree().process_frame
	mod.finale.open_if_ready(true)
	check(mod.finale.active and brief.anim_lid.current_animation == "open", "both latches open the case without another input")
	for tracker in tracks:
		XRServer.remove_tracker(tracker)
	print("NEAR_QA failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
