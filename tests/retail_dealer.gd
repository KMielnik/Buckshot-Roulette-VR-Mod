# Run only in the isolated retail QA stage, with the compositor disabled.
extends Node

var failures := 0
var bursts := 0
var anchored := false
var mod: Node
var effect: MultiMeshInstance3D
var normal_head: MeshInstance3D
var crushed_head: MeshInstance3D


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("DEALER_QA ", "PASS " if ok else "FAIL ", label)


func _run() -> void:
	mod = get_node("/root/ModLoader/TableVR-Bootstrap")
	await _shoot_case("blank", 2, false)
	await _shoot_case("live", 2, false)
	await _shoot_case("live", 1, true)
	print("DEALER_QA failures=", failures)
	get_tree().quit(0 if failures == 0 else 2)


func _shoot_case(shell: String, hp: int, dealer_fires: bool) -> void:
	var old_scene := get_tree().current_scene.get_instance_id()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	while not get_tree().current_scene or get_tree().current_scene.get_instance_id() == old_scene:
		await get_tree().process_frame
	var scene := get_tree().current_scene
	var gun := scene.get_node("standalone managers/shotgun shooting")
	var ai := scene.get_node("standalone managers/dealer intelligence")
	var plane: MeshInstance3D = gun.mat_splatter
	var old_mask := plane.layers
	var was_visible := plane.visible
	var old_material := plane.material_override
	bursts = 0
	anchored = false
	mod._process(0)
	effect = mod.get("dealer_impact") as MultiMeshInstance3D
	_check(is_instance_valid(effect), "retail scene adapter mounted")
	if not is_instance_valid(effect):
		return
	_check(plane.layers == 0 and plane.visible == was_visible, "only the render mask suppresses the original overlay")
	normal_head = ai.dealermesh_normal
	crushed_head = ai.dealermesh_crushed
	effect.visibility_changed.connect(_measure_burst)
	gun.roundManager.health_opponent = hp
	gun.roundManager.health_player = 2
	gun.shellSpawner.sequenceArray.assign([shell, "blank", "live"])
	ai.sequenceArray_knownShell.assign([false, false, false])
	if dealer_fires:
		ai.Shoot("self")
	else:
		gun.Shoot("dealer")
	var blank_seen := false
	for i in range(340):
		await get_tree().process_frame
		blank_seen = blank_seen or gun.speaker_blank.playing
		if bursts > 0:
			break
	if shell == "blank":
		_check(blank_seen and bursts == 0 and gun.roundManager.health_opponent == hp, "blank actually fired without dealer damage or blood")
	else:
		_check(bursts == 1 and anchored and gun.roundManager.health_opponent == hp - 1, "one spatial impact at the pre-recoil head on " + ("lethal self-shot" if dealer_fires else "player hit"))
		var material: StandardMaterial3D = effect.multimesh.mesh.material
		_check(effect.multimesh.mesh is SphereMesh and effect.multimesh.instance_count > 1 and not material.no_depth_test and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "opaque depth-tested 3D droplets")
		var start := effect.global_position
		var parent := mod.rig as Node3D
		var old_frame := parent.global_transform
		parent.global_position += Vector3.UP
		for i in range(4):
			await get_tree().process_frame
		_check(effect.global_position.is_equal_approx(start), "impact stays in the world while dealer and rig move")
		parent.global_transform = old_frame
		if dealer_fires:
			# Check the authored lethal splatter is still running alongside the replacement.
			for i in range(110):
				if gun.anim_splatter.current_animation == "fade out":
					break
				await get_tree().process_frame
			_check(gun.anim_splatter.current_animation == "fade out" and plane.layers == 0 and bursts == 1, "delayed lethal overlay stays suppressed without a double burst")
		else:
			for i in range(55):
				await get_tree().process_frame
			_check(not effect.visible, "nonlethal impact expires")
			var death := scene.get_node("standalone managers/death manager")
			death.animator_dealer.play("RESET")
			death.animator_dealer.advance(0)
			death.animator_dealer.play("dealer fly away")
			_check(bursts == 2 and effect.visible and anchored, "repeat recoil generates a fresh burst at the swapped head")
	mod._detach()
	_check(plane.layers == old_mask and plane.visible == was_visible and plane.material_override == old_material and not effect.visible, "detach restores the original mask and removes the burst")


func _measure_burst() -> void:
	if not effect.visible:
		return
	bursts += 1
	var head := crushed_head if crushed_head.layers != 0 else normal_head
	var bounds := head.mesh.get_aabb()
	var frame := head.global_transform
	if head == normal_head:
		var bones := head.get_node(head.skeleton) as Skeleton3D
		var index := bones.find_bone(head.skin.get_bind_name(0))
		frame = frame * bones.get_bone_global_pose(index) * head.skin.get_bind_pose(0)
	var point := frame.affine_inverse() * effect.global_position
	anchored = bounds.has_point(point) and point.y >= bounds.get_center().y
