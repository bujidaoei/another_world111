class_name AWGameAudio
extends Node
## Original sample library, shared named buses, bounded voices, synchronized stems.

signal diagnostic(event: Dictionary)

const MAX_VOICES: int = 8
const VOICE_GAIN_DB: float = -14.0
const FADE_SECONDS: float = 0.9
const Settings = preload("res://persistence/game_settings.gd")
const EVENTS: Dictionary = {
	"electric": [preload("res://assets/audio/electric_1.wav"), preload("res://assets/audio/electric_2.wav")],
	"impact": [preload("res://assets/audio/impact_1.wav"), preload("res://assets/audio/impact_2.wav")],
	"dodge": [preload("res://assets/audio/dodge.wav")],
	"collect": [preload("res://assets/audio/collect.wav")],
	"confirm": [preload("res://assets/audio/confirm.wav")],
	"hurt": [preload("res://assets/audio/hurt.wav")],
	"pulse": [preload("res://assets/audio/pulse.wav")],
	"anchor": [preload("res://assets/audio/anchor.wav")],
	"failure": [preload("res://assets/audio/failure.wav")],
	"victory": [preload("res://assets/audio/victory.wav")],
}
const PRIORITY: Dictionary = {"electric": 1, "impact": 1, "dodge": 2, "collect": 2, "confirm": 2, "hurt": 3, "pulse": 3, "anchor": 2, "failure": 4, "victory": 4}
const RAIN_STREAM: AudioStreamWAV = preload("res://assets/audio/rain_loop.wav")
const MUSIC_BASE: AudioStreamWAV = preload("res://assets/audio/music_base.wav")
const MUSIC_COMBAT: AudioStreamWAV = preload("res://assets/audio/music_combat.wav")

var _voices: Array[AudioStreamPlayer] = []
var _voice_start: Array[int] = []
var _voice_priority: Array[int] = []
var _rain: AudioStreamPlayer
var _music: AudioStreamPlayer
var _music_stream: AudioStreamSynchronized
var _layer_tween: Tween
var _combat_layer_db: float = -80.0
var _encounter_active: bool = false
var _initialized: bool = false
var _stopped: bool = false
var _settings: Dictionary = Settings.default_settings()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_initialize_audio()
	configure(_settings)


func configure(settings: Dictionary) -> Dictionary:
	var validation := Settings.normalize(settings)
	if not validation.ok:
		return validation
	_initialize_audio()
	_settings = validation.data
	_set_bus_gain("Master", float(_settings.master_volume))
	_set_bus_gain("Music", float(_settings.music_volume))
	_set_bus_gain("SFX", float(_settings.sfx_volume))
	_set_bus_gain("Ambience", float(_settings.ambience_volume))
	_set_bus_gain("UI", float(_settings.sfx_volume))
	return {"ok": true, "code": "audio_configured", "message": "音频设置已应用。"}


func start_environment() -> Dictionary:
	if not is_inside_tree():
		return _failure("audio_not_ready", "音频节点尚未进入场景。")
	_initialize_audio()
	if _stopped:
		_bind_environment_streams()
		_stopped = false
	if not _rain.playing:
		_rain.play()
	if not _music.playing:
		_music.play()
	set_encounter(_encounter_active)
	return {"ok": true, "code": "environment_started", "message": "雨声和音乐已开始播放。"}


func set_encounter(active: bool) -> void:
	_encounter_active = active
	_initialize_audio()
	if _stopped:
		return
	var target_db: float = -12.0 if active else -80.0
	if not is_inside_tree():
		_set_combat_layer_db(target_db)
		return
	if _layer_tween != null and _layer_tween.is_valid():
		_layer_tween.kill()
	_layer_tween = create_tween()
	_layer_tween.tween_method(_set_combat_layer_db, _combat_layer_db, target_db, FADE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func play_event(event_name: String) -> Dictionary:
	if not EVENTS.has(event_name):
		return _failure("audio_event_unknown", "音频事件不存在。")
	if not is_inside_tree():
		return _failure("audio_not_ready", "音频节点尚未进入场景。")
	_initialize_audio()
	if _stopped:
		return _failure("audio_stopped", "音频正在停止，未启动新的音效。")
	var priority: int = PRIORITY[event_name]
	var voice_index: int = _available_voice(priority)
	if voice_index < 0:
		return _failure("audio_voice_limit", "音效并发已满，保留更重要的声音。")
	var player := _voices[voice_index]
	player.stop()
	var variants: Array = EVENTS[event_name]
	player.stream = variants[_rng.randi_range(0, variants.size() - 1)]
	player.bus = "UI" if event_name == "confirm" else "SFX"
	player.pitch_scale = 1.0 if event_name in ["failure", "victory", "confirm", "collect"] else _rng.randf_range(0.97, 1.03)
	player.volume_db = VOICE_GAIN_DB - _rng.randf_range(0.0, 1.5)
	_voice_priority[voice_index] = priority
	_voice_start[voice_index] = Time.get_ticks_usec()
	player.play()
	diagnostic.emit({"component": "audio", "operation": "play_event", "event": event_name, "voice": voice_index, "priority": priority})
	return {"ok": true, "code": "audio_event_started", "message": "音效已开始播放。"}


func _initialize_audio() -> void:
	if _initialized:
		return
	for bus_name: String in ["Music", "SFX", "Ambience", "UI"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
	var master := AudioServer.get_bus_index("Master")
	var limiter_exists := false
	for index in range(AudioServer.get_bus_effect_count(master)):
		var effect := AudioServer.get_bus_effect(master, index)
		if effect is AudioEffectHardLimiter:
			limiter_exists = true
	if not limiter_exists:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -1.0
		limiter.release = 0.15
		AudioServer.add_bus_effect(master, limiter)
	_rain = _make_player("RainEnvironment", "Ambience", -9.0)
	_music = _make_player("SynchronizedMusic", "Music", 0.0)
	_bind_environment_streams()
	for index in range(MAX_VOICES):
		_voices.append(_make_player("EventVoice%d" % index, "SFX", VOICE_GAIN_DB))
		_voice_start.append(0)
		_voice_priority.append(0)
	_initialized = true


func _bind_environment_streams() -> void:
	_rain.stream = _loop_stream(RAIN_STREAM)
	_music_stream = AudioStreamSynchronized.new()
	_music_stream.stream_count = 2
	_music_stream.set_sync_stream(0, _loop_stream(MUSIC_BASE))
	_music_stream.set_sync_stream(1, _loop_stream(MUSIC_COMBAT))
	_music_stream.set_sync_stream_volume(0, -10.0)
	_music_stream.set_sync_stream_volume(1, _combat_layer_db)
	_music.stream = _music_stream


func _make_player(player_name: String, bus_name: String, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = bus_name
	player.volume_db = volume_db
	player.max_polyphony = 1
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	return player


func _loop_stream(source: AudioStreamWAV) -> AudioStreamWAV:
	var stream: AudioStreamWAV = source.duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
	return stream


func _available_voice(incoming_priority: int) -> int:
	var candidate: int = 0
	for index in range(_voices.size()):
		if not _voices[index].playing:
			return index
		if _voice_priority[index] < _voice_priority[candidate] or (_voice_priority[index] == _voice_priority[candidate] and _voice_start[index] < _voice_start[candidate]):
			candidate = index
	return candidate if _voice_priority[candidate] <= incoming_priority else -1


func _set_combat_layer_db(value: float) -> void:
	_combat_layer_db = value
	_music_stream.set_sync_stream_volume(1, value)


func _set_bus_gain(bus_name: String, linear_volume: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(index, linear_volume <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear_volume, 0.0001)))


func stop_all() -> void:
	_stopped = true
	if _layer_tween != null and _layer_tween.is_valid():
		_layer_tween.kill()
	_layer_tween = null
	for player: AudioStreamPlayer in _voices:
		player.stop()
		player.stream = null
	if _rain != null:
		_rain.stop()
		_rain.stream = null
	if _music != null:
		_music.stop()
		_music.stream = null
	_music_stream = null


func _exit_tree() -> void:
	stop_all()


func _failure(code: String, message: String) -> Dictionary:
	diagnostic.emit({"component": "audio", "operation": "error", "code": code})
	return {"ok": false, "code": code, "message": message}
