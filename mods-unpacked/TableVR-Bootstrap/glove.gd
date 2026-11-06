extends XRController3D

const RetailHand := preload("res://mods-unpacked/TableVR-Bootstrap/retail_hand.gd")

# The original procedural gloves also work in the asset-free test room.
var shell := Node3D.new()
var knuckles: Array[Node3D] = []
var tips: Array[Node3D] = []
var thumb: Node3D
var leather := StandardMaterial3D.new()
var seam := StandardMaterial3D.new()
var cuff := StandardMaterial3D.new()
var brass := StandardMaterial3D.new()
var last_trigger := 0.0
var last_grip := 0.0
var retail_hand: RetailHand
var index_ray := Transform3D.IDENTITY # Open index tip and direction in tracked grip space.
var wrist_in_grip := Vector3.ZERO
var resting_shell := Transform3D.IDENTITY
var restrained := false


func _ready() -> void:
	add_child(shell)
	visible = false
	retail_hand = RetailHand.new()
	if retail_hand.configure(tracker == &"right_hand", XRServer.world_scale):
		shell.add_child(retail_hand)
		wrist_in_grip = retail_hand.transform * retail_hand.get_bone_global_rest(retail_hand.find_bone("Bone")).origin
		if tracker == &"right_hand":
			var segment := retail_hand.open_index_segment()
			_cache_index_ray(segment[0], segment[1])
		print("[TableVR] ", tracker, " retail player hand")
		return
	retail_hand.free()
	retail_hand = null
	thumb = Node3D.new()
	var side := 1.0 if tracker == &"right_hand" else -1.0
	_color(leather, Color("#665248"))
	_color(seam, Color("#342d2a"))
	_color(cuff, Color("#824436"))
	_color(brass, Color("#c49960"))
	shell.basis = Basis(Vector3.BACK * side, Vector3.RIGHT * side, Vector3.UP)
	shell.scale *= XRServer.world_scale
	# Sections run from fingertips (-Z) to wrist (+Z); widths and depths are half-extents.
	_piece(shell, [Vector3(.039,.011,-.051), Vector3(.046,.021,-.032),
		Vector3(.042,.023,.010), Vector3(.030,.015,.047)], leather)
	var back_patch := _piece(shell, [Vector3(.030,.002,-.032), Vector3(.034,.004,-.022),
		Vector3(.021,.003,.018), Vector3(.014,.002,.022)], seam)
	back_patch.position.y = .018
	for i in range(4):
		var ridge := _piece(shell, [Vector3(.005,.002,-.008), Vector3(.008,.005,0),
			Vector3(.006,.003,.010)], leather)
		ridge.position = Vector3(side*(-.024 + i*.016), .022, -.024)
	_piece(shell, [Vector3(.034,.020,.036), Vector3(.037,.024,.052),
		Vector3(.033,.022,.082)], cuff)
	_piece(shell, [Vector3(.037,.024,.047), Vector3(.038,.025,.058)], seam)
	var clasp := _piece(shell, [Vector3(.011,.003,-.005), Vector3(.011,.003,.005)], brass)
	clasp.position = Vector3(0,.025,.052)
	var lengths := [.083, .090, .083, .066]
	for i in range(4):
		var joint := Node3D.new()
		shell.add_child(joint)
		joint.position = Vector3(side * (-.030 + .020 * i), 0, -.044 + .003 * abs(i - 1))
		joint.rotation.y = side * (.04 - .025 * i)
		knuckles.append(joint)
		var length_m: float = lengths[i]
		var width := .0105 if i != 3 else .009
		_piece(joint, [Vector3(width*.83,width*.83,-length_m*.55),
			Vector3(width,width,-length_m*.18), Vector3(width,width,.004)], leather)
		var pad := _piece(joint, [Vector3(width*.72,.002,-.008),Vector3(width*.82,.003,.005)], seam)
		pad.position = Vector3(0,width,-.006)
		var distal := Node3D.new()
		joint.add_child(distal)
		distal.position.z = -length_m*.51
		tips.append(distal)
		_piece(distal, [Vector3(width*.50,width*.53,-length_m*.49),
			Vector3(width*.84,width*.83,-length_m*.37), Vector3(width*.89,width*.9,.002)], leather)
	thumb.position = Vector3(-side*.031,-.005,.015)
	thumb.rotation.y = side*.85
	shell.add_child(thumb)
	_piece(thumb, [Vector3(.006,.007,-.061), Vector3(.012,.012,-.046),
		Vector3(.013,.014,-.020), Vector3(.016,.014,.004)], leather)
	_pose(0, 0)
	resting_shell = shell.transform
	wrist_in_grip = resting_shell * Vector3(0, 0, .047)
	if tracker == &"right_hand":
		var base := shell.transform * knuckles[0].transform
		var tip := base * tips[0].transform * Vector3(0, 0, -float(lengths[0]) * .49)
		_cache_index_ray(base.origin, tip)
	visible = false


func _cache_index_ray(base: Vector3, tip: Vector3) -> void:
	# Measure the existing hand in grip space. Use the resting index for clicks,
	# even while its animation bends toward the palm.
	var direction := (tip - base).normalized()
	var up := Vector3.BACK if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
	index_ray = Transform3D(Basis.IDENTITY, tip).looking_at(tip + direction, up)


func rescale_for_scene(ratio: float) -> void:
	release_restraint()
	shell.scale *= ratio
	resting_shell = shell.transform
	index_ray.origin *= ratio
	wrist_in_grip *= ratio


func restrain_at(wrist: Vector3, fingers: Vector3) -> void:
	if not restrained:
		restrained = true
		shell.top_level = true
		_pose(.35, .65)
	# Grip -Y extends along the hand. Turn the dorsal side upward at the rail.
	var y_axis := -fingers.normalized()
	var dorsal := Vector3.BACK if absf(y_axis.dot(Vector3.UP)) > .97 else Vector3.UP
	var x_axis := dorsal.slide(y_axis).normalized()
	if tracker == &"left_hand":
		x_axis = -x_axis
	var frame := Basis(x_axis, y_axis, x_axis.cross(y_axis))
	shell.global_transform = Transform3D(frame, wrist - frame * wrist_in_grip) * resting_shell


func release_restraint() -> void:
	if not restrained:
		return
	restrained = false
	shell.top_level = false
	shell.transform = resting_shell
	last_trigger = -1.0
	last_grip = -1.0


func _color(mat: StandardMaterial3D, color: Color) -> void:
	mat.albedo_color = color
	mat.roughness = 0.88
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.22


func _piece(parent: Node3D, rings: Array, mat: Material) -> MeshInstance3D:
	# Soft octagonal cross-sections with flat faces and closed ends.
	var vertices := PackedVector3Array()
	for section in rings:
		var ring: Vector3 = section
		for i in range(8):
			var angle := TAU * (i + 0.5) / 8.0
			vertices.append(Vector3(cos(angle)*ring.x, sin(angle)*ring.y, ring.z))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for row in range(rings.size() - 1):
		for i in range(8):
			var a := row*8 + i
			var b := row*8 + (i + 1)%8
			for index in [a, b+8, b, a, a+8, b+8]:
				surface.add_vertex(vertices[index])
	var last := (rings.size()-1)*8
	for i in range(1,7):
		for index in [0,i,i+1,last,last+i+1,last+i]:
			surface.add_vertex(vertices[index])
	surface.generate_normals()
	var part := MeshInstance3D.new()
	part.mesh = surface.commit()
	part.material_override = mat
	parent.add_child(part)
	return part


func _pose(index_pull: float, squeeze: float) -> void:
	if retail_hand != null:
		retail_hand.set_curl(index_pull, squeeze)
		return
	for i in range(4):
		var curl := index_pull if i == 0 else squeeze
		var rest := -6.0 if i == 0 else -12.0 - 3.0*i
		knuckles[i].rotation.x = deg_to_rad(lerpf(rest, -68.0, curl))
		tips[i].rotation.x = deg_to_rad(lerpf(rest, -76.0, curl))
	thumb.rotation.x = deg_to_rad(lerpf(-18.0, -43.0, squeeze))


func sample(can_interact: bool) -> void:
	if restrained:
		visible = can_interact
		return
	visible = can_interact and get_has_tracking_data()
	if visible:
		var trigger := clampf(get_float(&"trigger"), 0.0, 1.0)
		var grip := clampf(get_float(&"grip"), 0.0, 1.0)
		if not is_equal_approx(trigger, last_trigger) or not is_equal_approx(grip, last_grip):
			last_trigger = trigger
			last_grip = grip
			_pose(trigger, grip)
