extends Node

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("UI_QA ", "PASS " if ok else "FAIL ", label)


func _run() -> void:
	var mod := get_node("/root/ModLoader/TableVR-Bootstrap")
	while not get_tree().current_scene or get_tree().current_scene.scene_file_path != mod.MENU:
		await get_tree().process_frame
	mod._process(0.0)
	var grade = mod.grade
	var menu_env: Environment = get_tree().root.world_3d.environment
	check(grade != null and menu_env.adjustment_color_correction == grade.ramp and grade.ramp != null, "menu applies the authored palette to its 3D world")
	var falls = mod.menu_bullets
	check(is_instance_valid(falls) and falls.streams.size() == 2, "both original casing streams mounted")
	if not is_instance_valid(falls):
		get_tree().quit(1)
		return
	var masks: Dictionary = falls.saved_masks.duplicate()
	for stream in falls.streams:
		stream.actor.play(falls.CLIP)
		var each_wrap: Array[int] = []
		each_wrap.resize(stream.copies.size())
		var safe := true
		var off_screen := true
		check(stream.copies.size() in [6, 7], "fixed casing meshes per stream")
		for tick in range(ceili(3.1 * stream.actor.current_animation_length / absf(stream.actor.get_playing_speed()) * 90)):
			var before: Array[AABB] = []
			for shell in stream.copies:
				before.append(shell.global_transform * shell.get_aabb())
			stream.advance(1.0 / 90.0)
			var jumped := 0
			for i in stream.copies.size():
				var shell = stream.copies[i]
				var after: AABB = shell.global_transform * shell.get_aabb()
				if after.position.y > before[i].position.y + 1.0:
					jumped += 1
					each_wrap[i] += 1
					if before[i].end.y > -3.10 or after.position.y < 2.95:
						off_screen = false
						print("UI_QA wrap limits ", before[i].end.y, " / ", after.position.y)
			safe = safe and jumped <= 1
		check(safe and not each_wrap.has(0), "one segment at a time wraps over a full cycle")
		check(off_screen, "every wrap occurs beyond both shader fade limits")
	falls.unmount()
	grade.unmount()
	check(menu_env.adjustment_color_correction == null, "stock menu environment restored on teardown")
	var restored := true
	for source in masks:
		restored = restored and source.layers == masks[source] and source.layers != 0
	check(restored, "original casing visibility restored when leaving VR")
	get_tree().change_scene_to_file(mod.MAIN)
	while not get_tree().current_scene or get_tree().current_scene.scene_file_path != mod.MAIN:
		await get_tree().process_frame
	mod._process(0.0)
	var cards = mod.table_text
	var speaker := get_tree().current_scene.get_node("standalone managers/dialogue manager")
	check(is_instance_valid(cards), "retail table text mounted")
	if is_instance_valid(cards):
		cards.blocker.hide()
		cards.set_active(true)
		speaker.ShowDealerInspectionText()
		cards._process(0.0)
		check(cards.dialogue.is_visible_in_tree() and cards.dialogue.text == speaker.dialogueUI.text.left(1), "shows first character when retail starts speaking")
		speaker.dialogueUI.visible_characters = -1
		cards._process(0.0)
		check(cards.dialogue.text == speaker.dialogueUI.text, "completed line matches original dealer text")
		cards.blocker.show()
		cards._process(0.0)
		check(not cards.is_visible_in_tree(), "blackout covers the dialogue")
		cards.blocker.hide()
		speaker.HideText()
		cards._process(0.0)
		check(not cards.dialogue.visible, "retail HideText clears the stereo line")
		cards.set_active(false)
		check(not cards.visible, "focus loss clears both cards")
	var cuffs = mod.cuffs
	var manager := get_tree().current_scene.get_node("standalone managers/handcuff manager")
	manager.roundManager.playerCuffed = true
	await manager.AttachHandCuffs()
	check(cuffs.update(true) and cuffs.left.restrained and cuffs.right.restrained, "ordinary game holds both wrists on native attach")
	manager.RemoveAllCuffsRoutine()
	while manager.roundManager.playerCuffed:
		await get_tree().process_frame
	check(cuffs.update(true) and cuffs.right.restrained, "hands remain at rail during opening keyframes")
	for frame in range(110):
		await get_tree().process_frame
	check(not cuffs.update(true) and not cuffs.right.restrained and not cuffs.left.restrained, "ordinary game restores tracked hands on release")
	print("UI_QA failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
