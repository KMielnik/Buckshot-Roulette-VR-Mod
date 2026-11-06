extends RefCounted

var environment: Environment
var ramp: GradientTexture1D


func mount(camera: Camera3D) -> bool:
	var card := camera.get_node_or_null("post processing/posterization test/BackBufferCopy/ColorRect") as ColorRect
	if card == null or not card.is_visible_in_tree() or not card.material is ShaderMaterial:
		return false
	var material := card.material as ShaderMaterial
	var steps := int(material.get_shader_parameter("RED_COMPONENT"))
	if steps < 2 or steps > 32 or material.get_shader_parameter("GREEN_COMPONENT") != float(steps) or material.get_shader_parameter("BLUE_COMPONENT") != float(steps):
		return false
	var env := camera.environment if camera.environment != null else camera.get_world_3d().environment
	if env == null or not env.adjustment_enabled or env.adjustment_color_correction != null:
		return false
	# Godot applies the 1D color correction independently to RGB, after the
	# filmic tonemap and the game's animated brightness/contrast/saturation.
	var curve := Gradient.new()
	curve.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	for i in range(1, steps):
		var value := float(i) / steps
		curve.add_point(value, Color(value, value, value))
	ramp = GradientTexture1D.new()
	ramp.width = 2048
	ramp.gradient = curve
	environment = env
	environment.adjustment_color_correction = ramp
	return true


func unmount() -> void:
	if is_instance_valid(environment) and environment.adjustment_color_correction == ramp:
		environment.adjustment_color_correction = null
	environment = null
	ramp = null
