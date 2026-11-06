extends Skeleton3D

# These resource and bone names are from the installed 2.2.0.6 player hand rig.
# Only read visual resources from its SceneState. Never instantiate its game scripts.
const PLAYER_HANDS := "res://multiplayer/instances/main hand instances/main_hand_instance_scene.tscn"
const HAND_LENGTH_METRES := 0.19
const INDEX := ["Bone.008", "Bone.009", "Bone.010"]
const GRIP := ["Bone.011", "Bone.012", "Bone.013", "Bone.014", "Bone.015",
	"Bone.016", "Bone.017", "Bone.018", "Bone.019"]
const THUMB := ["Bone.002", "Bone.003"]

var curls: Array[Dictionary] = []


func configure(right_hand: bool, world_scale: float) -> bool:
	if not ResourceLoader.exists(PLAYER_HANDS, "PackedScene"):
		return false
	var packed := load(PLAYER_HANDS) as PackedScene
	if packed == null:
		return false
	var side := "R" if right_hand else "L"
	var bone_path := "./main hand instance_%s/hand main instance_%s/hand main armature_%s/Skeleton3D" % [side, side, side]
	var skin_path := bone_path + "/hand main instance_%s_default skin" % side
	var state := packed.get_state()
	var bones := _properties(state, bone_path)
	var visual := _properties(state, skin_path)
	var mesh := visual.get("mesh") as Mesh
	var skin := visual.get("skin") as Skin
	if mesh == null or skin == null or skin.get_bind_count() != 20:
		return false
	var length_units := mesh.get_aabb().size.x
	if length_units <= 0.0 or not _build_bones(bones, skin):
		return false

	# In mesh bind space fingers extend along -X. Centre the grip between
	# the wrist and the outer two knuckles, with thumbs toward controller -Z.
	var knuckle_center := (get_bone_global_rest(find_bone("Bone.008")).origin
		+ get_bone_global_rest(find_bone("Bone.017")).origin) * 0.5
	var palm_center := (get_bone_global_rest(find_bone("Bone")).origin + knuckle_center) * 0.5
	var handed := 1.0 if right_hand else -1.0
	basis = Basis(Vector3.UP, Vector3.RIGHT * handed, Vector3.FORWARD * handed)
	basis = basis.scaled(Vector3.ONE * HAND_LENGTH_METRES * world_scale / length_units)
	position = -(basis * palm_center)

	var surface := MeshInstance3D.new()
	surface.name = "RetailSkin"
	surface.mesh = mesh
	surface.skin = skin
	surface.skeleton = NodePath("..")
	add_child(surface)
	set_curl(0.0, 0.0)
	return true


func open_index_segment() -> PackedVector3Array:
	# In the retail right mesh, the fingertip extends past its last bind joint
	# by 90% of the preceding phalanx, dipping 25% of that length toward the palm.
	var knuckle_id := find_bone(INDEX[0])
	var distal_id := find_bone(INDEX[2])
	var middle := get_bone_global_rest(find_bone(INDEX[1])).origin
	var distal_frame := get_bone_global_rest(distal_id)
	var distal := distal_frame.origin
	var segment := distal - middle
	var tip := distal + segment * 0.90 + Vector3.DOWN * segment.length() * 0.25
	# The original relaxed 0.3 hand already bends its knuckles slightly.
	# Apply that bone pose to the mesh-space tip before measuring the ray.
	force_update_all_bone_transforms()
	var posed_tip := get_bone_global_pose(distal_id) * (distal_frame.affine_inverse() * tip)
	return PackedVector3Array([transform * get_bone_global_pose(knuckle_id).origin, transform * posed_tip])


func _properties(state: SceneState, path: String) -> Dictionary:
	for node in state.get_node_count():
		if str(state.get_node_path(node)) == path:
			var values := {}
			for entry in state.get_node_property_count(node):
				values[state.get_node_property_name(node, entry)] = state.get_node_property_value(node, entry)
			return values
	return {}


func _build_bones(properties: Dictionary, skin: Skin) -> bool:
	# The two exported skeletons have different authored scene poses. The
	# inverse binds describe each skin's open hand in a common mesh coordinate system.
	var bind_frames := {}
	for bind in skin.get_bind_count():
		var frame := skin.get_bind_pose(bind)
		if is_zero_approx(frame.basis.determinant()):
			return false
		bind_frames[skin.get_bind_name(bind)] = frame.affine_inverse()
	for required in ["Bone"] + INDEX + GRIP + THUMB:
		if not bind_frames.has(required):
			return false

	for index in skin.get_bind_count():
		var prefix := "bones/%d/" % index
		var joint := StringName(properties.get(prefix + "name", ""))
		var parent := int(properties.get(prefix + "parent", -2))
		if not bind_frames.has(joint) or parent < -1 or parent >= index or find_bone(joint) != -1:
			return false
		var frame: Transform3D = bind_frames[joint]
		var relative := frame
		if parent >= 0:
			var parent_frame: Transform3D = bind_frames[get_bone_name(parent)]
			relative = parent_frame.affine_inverse() * frame
		add_bone(joint)
		set_bone_parent(index, parent)
		set_bone_rest(index, relative)
		reset_bone_pose(index)
		if joint in INDEX or joint in GRIP or joint in THUMB:
			var axes := frame.basis.orthonormalized()
			var bend_axis := axes.y.cross(Vector3.DOWN).normalized()
			if bend_axis.is_zero_approx():
				return false
			curls.append({"index": index, "rest": get_bone_pose_rotation(index),
				"axis": axes.inverse() * bend_axis, "trigger": joint in INDEX, "thumb": joint in THUMB})
	return true


func set_curl(trigger: float, squeeze: float) -> void:
	for joint in curls:
		var degrees := lerpf(10.0, 62.0, trigger if joint.trigger else squeeze)
		if joint.thumb:
			degrees = lerpf(12.0, 32.0, squeeze)
		var rest: Quaternion = joint.rest
		set_bone_pose_rotation(joint.index, rest * Quaternion(joint.axis, deg_to_rad(degrees)))
