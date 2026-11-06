extends Node

# Observe presentation events already accepted by the game. Never predict a
# shell or modify the native animations, health, inventory or permissions.
signal feedback(kind: StringName)

const SOUNDS := {
	"player use.ogg": &"drink", "player use cigarettes1.ogg": &"lighter",
	"player use handsaw1.ogg": &"saw", "player use magnifier1.ogg": &"inspect",
	"player use inverter.ogg": &"invert", "player use medicine.ogg": &"pills",
	"player use adrenaline.ogg": &"inject", "player use burner phone.ogg": &"phone",
	"player break handcuffs.ogg": &"release", "player check handcuffs.ogg": &"cuffs",
	"rack shotgun.ogg": &"rack", "rack shotgun_back.ogg": &"rack",
	"rack shotgun_forward.ogg": &"rack", "load single shell.ogg": &"load",
}

var shooter: Node
var muzzle: AnimationPlayer
var eject: AnimationPlayer
var speakers: Array[Node] = []
var clocks := {}
var enabled := false

func mount(scene: Node) -> bool:
	shooter = scene.get_node_or_null("standalone managers/shotgun shooting")
	if shooter == null: return false
	muzzle = shooter.get("animator_muzzleFlash")
	eject = shooter.ejectionManager_player.animator
	if muzzle == null or eject == null: return false
	muzzle.animation_started.connect(_shot)
	eject.animation_started.connect(_eject)
	var items := scene.get_node_or_null("standalone managers/item interaction")
	for source in scene.find_children("*", "AudioStreamPlayer2D", true, false):
		if source == shooter.speaker_blank or (items != null and source == items.speaker_interaction) or (source.stream != null and SOUNDS.has(source.stream.resource_path.get_file())):
			speakers.append(source)
	return true

func update(allowed: bool) -> void:
	# Keep observing while inactive, consuming events instead of replaying them
	# when focus returns. A restart of the same stream is also a new event.
	var was_enabled := enabled
	enabled = allowed
	for source in speakers:
		if not is_instance_valid(source): continue
		var previous: Dictionary = clocks.get(source, {})
		var audible: bool = source.playing and not source.stream_paused
		var clock: float = source.get_playback_position() if audible else -1.0
		var path: String = source.stream.resource_path if source.stream != null else ""
		var started: bool = audible and (previous.is_empty() or previous.clock < 0 or previous.path != path or clock + .025 < previous.clock)
		clocks[source] = {"clock": clock, "path": path}
		if allowed and was_enabled and started and clock < .12:
			if source == shooter.speaker_blank:
				if _player_firing(): feedback.emit(&"dry_fire")
			elif SOUNDS.has(path.get_file()):
				feedback.emit(SOUNDS[path.get_file()])

func _player_firing() -> bool:
	# The dealer-target pose ends at 2.205s; the actual shot happens later.
	# assigned_animation retains that pose after current_animation becomes empty.
	var clip: String = shooter.animator_shotgun.assigned_animation
	return clip in ["player shoot dealer", "player shoot self"]

func _shot(clip: StringName) -> void:
	# A player hit has its own bilateral impact, including a self-inflicted shot.
	if enabled and clip == &"muzzle flash fire" and shooter.whoshot != "player" and _player_firing():
		feedback.emit(&"shot")

func _eject(clip: StringName) -> void:
	if enabled and clip == &"ejecting shell_player1": feedback.emit(&"eject")

func unmount() -> void:
	if is_instance_valid(muzzle) and muzzle.animation_started.is_connected(_shot): muzzle.animation_started.disconnect(_shot)
	if is_instance_valid(eject) and eject.animation_started.is_connected(_eject): eject.animation_started.disconnect(_eject)
	speakers.clear()
	clocks.clear()
	enabled = false
