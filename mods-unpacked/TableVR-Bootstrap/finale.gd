extends Node3D

const HUD_LAYER := 1 << 17
const UNLOCK_LAYER := 1 << 18
const PAN := &"pan to brief"
# From corresponding latch centres in Steam 2.2.0.6: 0.562 vs 4.209 units.
const CAR_UNITS_RATIO := 0.1335
var ending: Node
var brief: Node
var desk_camera: Camera3D
var active := false
var opened_lid := false
var panel: MeshInstance3D
var surface: SubViewport
var old_layers := {}
var entry := Transform3D.IDENTITY
var blend := 0.0
var continue_armed := false

func mount(camera: Camera3D, interaction: Node) -> bool:
	desk_camera = camera
	brief = interaction.get("brief")
	if brief == null: return false
	ending = brief.get("ending")
	if ending == null or ending.cam.cam != camera or not ending.animator_pan.has_animation(PAN):
		return false
	if ending.uiparent == null or ending.unlocker.ui == null or not ending.animator_cam.has_animation("camera loop car"):
		return false
	ending.animator_pan.animation_started.connect(_started)
	if ending.animator_pan.current_animation == PAN or ending.animator_cam.current_animation == "camera loop car":
		_started(PAN)
	return true

func open_if_ready(allowed: bool) -> void:
	if allowed and not opened_lid and not active and brief.latchRaisedL and brief.latchRaisedR and brief.intbranch_lid.interactionAllowed and not brief.intbranch_lid.interactionInvalid:
		opened_lid = true
		brief.OpenLid()

func _started(clip: StringName) -> void:
	if active or clip != PAN: return
	active = true
	var head := get_parent().get_node("Head") as Camera3D
	entry = head.global_transform.orthonormalized()
	# The rig will retain live pitch/roll. The initial base only needs the
	# current heading; carrying headset pitch into it would apply pitch twice.
	var backwards := entry.basis.z
	entry.basis = Basis(Vector3.UP, atan2(backwards.x, backwards.z))
	_make_score_panel()
	print("[TableVR] ending camera handover")

func camera_frame(delta: float) -> Transform3D:
	blend = minf(1.0, blend + delta / .35)
	var frame := desk_camera.global_transform.orthonormalized()
	return entry.interpolate_with(frame, smoothstep(0.0, 1.0, blend)) if blend < 1.0 else frame

func in_car() -> bool:
	return active and ending.animator_cam.current_animation == "camera loop car"

func present(allowed: bool, hand: XRController3D) -> void:
	if not active: return
	panel.visible = allowed and in_car()
	surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS if panel.visible else SubViewport.UPDATE_DISABLED
	if panel.visible:
		# The first-time unlock label is drawn over the game's black exit fade.
		var unlocking: bool = not ending.isActive and ending.unlocker.dia.dialogueUI == ending.unlocker.ui
		var layer := UNLOCK_LAYER if unlocking else HUD_LAYER
		if surface.canvas_cull_mask != layer:
			surface.canvas_cull_mask = layer
			panel.mesh.material.render_priority = Material.RENDER_PRIORITY_MAX if unlocking else 4
		var frame := desk_camera.global_transform.orthonormalized()
		var units := XRServer.world_scale
		panel.global_transform = Transform3D(frame.basis.scaled(Vector3.ONE * units),
			frame * (Vector3(0, 0, -1.45) * units))
	var aim := hand.get_node_or_null("../Right") as XRController3D
	var tracked := hand.get_has_tracking_data() or (aim != null and aim.get_has_tracking_data())
	if not allowed or not ending.waitingForInput or not tracked:
		continue_armed = false
	elif not hand.is_button_pressed(&"trigger_click"):
		continue_armed = true
	elif continue_armed:
		continue_armed = false
		ending.waitingForInput = false
		ending.ExitGame()

func _make_score_panel() -> void:
	surface = SubViewport.new()
	surface.size = Vector2i(960, 540)
	surface.disable_3d = true
	surface.transparent_bg = true
	surface.gui_disable_input = true
	surface.world_2d = desk_camera.get_viewport().world_2d
	surface.canvas_cull_mask = HUD_LAYER
	surface.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(surface)
	for source in [ending.uiparent, ending.animator_anykey.get_parent(), ending.unlocker.ui]:
		var items = source.find_children("*", "CanvasItem", true, false)
		items.append(source)
		for item in items:
			if not old_layers.has(item):
				old_layers[item] = item.visibility_layer
				item.visibility_layer |= UNLOCK_LAYER if source == ending.unlocker.ui else HUD_LAYER
	# The bright moving car can wash out the original pale lettering. Outline
	# the actual rendered glyphs so transparent parts still show the car.
	var shader := Shader.new()
	shader.code = """
	shader_type spatial;
	render_mode unshaded, depth_test_disabled, cull_disabled;
	uniform sampler2D score : source_color, filter_linear, repeat_disable;
	void fragment() {
		vec4 glyph = texture(score, UV);
		vec2 pixel = 2.0 / vec2(textureSize(score, 0));
		float edge = 0.0;
		for (int x = -1; x <= 1; x++) {
			for (int y = -1; y <= 1; y++) {
				edge = max(edge, texture(score, UV + pixel * vec2(float(x), float(y))).a);
			}
		}
		ALPHA = max(glyph.a, edge * 0.94);
		ALBEDO = glyph.rgb * glyph.a / max(ALPHA, 0.001);
	}
	"""
	var ink := ShaderMaterial.new()
	ink.shader = shader
	ink.render_priority = 4
	ink.set_shader_parameter("score", surface.get_texture())
	var quad := QuadMesh.new()
	quad.size = Vector2(1.85, 1.85 * 540.0 / 960.0)
	quad.material = ink
	panel = MeshInstance3D.new()
	panel.mesh = quad
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	panel.top_level = true
	panel.hide()
	add_child(panel)

func unmount() -> void:
	if is_instance_valid(ending) and is_instance_valid(ending.animator_pan) and ending.animator_pan.animation_started.is_connected(_started):
		ending.animator_pan.animation_started.disconnect(_started)
	for item in old_layers:
		if is_instance_valid(item): item.visibility_layer = old_layers[item]
	old_layers.clear()
