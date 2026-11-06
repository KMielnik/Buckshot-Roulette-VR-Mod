extends RefCounted

# Read navigation geometry from the owner's installed room at runtime.
var floors: Array[PackedVector2Array] = []
var walls: Array[PackedVector2Array] = []
var radius: float
var grating := Rect2()


func set_grating(mesh: MeshInstance3D) -> void:
	# The authored club walkway is an open metal grate. The top of its footprint
	# supports the player across the gaps between bars.
	var box := mesh.global_transform * mesh.get_aabb()
	grating = Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


func add_room(node: MeshInstance3D, floor_height: float, units: float) -> void:
	radius = 0.16 * units
	var faces := node.mesh.get_faces()
	var slice_height := floor_height + 0.85 * units
	for i in range(0, faces.size(), 3):
		var a := node.global_transform * faces[i]
		var b := node.global_transform * faces[i+1]
		var c := node.global_transform * faces[i+2]
		var normal := (b-a).cross(c-a).normalized()
		if absf(normal.y) > 0.96 and maxf(absf(a.y-floor_height), maxf(absf(b.y-floor_height), absf(c.y-floor_height))) < 0.17 * units:
			floors.append(PackedVector2Array([Vector2(a.x,a.z), Vector2(b.x,b.z), Vector2(c.x,c.z)]))
		elif absf(normal.y) < .25:
			var intersections := PackedVector2Array()
			var vertices := [a,b,c]
			for j in range(3):
				var start: Vector3 = vertices[j]
				var end: Vector3 = vertices[(j+1)%3]
				if (start.y <= slice_height) != (end.y <= slice_height):
					var cut := start.lerp(end, inverse_lerp(start.y, end.y, slice_height))
					intersections.append(Vector2(cut.x,cut.z))
			if intersections.size() == 2 and intersections[0].distance_squared_to(intersections[1]) > 0.001:
				walls.append(intersections)


func contains(point: Vector2) -> bool:
	for wall in walls:
		if Geometry2D.get_closest_point_to_segment(point, wall[0], wall[1]).distance_squared_to(point) < radius*radius:
			return false
	for offset in [Vector2.ZERO, Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		if not _has_floor(point + offset * radius):
			return false
	return true


func _has_floor(point: Vector2) -> bool:
	if grating.has_point(point):
		return true
	for tri in floors:
		if Geometry2D.is_point_in_polygon(point, tri):
			return true
	return false
