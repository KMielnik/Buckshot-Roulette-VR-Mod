# Private QA mod entry point. The runner supplies an isolated retail copy.
extends Node

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
	print("WALK_QA ", "PASS " if value else "FAIL ", label)


func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	while not get_tree().current_scene or get_tree().current_scene.scene_file_path != "res://scenes/main.tscn":
		await get_tree().process_frame
	var scene := get_tree().current_scene
	var camera: Camera3D = scene.get_node("Camera")
	var intro := scene.get_node("standalone managers/intro manager")
	var mod := get_node("/root/ModLoader/TableVR-Bootstrap")
	mod._process(0.0) # Exercise the real adapter with the compositor disabled.
	for side in ["LeftGlove", "RightGlove"]:
		var player_hand: Skeleton3D = mod.rig.get_node(side).retail_hand
		_check(is_instance_valid(player_hand) and player_hand.get_bone_count() == 20 and player_hand.has_node("RetailSkin"), side + " uses the installed rig and skin")
	var view = mod.view_station
	var size_ratio: float = ProjectSettings.get_setting("buckshot_vr/world_size", .88)
	_check(is_equal_approx(XRServer.world_scale, 10.0 / clampf(size_ratio, .80, 1.20)), "configured game world size " + str(size_ratio))
	_check(is_equal_approx(mod.gameplay_units_per_metre(1.0), 10.0) and is_equal_approx(mod.gameplay_units_per_metre("bad"), 10.0 / .88), "scale override and invalid value fallback")
	_check(is_equal_approx(mod.gameplay_units_per_metre(0), 12.5) and is_equal_approx(mod.gameplay_units_per_metre(2), 10.0 / 1.2), "world size limited to supported range")
	var mode = view.actor.playback_process_mode
	var leg_layers: int = view.leg_layers
	var sockets: Array = scene.get_node("standalone managers/camera manager").socketArray
	for socket in sockets:
		if socket.socketName == "restroom":
			var restroom: Transform3D = view._socket_frame(camera.get_parent_node_3d().global_transform, socket)
			_check(view.station.origin.is_equal_approx(restroom.origin + Vector3.UP * .12 * view.units), "raise walking eye by 12 cm")
	var contacts := []
	view.kick_contact.connect(func(): contacts.append(view.sequence))
	while not intro.intbranch_bathroomdoor.interactionAllowed:
		await get_tree().process_frame
	var start: Vector3 = view.station.origin
	for i in range(10):
		view.update(Vector2.RIGHT, 1.0/90, Vector3.BACK)
	_check(absf(view.station.origin.distance_to(start) - 1.95 * view.units / 9.0) < .001, "bathroom sidestep at 1.95 m/s")
	for i in range(2):
		var target: Vector3 = view.centers[i] + view.units * view.forward_axes[i]
		var kicked := false
		var tested_inside := false
		var sampled_glide := false
		for tick in range(1600):
			var backward: Vector3 = view.station.origin - target
			backward.y = 0
			var depth: float = view._depth(view.station.origin, i)
			if i == 1 and not tested_inside and depth > .30 * view.units:
				for j in range(90):
					view.update(Vector2.ZERO, 1.0/90)
					await get_tree().process_frame
				_check(not view.table_locked and not view.arriving and intro.blockout.objArray_club[0].visible, "can pause 30 cm inside the game room")
				tested_inside = true
			view.update(Vector2(0,1), 1.0/90, backward.normalized())
			if view.arriving and not sampled_glide:
				sampled_glide = true
				var entry: Transform3D = view.station
				_check(view._depth(entry.origin, 1) >= .75 * view.units and entry.origin.distance_to(view.desk.origin) > 1, "glide begins at the inner threshold")
				view.update(Vector2.RIGHT, .04, Vector3.ZERO, false)
				_check(entry.is_equal_approx(view.station), "glide pauses on focus loss")
				for j in range(28):
					view.update(Vector2.ZERO, 1.0/90)
				var middle: Transform3D = view.station
				_check(not view.table_locked and middle.origin.distance_to(entry.origin) > .1 and middle.origin.distance_to(view.desk.origin) > .1 and intro.blockout.objArray_club[0].visible, "camera travels through intermediate poses before the game starts")
			await get_tree().process_frame
			if view.activated[i] and not kicked:
				kicked = true
				var before: Transform3D = view.station
				for j in range(120):
					view.update(Vector2.ZERO, 1.0/90)
					await get_tree().process_frame
				_check(before.is_equal_approx(view.station) and view.opened[i], "kick opens door with player stationary " + str(i+1))
				_check(not view.table_locked and intro.blockout.objArray_club[0].visible, "game waits outside door " + str(i+1))
			if (i == 0 and view._depth(view.station.origin,0) > 2.0) or (i == 1 and view.table_locked):
				break
		_check(kicked and view.opened[i], "approach trigger " + str(i+1))
		if i == 1:
			_check(tested_inside and sampled_glide, "deeper entry and animated handoff both exercised")
	var desk: Transform3D = view.station
	_check(contacts == [0, 1], "one haptic contact as each kicked door starts swinging")
	var manager := scene.get_node("standalone managers/camera manager")
	var fixed := true
	for socket in manager.socketArray:
		if socket.socketName == "home":
			var home: Transform3D = view._socket_frame(camera.get_parent_node_3d().global_transform, socket)
			_check(home.origin.is_equal_approx(desk.origin - home.basis.z * 0.10 * view.units), "desk is at authored eye height and 10 cm back")
		camera.position = socket.pos
		camera.rotation_degrees = socket.rot
		fixed = fixed and view.update(Vector2(1,1),1.0/90).is_equal_approx(desk)
	_check(view.table_locked and fixed, "desk stays fixed across %d camera sockets and stick input" % manager.socketArray.size())
	_check(not intro.blockout.objArray_club[0].visible and view.actor.playback_process_mode == mode, "original room-entry callback and animation clock")
	mod._stop_session()
	_check(is_equal_approx(XRServer.world_scale, mod.saved_scale), "XR teardown restores previous world scale")
	_check(camera.is_current() and not get_viewport().use_xr and scene.get_node("intro parent/player leg").layers == leg_layers, "restore desktop and kick mesh")
	print("WALK_QA failures=", failures)
	get_tree().quit(0 if failures == 0 else 2)
