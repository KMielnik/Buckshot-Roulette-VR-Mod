extends Node3D

# In the retail assembly the small chain links a wrist loop to a loop on the
# rail. This point is the free wrist opening in the mesh's local coordinates.
const WRIST_LOOP := Vector3(-0.86, -0.18, 0.88)
const BREAK_CLIP := &"player break handcuffs"
const WRIST_DISTANCE_METRES := 0.18

var rounds: Node
var source: MeshInstance3D
var source_pivot: MeshInstance3D
var rail: MeshInstance3D
var animator: AnimationPlayer
var left: XRController3D
var right: XRController3D
var left_input: XRController3D
var right_input: XRController3D
var second: MeshInstance3D
var second_pivot: MeshInstance3D
var opens_at := 0.0
var opened := false


func mount(scene: Node, rig: XROrigin3D) -> bool:
	var manager := scene.get_node_or_null("standalone managers/handcuff manager")
	if manager == null:
		return false
	rounds = manager.get("roundManager")
	source = manager.get("handcuffs_player") as MeshInstance3D
	animator = manager.get("animator_handcuffsPlayer") as AnimationPlayer
	if rounds == null or typeof(rounds.get("playerCuffed")) != TYPE_BOOL or source == null or animator == null:
		return false
	source_pivot = source.get_node_or_null("handcuffs player bar pivot") as MeshInstance3D
	rail = source.get_parent() as MeshInstance3D
	if source.mesh == null or source_pivot == null or source_pivot.mesh == null or rail == null or rail.mesh == null:
		return false
	if not animator.has_animation(BREAK_CLIP):
		return false
	var clip := animator.get_animation(BREAK_CLIP)
	var track := clip.find_track("handcuffs player bar/handcuffs player bar pivot:rotation", Animation.TYPE_VALUE)
	if track < 0 or clip.track_get_key_count(track) < 2:
		return false
	opens_at = clip.track_get_key_time(track, clip.track_get_key_count(track) - 1)
	left = rig.get_node_or_null("LeftGlove") as XRController3D
	right = rig.get_node_or_null("RightGlove") as XRController3D
	left_input = rig.get_node_or_null("Left") as XRController3D
	right_input = rig.get_node_or_null("Right") as XRController3D
	if left == null or right == null or left_input == null or right_input == null:
		return false
	second = _visual_copy(source)
	second.name = "LeftCuff"
	second.visible = false
	add_child(second)
	second_pivot = _visual_copy(source_pivot)
	second.add_child(second_pivot)
	left_input.cuffs = self
	right_input.cuffs = self
	return true


func _visual_copy(original: MeshInstance3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = original.mesh
	instance.material_override = original.material_override
	for surface in original.get_surface_override_material_count():
		instance.set_surface_override_material(surface, original.get_surface_override_material(surface))
	return instance


func is_bound() -> bool:
	if not is_instance_valid(rounds):
		return false
	# On a round reset the rules release the player at the start of the
	# break animation. Hold the visual wrists until the bar has opened.
	return rounds.get("playerCuffed") == true or (is_instance_valid(animator)
			and animator.current_animation == BREAK_CLIP and animator.current_animation_position < opens_at
			and is_instance_valid(source) and source.is_visible_in_tree())


func update(active: bool) -> bool:
	var bound := is_bound()
	if not is_instance_valid(source) or not is_instance_valid(second):
		return false
	if not bound:
		opened = false
	elif animator.current_animation == BREAK_CLIP and animator.current_animation_position >= opens_at:
		opened = true
	second.visible = active and bound and source.is_visible_in_tree() and not opened
	if second.visible:
		# Place the second rail loop toward the far end of the *same* bar.
		var rail_axis := rail.global_transform.basis.z
		var rail_span := rail.get_aabb().size.z * rail_axis.length()
		var spacing := minf(WRIST_DISTANCE_METRES * XRServer.world_scale, rail_span * 0.48)
		var offset := rail_axis.normalized() * spacing
		second.global_transform = source.global_transform.translated(offset)
		second_pivot.transform = source_pivot.transform
		var fingers := -source.global_transform.basis.y.normalized()
		right.restrain_at(source.to_global(WRIST_LOOP), fingers)
		left.restrain_at(second.to_global(WRIST_LOOP), fingers)
	else:
		left.release_restraint()
		right.release_restraint()
	return bound


func unmount() -> void:
	for glove in [left, right]:
		if is_instance_valid(glove):
			glove.release_restraint()
	for input in [left_input, right_input]:
		if is_instance_valid(input) and input.cuffs == self:
			input.cuffs = null
	rounds = null
	if is_instance_valid(second):
		second.visible = false
		second.queue_free()
		second = null
