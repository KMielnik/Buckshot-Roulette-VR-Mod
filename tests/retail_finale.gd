extends Node

var failures := 0
var mod: Node

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("FINALE_QA ", "PASS " if ok else "FAIL ", label)

func _run() -> void:
	mod = get_node("/root/ModLoader/TableVR-Bootstrap")
	get_tree().change_scene_to_file(mod.MAIN)
	while get_tree().current_scene == null or get_tree().current_scene.scene_file_path != mod.MAIN:
		await get_tree().process_frame
	mod._process(0)
	mod.focused = true
	mod.needs_anchor = false
	mod.calibration = Transform3D.IDENTITY
	var finale = mod.finale
	var ending = finale.ending
	# Reset the first-win marker only in this automation-only profile.
	if OS.get_user_data_dir().get_file() != "BuckshotVR-QA-ending":
		get_tree().quit(1)
		return
	if FileAccess.file_exists(ending.unlocker.savepath):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ending.unlocker.savepath))
	var brief = finale.brief
	brief.MainRoutine()
	for i in 800: await get_tree().process_frame
	check(brief.intbranch_L.interactionAllowed and brief.intbranch_R.interactionAllowed, "stock cash case enables both locks")
	ending.roundManager.playerData.stat_shotsFired = 6
	brief.OpenLatch("R")
	mod._process(.01)
	check(not finale.active, "first latch cannot start ending")
	brief.OpenLatch("L")
	for i in 36:
		await get_tree().process_frame
		mod._process(1./90.)
	check(finale.active and not brief.intbranch_lid.interactionAllowed and ending.animator_pan.is_playing(), "both locks start one native pan automatically")
	var scene := get_tree().current_scene
	var seen_black := false
	var pan_matched := false
	var car_matched := false
	var car_station := Transform3D.IDENTITY
	var score_station := Transform3D.IDENTITY
	var steady := true
	var native_moved := false
	for tick in 3600:
		await get_tree().process_frame
		mod._process(1./90.)
		if tick == 220 and finale.active:
			pan_matched = mod.rig.global_position.distance_to(mod.base_camera.global_position) < .02 and mod.rig.global_transform.basis.is_equal_approx(mod.base_camera.global_transform.basis.orthonormalized())
		if mod.player_impact.visible and mod.player_impact.cover.get_shader_parameter("tint").a >= .99:
			seen_black = true
		if ending.animator_cam.current_animation == "camera loop car" and finale.panel.visible:
			if not car_matched:
				car_matched = mod.rig.global_position.distance_to(mod.base_camera.global_position) < .02
				car_station = mod.rig.global_transform
				score_station = finale.panel.global_transform
			else:
				steady = steady and mod.rig.global_transform.is_equal_approx(car_station) and finale.panel.global_transform.is_equal_approx(score_station)
				native_moved = native_moved or not mod.base_camera.global_transform.is_equal_approx(car_station)
		if ending.waitingForInput: break
	check(pan_matched and car_matched, "VR base follows the authored case pan and moves to the car")
	check(steady and native_moved, "car seat and score stay fixed while the desktop camera shakes")
	var eye: XRCamera3D = mod.rig.get_node("Head")
	var old_eye := eye.transform
	eye.position += Vector3(.03, .01, -.02)
	check(not eye.global_transform.is_equal_approx(car_station) and mod.rig.global_transform.is_equal_approx(car_station), "head can lean independently of the fixed car seat")
	eye.transform = old_eye
	var table_hinge = brief.anim_lid.get_parent()
	var car_hinge = scene.get_node("player vehicle parent/vehicle/briefcase parent in vehicle/briefcase hinge")
	var table_span: float = table_hinge.get_node("briefcase latch_left").global_position.distance_to(table_hinge.get_node("briefcase latch_right").global_position)
	var car_span: float = car_hinge.get_node("briefcase latch_left").global_position.distance_to(car_hinge.get_node("briefcase latch_right").global_position)
	check(absf(car_span / XRServer.world_scale - table_span / mod.view_station.units) < .01, "cash case has consistent physical width at the table and in the smaller car set")
	check(seen_black, "ending's full-view fade covers the car cut")
	var score = ending.label_array[0]
	check(ending.waitingForInput and score.is_visible_in_tree() and score.get_child(2).text == "6" and ending.label_array[5].text.contains(str(ending.cash_gl)), "real score rows display the shot count and payout")
	check(finale.surface.canvas_cull_mask == finale.HUD_LAYER and (score.visibility_layer & finale.HUD_LAYER) != 0 and (ending.animator_anykey.get_parent().visibility_layer & finale.HUD_LAYER) != 0, "score and continue prompt routed to the stereo HUD")
	var t := XRPositionalTracker.new()
	t.type = XRServer.TRACKER_CONTROLLER
	t.name = &"right_hand"
	XRServer.add_tracker(t)
	t.set_pose(&"grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	t.set_input(&"trigger_click",true)
	mod._process(.01)
	check(ending.waitingForInput, "trigger held before prompt does not skip it")
	t.set_input(&"trigger_click",false)
	mod._process(.01)
	t.set_input(&"trigger_click",true)
	mod._process(.01)
	check(not ending.waitingForInput and not ending.isActive, "fresh index trigger runs original ending exit")
	var saw_unlock := false
	for tick in 1200:
		await get_tree().process_frame
		if not is_instance_valid(scene) or get_tree().current_scene != scene: break
		mod._process(1./90.)
		if finale.surface.canvas_cull_mask == finale.UNLOCK_LAYER and ending.unlocker.ui.visible_characters != 0 and not ending.unlocker.ui.text.is_empty():
			saw_unlock = finale.panel.visible and finale.panel.mesh.material.render_priority > mod.player_impact.cover.render_priority
	check(saw_unlock, "first win shows the native unlock text above the black exit fade")
	check(not is_instance_valid(scene) or get_tree().current_scene != scene, "native ending completes the scene transition")
	XRServer.remove_tracker(t)
	print("FINALE_QA failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
