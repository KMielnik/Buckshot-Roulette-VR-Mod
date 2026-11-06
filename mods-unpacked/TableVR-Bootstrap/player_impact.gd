extends MeshInstance3D

signal player_hit
signal revived
signal heartbeat(weight: float)

const MAIN := "res://scenes/main.tscn"
const FIRE := &"muzzle flash fire"
const REVIVE := &"revival brightness"
const FLASH_SECONDS := 0.08
const REVEAL_SECONDS := 1.0
const HIT_COLOR := Color(0.40, 0.09, 0.04, 0.42)
# Onsets and relative strength measured from the 2.2.0.6 revival sound.
# The retail speaker supplies the playback clock, including the fading tail.
const HEART_ONSETS := [0.20, 0.37, 0.55, 0.75, 0.97, 1.13, 1.31, 1.51, 1.73, 1.89, 2.08, 2.28,
	2.50, 2.66, 2.85, 3.05, 3.27, 3.44, 3.63, 3.84, 4.07, 4.24, 4.44, 4.66, 4.90]
const HEART_WEIGHTS := [.89, .75, .93, .80, .92, .74, .90, .79, 1., .74, .98, .78,
	.88, .75, .90, .68, .79, .58, .60, .34, .29, .16, .15, .07, .05]

# Godot 4.1 clip coordinates cover each eye independently, including asymmetric frusta.
const COVER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;
uniform vec4 tint : source_color;
void vertex() { POSITION = vec4(VERTEX.xy, 0.5, 1.0); }
void fragment() { ALBEDO = tint.rgb; ALPHA = tint.a; FOG = vec4(0.0); }
"""

var shooter: Node
var blocker: ColorRect
var muzzle: AnimationPlayer
var revival: AnimationPlayer
var defib_audio: AudioStreamPlayer2D
var heart_audio: AudioStreamPlayer2D
var next_thump := -1
var audio_latency := 0.0
var bathroom_reviver: Node3D
var head: XRCamera3D
var original_environment: Environment
var world_environment: Environment
var impact_environment: Environment
var normal_brightness := 1.0
var cover := ShaderMaterial.new()
var active := false
var flash_left := 0.0
var pending_hit := 0.0
var unconscious := false
var in_ending := false


func mount(scene: Node) -> bool:
	visible = false
	set_process(false)
	if scene.scene_file_path != MAIN:
		return false
	head = get_parent() as XRCamera3D
	shooter = scene.get_node_or_null("standalone managers/shotgun shooting")
	var death := scene.get_node_or_null("standalone managers/death manager")
	var intro := scene.get_node_or_null("standalone managers/intro manager")
	if head == null or shooter == null or death == null or intro == null or shooter.get("death") != death:
		return false
	blocker = death.get("viewblocker") as ColorRect
	muzzle = shooter.get("animator_muzzleFlash") as AnimationPlayer
	revival = death.get("animator_pp") as AnimationPlayer
	defib_audio = death.get("speaker_playerDefib") as AudioStreamPlayer2D
	heart_audio = death.get("speaker_heartbeat") as AudioStreamPlayer2D
	bathroom_reviver = intro.get("smokerdude_revival") as Node3D
	if blocker == null or defib_audio == null or bathroom_reviver == null or muzzle == null or not muzzle.has_animation(FIRE) or revival == null or not revival.has_animation(REVIVE):
		return false
	var clip := revival.get_animation(REVIVE)
	var track := clip.find_track(NodePath(".:environment:adjustment_brightness"), Animation.TYPE_VALUE)
	if track < 0 or clip.track_get_key_count(track) < 2:
		return false
	normal_brightness = clip.track_get_key_value(track, clip.track_get_key_count(track) - 1)
	original_environment = head.environment
	world_environment = original_environment if original_environment else head.get_world_3d().environment
	if world_environment == null:
		return false
	# A private camera environment avoids the retail 5.44 brightness peak on revival.
	# Set neutral contrast at full coverage; retail contrast lifts pure black to gray.
	impact_environment = world_environment.duplicate() as Environment
	var shader := Shader.new()
	shader.code = COVER_SHADER
	cover.shader = shader
	cover.render_priority = Material.RENDER_PRIORITY_MAX - 1 # The first-win unlock label appears above black.
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	quad.material = cover
	mesh = quad
	position.z = -1.0
	extra_cull_margin = 32.0
	ignore_occlusion_culling = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	muzzle.animation_started.connect(_muzzle_started)
	revival.animation_started.connect(_revival_started)
	blocker.visibility_changed.connect(_blocker_changed)
	set_process(true)
	return true


func _muzzle_started(clip: StringName) -> void:
	# Both shooters set whoshot before playing the live-only muzzle animation.
	if clip == FIRE and shooter.get("whoshot") == "player" and not blocker.visible:
		print("[TableVR] player hit")
		player_hit.emit()
		# The retail Kill routine raises the blocker 0.08 game-seconds after impact.
		# Discard a hit if another mod interrupts that routine before the blocker rises.
		pending_hit = 0.5
		flash_left = FLASH_SECONDS if active else 0.0
		_draw_effect()

func _revival_started(clip: StringName) -> void:
	if clip == REVIVE:
		print("[TableVR] player revival")
		revived.emit()
		if is_instance_valid(heart_audio) and heart_audio.stream != null and heart_audio.stream.resource_path == "res://audio/heartbeat effect2.ogg":
			next_thump = 0
			audio_latency = AudioServer.get_output_latency()



func _blocker_changed() -> void:
	_observe_blocker()
	_draw_effect()


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	if not active:
		flash_left = 0.0
	_blocker_changed()


func _process(delta: float) -> void:
	if next_thump >= 0:
		if not is_instance_valid(heart_audio) or not heart_audio.playing:
			next_thump = -1
		elif not heart_audio.stream_paused:
			var heard := heart_audio.get_playback_position() + (AudioServer.get_time_since_last_mix() - audio_latency) * heart_audio.pitch_scale
			_follow_heartbeat(heard)
	_observe_blocker()
	pending_hit = maxf(0.0, pending_hit - delta)
	if active:
		_draw_effect()
		flash_left = maxf(0.0, flash_left - delta)


func _follow_heartbeat(heard: float) -> void:
	# Consume missed beats silently on a hitch or inactive session.
	var crossed := -1
	while next_thump >= 0 and next_thump < HEART_ONSETS.size() and heard >= HEART_ONSETS[next_thump]:
		crossed = next_thump
		next_thump += 1
	if crossed >= 0 and active and heard - HEART_ONSETS[crossed] <= .065:
		heartbeat.emit(HEART_WEIGHTS[crossed])
	if next_thump == HEART_ONSETS.size():
		next_thump = -1


func _observe_blocker() -> void:
	if not is_instance_valid(blocker) or not blocker.visible:
		unconscious = false
	elif not unconscious and (pending_hit > 0.0 or defib_audio.playing or bathroom_reviver.visible):
		unconscious = true
		print("[TableVR] player blackout")
		pending_hit = 0.0


func _draw_effect() -> void:
	if not active or not is_instance_valid(blocker) or not is_instance_valid(revival) or impact_environment == null:
		visible = false
		_restore_environment()
		return
	var tint := Color.TRANSPARENT
	var reviving := revival.is_playing() and revival.current_animation == REVIVE
	if in_ending:
		tint = blocker.color if blocker.is_visible_in_tree() else Color.TRANSPARENT
	elif unconscious:
		# A single shared ColorRect also belongs to the intro and ending. Take
		# ownership only after a live hit or a confirmed retail defib sequence.
		tint = Color.BLACK
		flash_left = 0.0
	elif reviving:
		tint = Color(0, 0, 0, 1.0 - smoothstep(0.0, REVEAL_SECONDS, revival.current_animation_position))
	elif flash_left > 0.0:
		tint = HIT_COLOR
		tint.a *= flash_left / FLASH_SECONDS
	visible = tint.a > 0.0
	if visible:
		cover.set_shader_parameter("tint", tint)
	if visible or reviving:
		impact_environment.adjustment_brightness = world_environment.adjustment_brightness if in_ending else minf(world_environment.adjustment_brightness, normal_brightness)
		impact_environment.adjustment_contrast = lerpf(minf(world_environment.adjustment_contrast, 1.0), 1.0, tint.a)
		head.environment = impact_environment
	else:
		_restore_environment()


func _restore_environment() -> void:
	if is_instance_valid(head) and impact_environment != null and head.environment == impact_environment:
		head.environment = original_environment


func unmount() -> void:
	set_process(false)
	active = false
	visible = false
	flash_left = 0.0
	pending_hit = 0.0
	unconscious = false
	_restore_environment()
	if is_instance_valid(muzzle) and muzzle.animation_started.is_connected(_muzzle_started):
		muzzle.animation_started.disconnect(_muzzle_started)
	if is_instance_valid(revival) and revival.animation_started.is_connected(_revival_started):
		revival.animation_started.disconnect(_revival_started)
	if is_instance_valid(blocker) and blocker.visibility_changed.is_connected(_blocker_changed):
		blocker.visibility_changed.disconnect(_blocker_changed)
	blocker = null
	muzzle = null
	revival = null
	defib_audio = null
	heart_audio = null
	next_thump = -1
	bathroom_reviver = null
	shooter = null
	head = null
	impact_environment = null
	world_environment = null
	original_environment = null


func _exit_tree() -> void:
	unmount()
