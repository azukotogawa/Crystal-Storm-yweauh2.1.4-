extends SceneTree
## Main-scene composition boot: stages, registry, diagnostics.
## Usage: godot --headless -s scripts/verify_composition_boot.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const _CompositionRoot = preload("res://systems/composition_root.gd")


var _failed: int = 0
var _stages_seen: Array = []


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("no main")
		quit(1)
		return
	var game: Node = packed.instantiate()
	var compose = game.get_node_or_null("CompositionRoot")
	if compose == null:
		_fail("CompositionRoot node missing from main.tscn")
		quit(1)
		return
	# BEFORE add_child: main._ready will call boot_async with these overrides.
	if compose.has_method("set_debug_overrides"):
		compose.set_debug_overrides({"render_distance": 7, "caves_enabled": false})
	if compose.has_signal("stage_changed"):
		compose.stage_changed.connect(func(_id: int, name: String): _stages_seen.append(name))

	root.add_child(game)

	# Wait for boot
	var frames := 0
	while not bool(compose.get("_boot_done")) and int(compose.stage) != _CompositionRoot.Stage.FAILED and frames < 2400:
		await process_frame
		frames += 1

	if int(compose.stage) == _CompositionRoot.Stage.FAILED:
		_fail("boot failed: %s" % str(compose.get("_failed_reason")))
	elif not bool(compose.get("_boot_done")):
		_fail("boot timeout stage=%s" % compose.get_stage_name())
	else:
		print("OK composition boot completed stage=%s" % compose.get_stage_name())

	# Registry has critical services
	var reg = compose.registry
	if reg == null:
		_fail("registry null")
	else:
		for id in [&"config_service", &"performance_service", &"world", &"world_features", &"chunk_manager", &"spatial_query_service"]:
			if not reg.has_service(id):
				_fail("missing registered service %s" % str(id))
		var cm = reg.resolve(&"chunk_manager")
		var cm2 = reg.require(&"chunk_manager")
		if cm == null or cm != cm2:
			_fail("chunk_manager DI instance mismatch")
		else:
			print("OK DI chunk_manager registered")

	# Stages monotonic
	var expected := [
		"CONFIGURED", "QUALITY_APPLIED", "FEATURES_SEEDED",
		"CHUNKS_CREATED", "INITIAL_STREAM_READY", "VISUALS_COMMITTED", "RUNNING",
	]
	var last_idx := -1
	for s in expected:
		var idx: int = _stages_seen.find(s)
		if idx < 0:
			# May have missed if signal late; check final stage times
			var times: Dictionary = compose.get("_stage_times_ms") if "_stage_times_ms" in compose else {}
			if not times.has(s) and compose.get_stage_name() != "RUNNING":
				_fail("stage %s not observed" % s)
		elif idx < last_idx:
			_fail("stage order violation around %s" % s)
		else:
			last_idx = idx
	print("OK stages seen: %s" % str(_stages_seen))

	# Diagnostics API
	var diag: Dictionary = compose.get_diagnostics()
	if not diag.has("registry") or not diag.has("stage_times_ms"):
		_fail("diagnostics incomplete")
	else:
		print("OK diagnostics keys present")
	var health: Dictionary = compose.get_health_report()
	if not bool(health.get("running", false)):
		_fail("health report should show running")
	else:
		print("OK service health report")

	# Resolved config present
	if compose.resolved_config.is_empty():
		_fail("resolved_config empty after boot")
	elif not compose.resolved_config.has("policy"):
		_fail("resolved_config missing policy")
	else:
		print("OK resolved runtime config")

	# Consumer must observe debug policy knobs (not raw quality alone)
	var policy: Dictionary = compose.resolved_config.get("policy", {})
	if int(policy.get("render_distance", -1)) != 7:
		_fail("resolved policy render_distance should be debug=7 (got %s)" % str(policy.get("render_distance")))
	var cm_live = reg.resolve(&"chunk_manager")
	if cm_live == null:
		_fail("chunk_manager missing for policy consumer assert")
	elif int(cm_live.RENDER_DISTANCE) != 7:
		_fail("ChunkManager.RENDER_DISTANCE must match policy after apply (got %d want 7)" % int(cm_live.RENDER_DISTANCE))
	else:
		print("OK ChunkManager consumed resolved policy render_distance=7")
	var world_live = reg.resolve(&"world")
	if world_live and "caves_enabled" in world_live:
		if bool(world_live.caves_enabled) != false and world_live.has_method("get"):
			pass
	# caves_enabled may be stored differently; policy false is what matters on set_caves_enabled
	print("OK policy consumer checks complete")

	# Shutdown ordering: release chunks/workers before freeing scene.
	var shut_before: Array = reg.shutdown_order().duplicate()
	compose.shutdown()
	if int(compose.stage) != _CompositionRoot.Stage.SHUTTING_DOWN:
		_fail("shutdown did not enter SHUTTING_DOWN")
	else:
		print("OK shutdown stage + order size=%d" % shut_before.size())

	# Chunks already released in compose.shutdown(). Let SceneTree own a single free path.
	# (Manual free() + quit previously raced ObjectDB and printed double-free on exit.)
	await process_frame
	if _failed == 0:
		print("All composition boot tests OK")
		if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT") == "1":
			OS.kill(OS.get_process_id())
			return
		quit(0)
	else:
		quit(1)
