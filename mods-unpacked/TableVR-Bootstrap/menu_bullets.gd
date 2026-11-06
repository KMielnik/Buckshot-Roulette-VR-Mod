extends Node3D

# Original meshes contain many casings. A fixed ring moves the meshes, while a
# height mask retires the lowest casings before their mesh wraps above the title.
const CLIP := &"main action"
const BOTTOM := -7.40
const SPACING := 2.51611
const PERIOD := 6.0 * SPACING
const SHELL_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D skin : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform sampler2D detail : hint_normal, filter_nearest_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.);
uniform float rough = 0.5;
uniform float relief = 1.;
uniform bool vertex_tint = true;
varying vec3 local_point;
varying float height;
void vertex() {
	local_point = VERTEX;
	height = (MODEL_MATRIX * vec4(VERTEX, 1.)).y;
}
void fragment() {
	float amount = smoothstep(-3.10, -2.4, height) * (1. - smoothstep(2.24, 2.95, height));
	// Mesh-space stipple remains fixed to each casing in both eyes. Surviving
	// fragments use opaque depth, including where the waterfall overlaps itself.
	if (amount < 1. && amount <= fract(dot(floor(local_point * 93.), vec3(.1031,.1669,.2141)))) { discard; }
	ALBEDO = texture(skin, UV).rgb * tint.rgb * (vertex_tint ? COLOR.rgb : vec3(1.));
	ROUGHNESS = rough;
	NORMAL_MAP = texture(detail, UV).rgb;
	NORMAL_MAP_DEPTH = relief;
}
"""

class Stream:
	var actor: AnimationPlayer
	var travel := 0.0
	var group := Node3D.new()
	var copies: Array[MeshInstance3D] = []
	var offsets := PackedFloat32Array()

	func advance(delta: float) -> void:
		if actor.is_playing() and actor.current_animation == CLIP:
			travel = fposmod(travel + delta * actor.get_playing_speed() * (2.0 * SPACING / actor.current_animation_length), PERIOD)
		for i in copies.size():
			copies[i].position.y = BOTTOM + fposmod(offsets[i] - travel - BOTTOM, PERIOD)

var streams: Array[Stream] = []
var saved_masks := {}
var materials := {}
var shader := Shader.new()


func mount(scene: Node) -> bool:
	var manager := scene.get_node_or_null("standalone managers/menu manager")
	if manager == null:
		return false
	var actors = manager.get("waterfalls")
	if not actors is Array or actors.size() != 2:
		return false
	shader.code = SHELL_SHADER
	for actor in actors:
		if not actor is AnimationPlayer or not actor.has_animation(CLIP):
			unmount()
			return false
		var bone: Node3D = actor.get_parent().get_node_or_null("shell waterfall parent/Bone")
		if bone == null or not (bone.has_node("segment1") and bone.has_node("segment2") and bone.has_node("segment3")):
			unmount()
			return false
		var stream := Stream.new()
		stream.actor = actor
		stream.travel = -bone.position.y
		streams.append(stream)
		bone.get_parent().add_child(stream.group)
		var batch := bone.get_children()
		var originals := batch.size()
		# Extend one complete set so even a rotated mesh's bounding box lies
		# outside the fade at both ends before reusing it.
		for j in range(1, 4):
			batch.append(bone.get_node("segment" + str(j)))
		for i in batch.size():
			var source := batch[i] as MeshInstance3D
			if source == null or source.mesh == null:
				unmount()
				return false
			var shell := MeshInstance3D.new()
			stream.group.add_child(shell)
			shell.mesh = source.mesh
			shell.transform = source.transform
			shell.layers = saved_masks.get(source, source.layers)
			for surface in source.mesh.get_surface_count():
				var original := source.get_active_material(surface) as StandardMaterial3D
				if original == null:
					unmount()
					return false
				shell.set_surface_override_material(surface, _fading_material(original))
			stream.copies.append(shell)
			stream.offsets.append(source.position.y if i < originals else source.position.y - 3.0 * SPACING)
			if not saved_masks.has(source):
				saved_masks[source] = source.layers
				source.layers = 0
		stream.advance(0.0)
	set_process(true)
	return true


func _fading_material(original: StandardMaterial3D) -> ShaderMaterial:
	if materials.has(original):
		return materials[original]
	var result := ShaderMaterial.new()
	result.shader = shader
	result.set_shader_parameter("skin", original.albedo_texture)
	result.set_shader_parameter("detail", original.normal_texture)
	result.set_shader_parameter("relief", original.normal_scale if original.normal_enabled else 0.0)
	result.set_shader_parameter("rough", original.roughness)
	result.set_shader_parameter("tint", original.albedo_color)
	result.set_shader_parameter("vertex_tint", original.vertex_color_use_as_albedo)
	materials[original] = result
	return result


func _process(delta: float) -> void:
	for stream in streams:
		if is_instance_valid(stream.actor) and is_instance_valid(stream.group):
			stream.advance(delta)


func unmount() -> void:
	set_process(false)
	for source in saved_masks:
		if is_instance_valid(source):
			source.layers = saved_masks[source]
	saved_masks.clear()
	for stream in streams:
		if is_instance_valid(stream.group):
			stream.group.hide()
			stream.group.queue_free()
	streams.clear()
	materials.clear()


func _exit_tree() -> void:
	unmount()
