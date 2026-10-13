class_name AWPerformanceMeasure
extends SceneTree
## External QA main loop. Production gameplay is driven only by audited InputEvents.

var _config: Dictionary
var _session: Node
var _driver: Node
var _boot_us := 0
var _sample_start_us := 0
var _last_frame_us := 0
var _ending := false
var _frames := PackedFloat64Array()
var _metrics: Dictionary = {}
var _stage_frames: Dictionary = {}
var _viewport: RID
var _metadata: Dictionary = {}
var _coverage_events: Array[Dictionary] = []
var _last_result_count := 0
var _last_report_us := 0
var _first_engine_frame := 0
var _last_peak_monitor_us := 0

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		_abort("Expected a single external performance configuration path.")
		return
	var candidate: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not candidate is Dictionary:
		_abort("Performance configuration is not readable JSON.")
		return
	_config = candidate
	if float(_config.get("warmup_seconds", 0)) < 5 or float(_config.get("minimum_seconds", 0)) < 60 or int(_config.get("minimum_completed_runs", 0)) < 2:
		_abort("Measurement requires five seconds warmup, sixty seconds sample and two completed legal runs.")
		return
	var renderer := RenderingServer.get_current_rendering_method()
	var rendering_driver := RenderingServer.get_current_rendering_driver_name()
	if OS.has_feature("editor") or OS.has_feature("debug") or renderer != "mobile" or rendering_driver != "vulkan" or DisplayServer.get_name() == "headless" or RenderingServer.get_rendering_device() == null:
		_abort("Release, real window, Mobile and Vulkan requirements are not met.")
		return
	if DisplayServer.window_get_size() != Vector2i(1920, 1080) or DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED or not RenderingServer.is_render_loop_enabled():
		_abort("Expected an active 1920x1080 windowed render loop.")
		return
	var scene: PackedScene = load("res://presentation/main.tscn")
	var script: Script = load(str(_config.driver_path))
	if scene == null or script == null or not script.can_instantiate():
		_abort("Production main scene or external input driver did not load.")
		return
	if current_scene != null:
		current_scene.queue_free()
	_session = scene.instantiate()
	_session.set("save_directory", str(_config.save_directory))
	root.add_child(_session)
	current_scene = _session
	_driver = script.new()
	root.add_child(_driver)
	_viewport = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport, true)
	_metadata = {
		"engine": Engine.get_version_info(), "release": OS.has_feature("release"), "debug": OS.has_feature("debug"),
		"renderer": renderer, "rendering_driver": rendering_driver, "display_server": DisplayServer.get_name(),
		"gpu_name": RenderingServer.get_video_adapter_name(), "gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"gpu_api_version": RenderingServer.get_video_adapter_api_version(), "window_client_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"startup_viewport_texture_size": [root.get_texture().get_size().x, root.get_texture().get_size().y],
		"vsync_mode": DisplayServer.window_get_vsync_mode(), "engine_max_fps": Engine.max_fps,
		"screen_refresh_rate_hz": DisplayServer.screen_get_refresh_rate(),
		"save_directory": str(_config.save_directory), "user_data_directory": OS.get_user_data_dir(),
		"clock": "Time.get_ticks_usec / consecutive SceneTree process_frame", "render_time_collection": "RenderingServer.viewport_set_measure_render_time enabled",
		"monitor_semantics": {"engine_fps": "Previous approximately one-second engine window; sampled once per second", "process_peak_1s_ms": "Maximum process + rendering sync/draw duration in previous approximately one-second window, not per-frame CPU duration", "physics_peak_1s_ms": "Maximum physics step duration in previous approximately one-second window, not every frame", "render_cpu_ms": "Viewport rendering CPU duration in milliseconds", "render_gpu_ms": "Viewport GPU timestamp duration in milliseconds when supported"},
		"limitations": ["External input driver and measurement main loop add QA overhead; no subtraction or extrapolation.", "Short representative PC exposure, not two-hour stability or Android acceptance.", "Release MEMORY_STATIC and MEMORY_STATIC_MAX are debug-only and unavailable; reported as null.", "GPU timing is null if no positive hardware timing sample is observed."]
	}
	for name: String in ["engine_fps", "process_peak_1s_ms", "physics_peak_1s_ms", "render_cpu_ms", "render_gpu_ms", "draw_calls", "render_objects", "render_primitives", "vram_bytes", "texture_bytes", "buffer_bytes"]:
		_metrics[name] = PackedFloat64Array()
	_boot_us = Time.get_ticks_usec()
	process_frame.connect(_sample_frame)
	_driver.call("start", _session, 1000, true)
	print("PERF_READY " + JSON.stringify(_metadata))

func _sample_frame() -> void:
	if _ending:
		return
	var now := Time.get_ticks_usec()
	var elapsed := float(now - _boot_us) / 1000000.0
	if elapsed < float(_config.warmup_seconds):
		_last_frame_us = now
		return
	if _sample_start_us == 0:
		_sample_start_us = now
		_last_frame_us = now
		_metadata["viewport_texture_size"] = [root.get_texture().get_size().x, root.get_texture().get_size().y]
		_first_engine_frame = Engine.get_process_frames()
		return
	var interval := float(now - _last_frame_us) / 1000.0
	_last_frame_us = now
	_frames.append(interval)
	var stage := str(_driver.get("stage"))
	if not _stage_frames.has(stage):
		_stage_frames[stage] = PackedFloat64Array()
	_stage_frames[stage].append(interval)
	if now - _last_peak_monitor_us >= 1000000:
		_last_peak_monitor_us = now
		_metrics.engine_fps.append(Performance.get_monitor(Performance.TIME_FPS))
		_metrics.process_peak_1s_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_metrics.physics_peak_1s_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_metrics.render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(_viewport))
	_metrics.render_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(_viewport))
	_metrics.draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_metrics.render_objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_metrics.render_primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_metrics.vram_bytes.append(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	_metrics.texture_bytes.append(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	_metrics.buffer_bytes.append(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED))
	var results: Array = _driver.get("results")
	while _last_result_count < results.size():
		var event: Dictionary = results[_last_result_count].duplicate(true)
		event["measurement_seconds"] = float(now - _sample_start_us) / 1000000.0
		_coverage_events.append(event)
		_last_result_count += 1
	var measured := float(now - _sample_start_us) / 1000000.0
	if now - _last_report_us > 10000000:
		_last_report_us = now
		print("PERF_PROGRESS " + JSON.stringify({"measurement_seconds": measured, "stage": stage, "completed_runs": _driver.get("completed_runs"), "sampled_frames": _frames.size()}))
	if stage == "error":
		_finish(false, "Input playtest driver reported an error.")
	elif measured >= float(_config.minimum_seconds) and int(_driver.get("completed_runs")) >= int(_config.minimum_completed_runs) and _has_real_coverage():
		_finish(true, "Minimum exposure and repeated legal gameplay coverage were observed.")
	elif elapsed >= float(_config.maximum_seconds):
		_finish(false, "Exposure timeout without required repeated gameplay coverage.")

func _has_real_coverage() -> bool:
	var settled := 0
	var combat := 0
	var gathered := 0
	for event: Dictionary in _coverage_events:
		match str(event.get("event", "")):
			"settled": settled += 1
			"all_enemies_defeated": combat += 1
			"objective_and_cargo": gathered += 1
	return settled >= 2 and combat >= 2 and gathered >= 2 and int(_session.get("run_counter")) >= 2

func _finish(ok: bool, message: String) -> void:
	_ending = true
	_driver.call("_release")
	_driver.set("stage", "idle")
	var stages: Dictionary = {}
	for stage: String in _stage_frames:
		stages[stage] = _describe(_stage_frames[stage], true)
	var metrics: Dictionary = {}
	for name: String in _metrics:
		var values: PackedFloat64Array = _metrics[name]
		var statistics := _describe(values)
		metrics[name] = statistics if float(statistics.get("max", 0)) > 0 else null
	metrics["static_memory_bytes"] = null
	metrics["static_memory_peak_bytes"] = null
	var report := {"ok": ok, "message": message, "kind": "release template / byte-identical production gameplay resources / QA launch pack", "metadata": _metadata,
		"warmup_seconds": float(_config.warmup_seconds), "measurement_seconds": float(Time.get_ticks_usec() - _sample_start_us) / 1000000.0,
		"completed_runs": int(_driver.get("completed_runs")), "coverage_verified": _has_real_coverage(), "engine_process_frame_count": Engine.get_process_frames() - _first_engine_frame,
		"frame_ms": _describe(_frames, true), "stages_frame_ms": stages,
		"monitors": metrics, "coverage_events": _coverage_events, "raw_frame_ms": _frames,
		"close_method": "Production AWGameSession._request_quit, save and audio lifecycle awaited by production code"}
	if not _write_report(report):
		print("PERF_REPORT_FAILED")
		ok = false
	else:
		print("PERF_COMPLETE " + JSON.stringify({"ok": ok, "seconds": report.measurement_seconds, "frames": _frames.size(), "completed_runs": report.completed_runs, "frame_ms": report.frame_ms}))
	# This close operation is the production lifecycle; it does not grant any gameplay state.
	if _session.has_method("_request_quit"):
		_session.call("_request_quit")
	else:
		push_error("Production session has no normal quit lifecycle.")
		quit(1)

func _describe(values: PackedFloat64Array, frame_intervals: bool = false) -> Dictionary:
	if values.is_empty():
		return {"samples": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var sum := 0.0
	var over_33 := 0
	var over_50 := 0
	var over_100 := 0
	for value: float in sorted:
		sum += value
		if value > 33.333333: over_33 += 1
		if value > 50: over_50 += 1
		if value > 100: over_100 += 1
	var result := {"samples": sorted.size(), "min": sorted[0], "max": sorted[-1], "mean": sum / sorted.size(),
		"p50": _percentile(sorted, 0.50), "p95": _percentile(sorted, 0.95), "p99": _percentile(sorted, 0.99),
		"percentile_method": "nearest rank"}
	if frame_intervals:
		result["over_33_33_ms"] = over_33
		result["over_50_ms"] = over_50
		result["over_100_ms"] = over_100
	return result

func _percentile(sorted: PackedFloat64Array, quantile: float) -> float:
	return sorted[clampi(ceili(quantile * sorted.size()) - 1, 0, sorted.size() - 1)]

func _write_report(report: Dictionary) -> bool:
	var path := str(_config.report_path)
	var text := JSON.stringify(report, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var good := file.get_error() == OK
	file.close()
	return good and FileAccess.get_file_as_string(path) == text

func _abort(message: String) -> void:
	push_error(message)
	print("PERF_ABORT " + message)
	quit(1)
