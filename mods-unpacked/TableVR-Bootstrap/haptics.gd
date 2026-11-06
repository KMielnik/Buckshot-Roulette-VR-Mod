extends Node

signal pulse_requested(tracker: StringName, kind: StringName, amplitude: float, seconds: float)

# Amplitude and seconds. Zero frequency lets the active runtime use the motor's
# resonant frequency. Impacts take precedence over incidental hover feedback.
const PROFILES := {
	&"hover": Vector2(.14, .020), &"key": Vector2(.28, .027),
	&"item": Vector2(.38, .052), &"metal": Vector2(.49, .054),
	&"place": Vector2(.25, .042), &"paper": Vector2(.19, .043),
	&"kick": Vector2(.55, .070), &"hit": Vector2(.86, .085),
	&"revival": Vector2(.44, .105), &"cuffs": Vector2(.48, .042),
}

var left: XRController3D
var right: XRController3D
var active := false
var strength := 1.0
var busy_until := {}
var playing_level := {}
var reported := {}


func mount(rig: XROrigin3D) -> void:
	left = rig.get_node("LeftGlove")
	right = rig.get_node("RightGlove")
	var setting = ProjectSettings.get_setting("buckshot_vr/haptic_strength", 1.0)
	if (setting is float or setting is int) and is_finite(float(setting)):
		strength = clampf(float(setting), 0.0, 1.0)


func set_active(value: bool) -> void:
	if active and not value:
		busy_until.clear()
		playing_level.clear()
	active = value


func cue(kind: StringName) -> void:
	if not active or strength <= 0 or not PROFILES.has(kind):
		return
	var bilateral := kind in [&"kick", &"hit", &"revival", &"cuffs"]
	var level := 3 if bilateral else (1 if kind == &"hover" else 2)
	var profile: Vector2 = PROFILES[kind]
	_play(right, kind, level, profile)
	if bilateral:
		_play(left, kind, level, profile)


func _play(hand: XRController3D, kind: StringName, level: int, profile: Vector2) -> void:
	if not is_instance_valid(hand) or not hand.get_has_tracking_data():
		return
	var now := Time.get_ticks_msec()
	var tracker := hand.tracker
	if now < int(busy_until.get(tracker, 0)) and level <= int(playing_level.get(tracker, 0)):
		return
	var hold_ms := 100 if kind == &"hover" else ceili(profile.y * 1000.0)
	busy_until[tracker] = now + hold_ms
	playing_level[tracker] = level
	hand.trigger_haptic_pulse("haptic", 0.0, profile.x * strength, profile.y, 0.0)
	pulse_requested.emit(tracker, kind, profile.x * strength, profile.y)
	if not reported.has(tracker):
		reported[tracker] = true
		print("[TableVR] first haptic request ", tracker, " ", kind)


func heartbeat(weight: float) -> void:
	if active and strength > 0:
		var pulse := Vector2(.68 * weight, .055)
		_play(left, &"heartbeat", 2, pulse)
		_play(right, &"heartbeat", 2, pulse)


func world_press(alias: String, item: String, grid: bool) -> void:
	cue(_world_kind(alias, item, grid))


func near_press(side: int, alias: String, item: String, grid: bool) -> void:
	if active and strength > 0:
		var kind := _world_kind(alias, item, grid)
		_play(left if side == 0 else right, kind, 2, PROFILES[kind])


func _world_kind(alias: String, item: String, grid: bool) -> StringName:
	if grid:
		return &"place"
	elif alias in ["shotgun", "latch left", "latch right", "briefcase lid"] or item in ["handsaw", "handcuffs", "inverter"]:
		return &"metal"
	elif alias in ["item", "briefcase intake", "pill bottle"]:
		return &"item"
	elif alias == "release form on table":
		return &"paper"
	return &"key"
