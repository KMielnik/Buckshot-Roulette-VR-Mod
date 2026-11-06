extends Node

var heard: Array[float] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	while not get_tree().current_scene or get_tree().current_scene.scene_file_path != "res://scenes/main.tscn":
		await get_tree().process_frame
	var mod := get_node("/root/ModLoader/TableVR-Bootstrap")
	mod._process(0.0)
	var fx = mod.player_impact
	fx.set_active(true)
	fx.heartbeat.connect(func(_weight): heard.append(fx.heart_audio.get_playback_position() + AudioServer.get_time_since_last_mix() - fx.audio_latency))
	fx.shooter.roundManager.health_player = 2
	fx.shooter.death.MedicineDeath()
	var until := Time.get_ticks_msec() + 9000
	while Time.get_ticks_msec() < until and heard.size() < fx.HEART_ONSETS.size():
		await get_tree().process_frame
	var ok: bool = heard.size() == fx.HEART_ONSETS.size()
	var max_offset := 0.0
	for i in heard.size():
		max_offset = maxf(max_offset, absf(heard[i] - fx.HEART_ONSETS[i]))
	ok = ok and max_offset < .065
	print("HEART_QA ", "PASS" if ok else "FAIL", " actual mixer onsets=", heard.size(), " maximum offset seconds=", max_offset)
	print("HEART_QA failures=", 0 if ok else 1)
	get_tree().quit(0 if ok else 1)
