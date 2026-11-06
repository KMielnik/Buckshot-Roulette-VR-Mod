extends RefCounted

signal kick_contact

const WalkArea := preload("res://mods-unpacked/TableVR-Bootstrap/walk_area.gd")
const CLIPS := [&"camera exit bathroom", &"camera enter backroom"]
const DESK_SETBACK_M := 0.10
const WALK_EYE_LIFT_M := 0.12
const ENTRY_DEPTH_M := 0.75
const ARRIVAL_SECONDS := 0.65
const DEADZONE := 0.22
const WALK_SPEED_M_S := 1.95

var desk: Transform3D
var station: Transform3D
var table_locked := false
var arriving := false
var arrival_start: Transform3D
var arrival_elapsed := 0.0
var units: float
var floor_area := WalkArea.new()
var camera: Camera3D
var interaction: Node
var branches: Array[Node] = []
var centers := PackedVector3Array()
var forward_axes := PackedVector3Array()
var half_widths := PackedFloat32Array()
var actor: AnimationPlayer
var leg: MeshInstance3D
var boot: MeshInstance3D
var leg_layers: int
var opened := [false, false]
var activated := [false, false]
var sequence := -1
var saved_mode: AnimationPlayer.AnimationProcessCallback
var windup := 0.0
var swing_end := 0.0
var contact_time := 0.0
var begin_game := 0.0


func bind(scene: Node, desktop: Camera3D, scale_factor: float) -> bool:
	var manager := scene.get_node_or_null("standalone managers/camera manager")
	var intro := scene.get_node_or_null("standalone managers/intro manager")
	var club := scene.get_node_or_null("backroom main parent/Cube_120_CLUB") as Node3D
	var bathroom := scene.get_node_or_null("restroom_CLUB") as MeshInstance3D
	var walkway := scene.get_node_or_null("backroom main parent/Cube_120_CLUB/Empty_002/Cube_095") as MeshInstance3D
	leg = scene.get_node_or_null("intro parent/player leg")
	interaction = scene.get_node_or_null("standalone managers/interaction manager")
	if manager == null or intro == null or club == null or bathroom == null or walkway == null or leg == null or interaction == null or manager.get("cam") != desktop:
		return false
	actor = intro.get("animator_camera")
	if actor == null:
		return false
	var sockets := {}
	for resource in manager.socketArray:
		sockets[resource.socketName] = resource
	if not sockets.has("home") or not sockets.has("restroom"):
		return false
	camera = desktop
	units = scale_factor
	var parent_frame := desktop.get_parent_node_3d().global_transform
	desk = _socket_frame(parent_frame, sockets["home"])
	desk.origin += desk.basis.z * DESK_SETBACK_M * units
	station = _socket_frame(parent_frame, sockets["restroom"])
	station.origin.y += WALK_EYE_LIFT_M * units
	branches.assign([intro.intbranch_bathroomdoor, intro.intbranch_backroomdoor])
	for i in range(2):
		if not _read_door(i):
			return false
	var first_door := branches[0].get_parent() as MeshInstance3D
	var door_bounds := first_door.global_transform * first_door.get_aabb()
	floor_area.add_room(bathroom, door_bounds.position.y, units)
	floor_area.set_grating(walkway)
	if floor_area.floors.is_empty():
		return false
	leg_layers = leg.layers
	boot = MeshInstance3D.new()
	boot.name = "TableVRKick"
	boot.mesh = leg.mesh
	boot.material_override = leg.material_override
	for i in range(leg.get_surface_override_material_count()):
		boot.set_surface_override_material(i, leg.get_surface_override_material(i))
	boot.visible = false
	scene.add_child(boot)
	leg.layers = 0
	actor.animation_started.connect(_animation_started)
	if actor.is_playing() and CLIPS.has(actor.current_animation):
		station.origin = camera.global_position + Vector3.UP * WALK_EYE_LIFT_M * units
		_start_sequence(CLIPS.find(actor.current_animation))
	elif not club.visible:
		_lock_table()
	elif branches[1].interactionAllowed:
		opened[0] = true
		activated[0] = true
		station.origin = camera.global_position + Vector3.UP * WALK_EYE_LIFT_M * units
	return true


func _socket_frame(frame: Transform3D, socket: Resource) -> Transform3D:
	return frame * Transform3D(Basis(Vector3.UP, deg_to_rad(socket.rot.y)), socket.pos)


func _read_door(i: int) -> bool:
	var mesh := branches[i].get_parent() as MeshInstance3D
	if mesh == null or not actor.has_animation(CLIPS[i]):
		return false
	var box := mesh.global_transform * mesh.get_aabb()
	centers.append(box.get_center())
	var axis := mesh.global_transform.basis.x
	axis.y = 0
	axis = axis.normalized()
	if axis.dot(desk.origin - station.origin) < 0:
		axis = -axis
	forward_axes.append(axis)
	var sideways := axis.cross(Vector3.UP).abs()
	half_widths.append(box.size.dot(sideways) * 0.5)
	var clip := actor.get_animation(CLIPS[i])
	var leg_track := clip.find_track(NodePath("player leg:visible"), Animation.TYPE_VALUE)
	var rotation_track := clip.find_track(NodePath(str(mesh.name) + ":rotation"), Animation.TYPE_VALUE)
	if leg_track < 0 or rotation_track < 0 or clip.track_get_key_count(leg_track) < 2 or clip.track_get_key_count(rotation_track) < 2:
		return false
	if i == 1:
		for track in range(clip.get_track_count()):
			if clip.track_get_type(track) == Animation.TYPE_METHOD:
				for key in range(clip.track_get_key_count(track)):
					if clip.method_track_get_name(track, key) == &"BeginGame":
						begin_game = clip.track_get_key_time(track,key)
		return begin_game > clip.track_get_key_time(rotation_track, 1)
	return true


func update(stick: Vector2, delta: float, head_back := Vector3.ZERO, interaction_enabled := true) -> Transform3D:
	if table_locked:
		return desk
	if arriving:
		if interaction_enabled:
			_advance_arrival(delta)
		return station
	if stick.length() > DEADZONE:
		var back := Vector3(head_back.x, 0, head_back.z)
		back = station.basis.z if back.length_squared() < .001 else back.normalized()
		var force := clampf((stick.length() - DEADZONE) / (1.0 - DEADZONE), 0, 1)
		var input := stick.normalized()
		var travel := (Vector3.UP.cross(back)*input.x - back*input.y) * force * units * WALK_SPEED_M_S * minf(delta,.05)
		# Slide along the room walls when one component is blocked.
		_step(Vector3(travel.x,0,0))
		_step(Vector3(0,0,travel.z))
	if interaction_enabled:
		_check_approach()
	if sequence >= 0:
		_tick_kick(delta, interaction_enabled)
	return station


func _step(offset: Vector3) -> void:
	if offset.is_zero_approx():
		return
	var point := station.origin + offset
	for i in range(2):
		var distance := _depth(point, i)
		var lateral := absf((point - centers[i]).dot(forward_axes[i].cross(Vector3.UP)))
		# The club grating ends at the second door. Its open threshold continues
		# straight into the game room as far as the walking-to-desk handoff.
		var inside_limit := ENTRY_DEPTH_M + 0.15 if i == 1 else 0.45
		if distance > -0.45 * units and distance < inside_limit * units and lateral < half_widths[i] - floor_area.radius:
			if opened[i] or distance < -floor_area.radius:
				station.origin = point
			return
		# Rooms can only be crossed through the doorway. This also keeps the club
		# side of the threshold closed while its authored swing is still playing.
		if _depth(station.origin, i) * distance <= 0 and (not opened[i] or lateral >= half_widths[i] - floor_area.radius):
			return
	if floor_area.contains(Vector2(point.x,point.z)):
		station.origin = point


func _depth(point: Vector3, i: int) -> float:
	return (point - centers[i]).dot(forward_axes[i])


func _check_approach() -> void:
	if sequence >= 0:
		return
	var i := 1 if opened[0] else 0
	if activated[i]:
		return
	var distance := _depth(station.origin,i)
	var sideways := absf((station.origin - centers[i]).dot(forward_axes[i].cross(Vector3.UP)))
	var branch := branches[i]
	if distance < -1.12*units or distance > 0 or sideways > half_widths[i] - floor_area.radius:
		return
	if not interaction.cursor.cursor_visible or not branch.interactionAllowed or branch.interactionInvalid:
		return
	var previous = interaction.activeInteractionBranch
	interaction.activeInteractionBranch = branch
	interaction.MainInteractionEvent()
	interaction.activeInteractionBranch = previous


func _animation_started(clip: StringName) -> void:
	if table_locked:
		return
	var index := CLIPS.find(clip)
	if index >= 0:
		_start_sequence(index)


func _start_sequence(i: int) -> void:
	if sequence == i:
		return
	_release_timeline()
	activated[i] = true
	sequence = i
	var clip := actor.get_animation(CLIPS[i])
	var leg_track := clip.find_track(NodePath("player leg:visible"), Animation.TYPE_VALUE)
	var rotation_track := clip.find_track(NodePath(str(branches[i].get_parent().name) + ":rotation"), Animation.TYPE_VALUE)
	windup = maxf(0, clip.track_get_key_time(leg_track,1) - .16)
	swing_end = clip.track_get_key_time(rotation_track,1)
	contact_time = clip.track_get_key_time(rotation_track, 0)
	saved_mode = actor.playback_process_mode
	actor.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
	print("[TableVR] proximity kick ", CLIPS[i])


func _tick_kick(delta: float, can_enter: bool) -> void:
	var i := sequence
	var clock := actor.current_animation_position
	var target := maxf(clock, windup) + minf(delta,.05)
	if i == 1:
		# BeginGame hides the club. Keep that method key pending through the glide.
		target = minf(target, begin_game - .015)
	actor.advance(maxf(0,target - clock))
	if clock < contact_time and target >= contact_time:
		kick_contact.emit()
	opened[i] = opened[i] or target >= swing_end
	boot.visible = leg.visible and target < swing_end + .28 and station.origin.distance_to(centers[i]) < 1.9*units
	if boot.visible:
		var pose := leg.global_transform
		pose.origin += station.origin - Vector3.UP * WALK_EYE_LIFT_M * units - camera.global_position
		boot.global_transform = pose
	if i == 1 and can_enter and target >= begin_game - .015 and _depth(station.origin,1) >= ENTRY_DEPTH_M * units:
		arriving = true
		arrival_start = station
		arrival_elapsed = 0.0
		print("[TableVR] crossed game-room entry; moving to desk")
	elif i == 0 and target >= swing_end + .30:
		# The remaining vanilla animation can run in the background. It no longer owns the view.
		_release_timeline()


func start_from_eye(position: Vector3, yaw: float) -> void:
	# Start exactly where the wearer is looking, including any lean or stick turn.
	arrival_start = Transform3D(Basis(Vector3.UP, yaw), position)
	station = arrival_start


func _advance_arrival(delta: float) -> void:
	arrival_elapsed = minf(arrival_elapsed + minf(delta, 0.05), ARRIVAL_SECONDS)
	var weight := smoothstep(0.0, ARRIVAL_SECONDS, arrival_elapsed)
	station = arrival_start.interpolate_with(desk, weight)
	if arrival_elapsed >= ARRIVAL_SECONDS:
		actor.advance(maxf(0, begin_game - actor.current_animation_position) + .001)
		_release_timeline()
		arriving = false
		_lock_table()


func _lock_table() -> void:
	station = desk
	table_locked = true
	print("[TableVR] entered game room; desk position locked")


func _release_timeline() -> void:
	if sequence >= 0 and is_instance_valid(actor):
		actor.playback_process_mode = saved_mode
	sequence = -1
	if is_instance_valid(boot):
		boot.visible = false


func unbind() -> void:
	_release_timeline()
	if is_instance_valid(actor) and actor.animation_started.is_connected(_animation_started):
		actor.animation_started.disconnect(_animation_started)
	if is_instance_valid(leg):
		leg.layers = leg_layers
	if is_instance_valid(boot):
		boot.queue_free()
