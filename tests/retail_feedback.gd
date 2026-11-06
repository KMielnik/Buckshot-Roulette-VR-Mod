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
	bus.strength = 1.0
	bus.set_active(false)
	bus.set_active(true)
	bus.cue(&"shot")
	check(bus.tails.size() == 1, "recoil tail is queued only for the tracked hand")
	bus.set_active(false)
	check(bus.tails.is_empty(), "focus loss cancels every delayed feedback beat")
	var observed := []
	var watcher = mod.action_feedback
	check(watcher != null and watcher.speakers.size() >= 7, "native action audio and animations are bound")
	watcher.feedback.connect(func(kind): observed.append(kind))
	watcher.update(true)
	var shooter = watcher.shooter
	shooter.animator_shotgun.play("player shoot dealer")
	shooter.whoshot = "dealer"
	shooter.shellSpawner.sequenceArray.assign(["live"])
	shooter.PlayShootingSound()
	shooter.animator_muzzleFlash.advance(0)
	check(observed.count(&"shot") == 1, "accepted live player shot generates recoil at muzzle flash")
	shooter.animator_muzzleFlash.stop()
	shooter.whoshot = "player"
	shooter.PlayShootingSound()
	shooter.animator_muzzleFlash.advance(0)
	check(observed.count(&"shot") == 1, "player impact owns feedback for a self shot")
	shooter.animator_shotgun.play("enemy shoot self")
	shooter.whoshot = "dealer"
	shooter.animator_muzzleFlash.stop()
	shooter.PlayShootingSound()
	shooter.animator_muzzleFlash.advance(0)
	check(observed.count(&"shot") == 1, "dealer firing does not pretend the player fired")
	shooter.animator_shotgun.play("player shoot dealer")
	shooter.shellSpawner.sequenceArray.assign(["blank"])
	shooter.PlayShootingSound()
	watcher.update(true)
	check(observed.count(&"dry_fire") == 1, "blank makes a distinct mechanical click")
	watcher.update(true)
	check(observed.count(&"dry_fire") == 1, "continuing audio cannot retrigger feedback")
	shooter.ejectionManager_player.animator.play("ejecting shell_player1")
	check(observed.count(&"eject") == 1, "local shell ejection generates its own feedback")
	var items = get_tree().current_scene.get_node("standalone managers/item interaction")
	for sound in ["player use handsaw1.ogg", "player use inverter.ogg", "player break handcuffs.ogg", "player use cigarettes1.ogg"]:
		items.PlaySound(load("res://audio/" + sound))
		watcher.update(true)
	check(observed.has(&"saw") and observed.has(&"invert") and observed.has(&"release") and observed.has(&"lighter"), "distinct item and cuff release feedback comes from actual sound playback")
	watcher.update(false)
	n = observed.size()
	items.PlaySound(load("res://audio/player use medicine.ogg"))
	watcher.update(false)
	watcher.update(true)
	check(observed.size() == n, "events while unfocused are consumed without replay")
	shooter.animator_muzzleFlash.stop()
	shooter.roundManager.health_opponent = 4
	shooter.shellSpawner.sequenceArray.assign(["live", "blank"])
	var count_before := observed.count(&"shot")
	var shots_before: int = shooter.roundManager.playerData.stat_shotsFired
	shooter.Shoot("dealer")
	for tick in 280:
		await get_tree().process_frame
		watcher.update(true)
		if shooter.roundManager.playerData.stat_shotsFired > shots_before: break
	check(observed.count(&"shot") == count_before + 1 and shooter.roundManager.health_opponent == 3, "real delayed Shoot routine produces recoil after the aiming animation has finished")
	for device in trackers:
		XRServer.remove_tracker(device)
	mod._stop_session()
	print("FEEDBACK_QA failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
