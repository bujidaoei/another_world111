extends SceneTree
## Independent real Godot mixer probe; copied into an isolated local project.

var _passed: int = 0
var _failed: int = 0
var _issues: Array[String] = []


func _initialize() -> void:
	await process_frame
	var audio_script: Script = load("res://presentation/game_audio.gd")
	var audio: Node = audio_script.new()
	root.add_child(audio)
	var bus_count := AudioServer.bus_count
	var master_index := AudioServer.get_bus_index("Master")
	var effect_count := AudioServer.get_bus_effect_count(master_index)
	_check(audio.get_child_count() == 10, "two environment players plus eight event voices")
	_check(audio.configure({}).ok, "default configuration")
	_check(audio.configure({}).ok and AudioServer.bus_count == bus_count and AudioServer.get_bus_effect_count(master_index) == effect_count, "reconfiguration reuses buses/effects")
	_check(not audio.configure({"master_volume": 1.1}).ok, "invalid settings rejected")
	for bus: String in ["Master", "Music", "SFX", "Ambience", "UI"]:
		_check(AudioServer.get_bus_index(bus) >= 0, "named bus " + bus)
	_check(audio.configure({"master_volume": 0.0, "music_volume": 0.0, "sfx_volume": 0.0, "ambience_volume": 0.0}).ok, "zero-volume configuration")
	for bus: String in ["Master", "Music", "SFX", "Ambience", "UI"]:
		_check(AudioServer.is_bus_mute(AudioServer.get_bus_index(bus)), "zero mutes " + bus)
	_check(audio.configure({"master_volume": 1.0, "music_volume": 1.0, "sfx_volume": 1.0, "ambience_volume": 1.0}).ok, "all-volume-max configuration")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(master_index, capture)
	_check(audio.start_environment().ok, "environment start")
	var rain: AudioStreamPlayer = audio.get_node("RainEnvironment")
	var music: AudioStreamPlayer = audio.get_node("SynchronizedMusic")
	_check(rain.playing and music.playing, "real loop players active")
	var music_stream := music.stream as AudioStreamSynchronized
	_check(music_stream != null and music_stream.stream_count == 2, "synchronized music has two stems")
	_check((rain.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "rain looping enabled")
	for index in range(2):
		_check((music_stream.get_sync_stream(index) as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "music stem looping " + str(index))
	audio.set_encounter(true)
	await create_timer(1.05).timeout
	_check(absf(music_stream.get_sync_stream_volume(1) + 12.0) < 0.01, "combat stem fades to target")
	for event_name: String in ["electric", "impact", "dodge", "collect", "confirm", "hurt", "pulse", "anchor", "failure", "victory"]:
		_check(audio.play_event(event_name).ok, "event playback " + event_name)
	_check(not audio.play_event("missing_event").ok, "unknown event rejected")
	for index in range(8):
		var voice: AudioStreamPlayer = audio.get_node("EventVoice%d" % index)
		voice.stop()
	for index in range(8):
		_check(audio.play_event("failure").ok, "fill bounded voice " + str(index))
	_check(audio.play_event("electric").code == "audio_voice_limit", "lower priority event cannot steal eight stingers")
	_check(audio.play_event("victory").ok, "important event replaces oldest equal priority voice")
	_check(audio.get_child_count() == 10, "voice count remains bounded under saturation")
	capture.clear_buffer()
	await create_timer(1.85).timeout
	var captured := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	var square_sum := 0.0
	for frame: Vector2 in captured:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		square_sum += frame.x * frame.x + frame.y * frame.y
	var rms := sqrt(square_sum / maxf(1.0, 2.0 * captured.size()))
	_check(captured.size() > 0 and peak > 0.0001, "actual Godot mixer produced nonzero audio frames")
	_check(peak <= db_to_linear(-1.0) + 0.0001, "post-limiter mixed peak respects ceiling")
	rain.seek(11.9)
	music.seek(23.9)
	await create_timer(0.4).timeout
	_check(rain.playing and rain.get_playback_position() < 2.0, "rain wraps at real loop end")
	_check(music.playing and music.get_playback_position() < 2.0, "synchronized stems wrap at real loop end")
	audio.set_encounter(false)
	await create_timer(1.05).timeout
	_check(absf(music_stream.get_sync_stream_volume(1) + 80.0) < 0.01, "combat stem fades out")
	audio.stop_all()
	audio.stop_all()
	_check(not rain.playing and not music.playing and rain.stream == null and music.stream == null, "repeated stop releases environment streams")
	var voices_cleared := true
	for index in range(8):
		var voice: AudioStreamPlayer = audio.get_node("EventVoice%d" % index)
		voices_cleared = voices_cleared and not voice.playing and voice.stream == null
	_check(voices_cleared, "stop releases all fixed voice streams")
	_check(audio.play_event("electric").code == "audio_stopped", "stop prevents new events during shutdown")
	_check(audio.start_environment().ok and rain.playing and music.playing and audio.get_child_count() == 10, "explicit environment restart safely rebinds existing players")
	audio.stop_all()
	await create_timer(0.2).timeout
	AudioServer.remove_bus_effect(master_index, effect_count)
	audio.queue_free()
	await process_frame
	# AudioServer retires stopped playbacks on its next mixer cycle.
	await create_timer(0.2).timeout
	var report := {"passed": _passed, "failed": _failed, "issues": _issues, "captured_frames": captured.size(), "mixed_peak": peak, "mixed_rms": rms, "display_server": DisplayServer.get_name(), "audio_driver": "Dummy (technical mixer probe)", "subjective_listening": "not performed"}
	print(JSON.stringify(report))
	var file := FileAccess.open("res://audio-probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	quit(0 if _failed == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		_issues.append(label)
