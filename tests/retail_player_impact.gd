# Runs inside a disposable copy with a separate save profile and OpenXR disabled.
extends Node

const MAIN := "res://scenes/main.tscn"
var failures := 0
var entered_death := false


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("PLAYER_QA ", "PASS " if ok else "FAIL ", label)


func _run() -> void:
	get_tree().node_added.connect(_watch_transition)
	get_tree().change_scene_to_file(MAIN)
	while not get_tree().current_scene or get_tree().current_scene.scene_file_path != MAIN:
		await get_tree().process_frame
	var scene := get_tree().current_scene
	var mod := get_node("/root/ModLoader/TableVR-Bootstrap")
	mod._process(0.0)
	var effect = mod.player_impact
	var thumps: Array[float] = []
	effect.heartbeat.connect(func(weight: float): thumps.append(weight))
	_check(is_instance_valid(effect), "integrated mod binds retail player, defib animator and authored blocker")
	if not is_instance_valid(effect):
		print("PLAYER_QA failures=", failures + 1)
		get_tree().quit(1)
		return
	var head: XRCamera3D = mod.rig.get_node("Head")
	_check(effect.get_parent() == head, "effect mounted to real rig Head")
	effect.set_active(true)
	_check(effect.blocker.visible and not effect.visible and head.environment == null, "initial bathroom blocker excluded")
	while effect.blocker.visible:
		await get_tree().process_frame
	var shooter: Node = effect.shooter
	var death: Node = shooter.death
	var round_manager: Node = shooter.roundManager
	round_manager.health_player = 3
	round_manager.health_opponent = 3
	shooter.whoshot = "player"
	shooter.shellSpawner.sequenceArray.assign(["blank"])
	shooter.PlayShootingSound()
	_check(effect.pending_hit == 0 and not effect.visible, "blank pointed at player produces no flash")
	shooter.whoshot = "dealer"
	shooter.shellSpawner.sequenceArray.assign(["live", "blank", "live"])
	shooter.PlayShootingSound()
	_check(effect.pending_hit == 0 and not effect.visible, "live hit directed at dealer excluded")
	var shots_before: int = round_manager.playerData.stat_shotsFired
	death.dealerAI.Shoot("player")
	while round_manager.playerData.stat_shotsFired == shots_before:
		await get_tree().process_frame
	_check(effect.flash_left > 0 and effect.visible and round_manager.health_player == 2, "actual dealer hit produces brief tint once and retail damage")
	effect.set_active(false)
	_check(not effect.visible and head.environment == null, "loss of focus clears tint and restores environment")
	while not effect.blocker.visible:
		await get_tree().process_frame
	effect.set_active(true)
	_check(effect.unconscious and effect.visible and effect.cover.get_shader_parameter("tint") == Color.BLACK, "resuming a real knockout holds full black")
	var held := true
	var saw_defib := false
	while effect.blocker.visible:
		held = held and effect.visible and effect.cover.get_shader_parameter("tint") == Color.BLACK
		saw_defib = saw_defib or effect.defib_audio.playing
		await get_tree().process_frame
	_check(held and saw_defib and effect.revival.current_animation == effect.REVIVE and death.defibParent.visible, "holds through defib sound until authored reveal")
	_check(effect.heart_audio == death.speaker_heartbeat and effect.heart_audio.playing and effect.next_thump >= 0, "revival arms the actual 2.2.0.6 heartbeat speaker")
	for beat in effect.HEART_ONSETS:
		effect._follow_heartbeat(beat + .001)
	var hits := thumps.size()
	_check(hits == 25 and thumps[0] > thumps[1] and thumps[-1] < .1, "both lobes are timed independently and fade with recording")
	effect._follow_heartbeat(5.2)
	_check(thumps.size() == hits, "end of heartbeat cannot replay")
	while effect.revival.current_animation_position < 0.35:
		await get_tree().process_frame
	var tint: Color = effect.cover.get_shader_parameter("tint")
	_check(tint.a > 0 and tint.a < 1 and head.environment == effect.impact_environment, "reveals progressively using the revival playhead")
	var limit: float = effect.normal_brightness
	_check(effect.impact_environment.adjustment_brightness <= limit + 0.001 and effect.world_environment.adjustment_brightness > limit, "XR brightness cap leaves retail lighting animation running")
	while effect.revival.is_playing() and effect.revival.current_animation == effect.REVIVE:
		await get_tree().process_frame
	await get_tree().process_frame
	_check(not effect.visible and head.environment == null and effect.flash_left == 0, "revival completes without replaying flash")

	# A permanently fatal hit in endless mode takes the short death-scene branch
	# without writing the story save or awarding the million-score achievement.
	round_manager.endless = true
	round_manager.health_player = 1
	shooter.shellSpawner.sequenceArray.assign(["live", "blank", "live"])
	effect.set_active(false)
	shooter.Shoot("self")
	while not effect.blocker.visible:
		await get_tree().process_frame
	effect.set_active(true)
	_check(round_manager.health_player == 0 and effect.visible and effect.unconscious and effect.flash_left == 0, "fatal self-shot while unfocused resumes black without replay")
	var held_to_exit := true
	while is_instance_valid(scene) and scene.is_inside_tree():
		held_to_exit = held_to_exit and effect.visible and effect.unconscious
		await get_tree().process_frame
	while not get_tree().current_scene:
		await get_tree().process_frame
	_check(held_to_exit and not is_instance_valid(effect) and mod.player_impact == null and entered_death, "permanent knockout passes through original death scene and no stale cover")
	print("PLAYER_QA failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)


func _watch_transition(node: Node) -> void:
	if node.scene_file_path == "res://scenes/death.tscn":
		entered_death = true
