extends Node

var failures := 0
var pulses := []


func _ready() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("FEEDBACK_QA ", "PASS " if ok else "FAIL ", label)


func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	while not get_tree().current_scene or get_tree().current_scene.scene_file_path != "res://scenes/main.tscn":
		await get_tree().process_frame
	var mod := get_node("/root/ModLoader/TableVR-Bootstrap")
	mod._process(0.0)
	var bus = mod.haptics
	var trackers := []
	for side in [&"left_hand", &"right_hand"]:
		var device := XRPositionalTracker.new()
		device.type = XRServer.TRACKER_CONTROLLER
		device.name = side
		XRServer.add_tracker(device)
		device.set_pose(&"grip", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		trackers.append(device)
	bus.pulse_requested.connect(func(side, kind, amplitude, duration): pulses.append([side, kind, amplitude, duration]))
	bus.set_active(true)
	mod.world_pointer.target_entered.emit()
	mod.world_pointer.target_entered.emit()
	check(pulses.size() == 1 and pulses[0][0] == &"right_hand" and pulses[0][1] == &"hover", "hover is right-hand only and rate-limited")
	mod.world_pointer.selected.emit("item", "beer", false)
	check(pulses.size() == 2 and pulses[1][1] == &"item", "item confirmation can interrupt hover")
	mod.player_impact.player_hit.emit()
	mod.world_pointer.target_entered.emit()
	check(pulses.size() == 4 and pulses[2][1] == &"hit" and pulses[3][0] == &"left_hand" and pulses[3][2] > .75 and pulses[3][3] < .1, "short strong hit reaches both hands and suppresses weaker output")
	for entry in [["shotgun", "", false, &"metal"], ["item", "handcuffs", false, &"metal"], ["", "", true, &"place"], ["release form on table", "", false, &"paper"], ["signature machine button", "", false, &"key"]]:
		bus.set_active(false)
		bus.set_active(true)
		mod.world_pointer.selected.emit(entry[0], entry[1], entry[2])
		check(pulses.back()[1] == entry[3], "accepted action routes to " + str(entry[3]))
	bus.set_active(false)
	bus.set_active(true)
	var n := pulses.size()
	mod.view_station.kick_contact.emit()
	check(pulses.size() == n + 2 and pulses.back()[1] == &"kick", "kick reaches both motors")
	bus.set_active(false)
	bus.set_active(true)
	trackers[0].invalidate_pose(&"grip")
	n = pulses.size()
	mod.player_impact.revived.emit()
	check(pulses.size() == n + 1 and pulses.back()[0] == &"right_hand" and pulses.back()[1] == &"revival", "revival skips an untracked hand")
	mod._set_focus(false)
	n = pulses.size()
	mod.view_station.kick_contact.emit()
	check(pulses.size() == n, "unfocused game sends no pulse")
	bus.strength = 0.0
	bus.set_active(true)
	mod.player_impact.player_hit.emit()
	check(pulses.size() == n, "zero strength disables output")
	for device in trackers:
		XRServer.remove_tracker(device)
	mod._stop_session()
	print("FEEDBACK_QA failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
