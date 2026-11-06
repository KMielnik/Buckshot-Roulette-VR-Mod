extends MultiMeshInstance3D

const RECOIL := &"dealer fly away"
const COUNT := 60
const DURATION := 0.64

var recoil: AnimationPlayer
var plane: MeshInstance3D
var original_layers := 0
var normal_head: MeshInstance3D
var crushed_head: MeshInstance3D
var skeleton: Skeleton3D
var root_bone := -1
var rng := RandomNumberGenerator.new()
var starts := PackedVector3Array()
var speeds := PackedVector3Array()
var sizes := PackedFloat32Array()
var elapsed := 0.0
var head_width := 0.0


func mount(scene: Node) -> bool:
	if is_instance_valid(recoil):
		return true
	var gun := scene.get_node_or_null("standalone managers/shotgun shooting")
	var death := scene.get_node_or_null("standalone managers/death manager")
	var dealer := scene.get_node_or_null("standalone managers/dealer intelligence")
	if gun == null or death == null or dealer == null:
		return false
	var overlay := gun.get("mat_splatter") as MeshInstance3D
	var anim := death.get("animator_dealer") as AnimationPlayer
	var head := dealer.get("dealermesh_normal") as MeshInstance3D
	var crushed := dealer.get("dealermesh_crushed") as MeshInstance3D
	if overlay == null or overlay != scene.get_node_or_null("Camera/blood splatter plane") or not overlay.mesh is PlaneMesh:
		return false
	if anim == null or not anim.has_animation(RECOIL) or head == null or head.mesh == null:
		return false
	if crushed == null or crushed.mesh == null or not head.is_ancestor_of(crushed):
		return false
	if not anim.get_parent().is_ancestor_of(head) or head.mesh.get_aabb().size.x <= 0 or crushed.mesh.get_aabb().size.x <= 0:
		return false
	skeleton = head.get_node_or_null(head.skeleton) as Skeleton3D
	if skeleton == null or head.skin == null or head.skin.get_bind_count() < 1:
		return false
	root_bone = skeleton.find_bone(head.skin.get_bind_name(0))
	if root_bone < 0 or skeleton.get_bone_parent(root_bone) != -1:
		return false
	normal_head = head
	crushed_head = crushed
	recoil = anim
	plane = overlay
	original_layers = plane.layers
	# The game can still animate transparency/textures and play the splatter sound.
	plane.layers = 0
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.53, 0.045, 0.027)
	material.roughness = 0.34
	material.emission_enabled = true
	material.emission = Color(0.35, 0.024, 0.012)
	var droplet := SphereMesh.new()
	droplet.radial_segments = 6
	droplet.rings = 2
	droplet.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = droplet
	multimesh.instance_count = COUNT
	starts.resize(COUNT)
	speeds.resize(COUNT)
	sizes.resize(COUNT)
	rng.seed = 94913  # Independent of the game's shell and item RNG.
	hide()
	set_process(false)
	recoil.animation_started.connect(_on_recoil)
	return true


func _on_recoil(animation: StringName) -> void:
	if animation != RECOIL or not is_instance_valid(normal_head) or not is_instance_valid(crushed_head):
		return
	# Snapshot the visible head before the recoil animation pulls it away.
	# Its local +X faces the table on the audited retail meshes.
	var head := crushed_head if crushed_head.layers != 0 else normal_head
	var bounds := head.mesh.get_aabb()
	var face := bounds.get_center() + bounds.size * Vector3(0.43, 0.10, 0.0)
	var head_frame := head.global_transform
	if head == normal_head:
		# The rigged mesh's vertices include an inverse-bind offset from the armature.
		head_frame = head_frame * skeleton.get_bone_global_pose(root_bone) * head.skin.get_bind_pose(0)
	global_transform = Transform3D(Basis.IDENTITY, head_frame * face)
	var frame := head_frame.basis.orthonormalized()
	head_width = head_frame.basis.x.length() * bounds.size.x
	for i in COUNT:
		starts[i] = frame * Vector3(0, rng.randf_range(-0.08, 0.08), rng.randf_range(-0.12, 0.12)) * head_width
		speeds[i] = frame * Vector3(rng.randf_range(0.5, 1.8), rng.randf_range(-0.38, 1.40), rng.randf_range(-1.25, 1.25)) * head_width
		var size := rng.randf_range(0.023, 0.047)
		if i % 4 == 0:
			size *= 1.65
		sizes[i] = size * head_width
	elapsed = 0.0
	_draw_drops()
	show()
	set_process(true)
	print("[TableVR] dealer impact ", head.name, " at ", global_position)


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= DURATION:
		hide()
		set_process(false)
		return
	_draw_drops()


func _draw_drops() -> void:
	var gravity := Vector3.DOWN * (head_width * 5.0)
	var shrink := 1.0 - smoothstep(DURATION * 0.5, DURATION, elapsed)
	for i in COUNT:
		var velocity := speeds[i] + gravity * elapsed
		var position_in_burst := starts[i] + speeds[i] * elapsed + gravity * (0.5 * elapsed * elapsed)
		var rotation_to_velocity := Basis(Quaternion(Vector3.UP, velocity.normalized()))
		var axes := rotation_to_velocity * Basis.from_scale(Vector3(1, 1.8, 1) * sizes[i] * shrink)
		multimesh.set_instance_transform(i, Transform3D(axes, position_in_burst))


func unmount() -> void:
	if is_instance_valid(recoil) and recoil.animation_started.is_connected(_on_recoil):
		recoil.animation_started.disconnect(_on_recoil)
	if is_instance_valid(plane):
		plane.layers = original_layers
	recoil = null
	plane = null
	normal_head = null
	crushed_head = null
	hide()
	set_process(false)


func _exit_tree() -> void:
	unmount()
