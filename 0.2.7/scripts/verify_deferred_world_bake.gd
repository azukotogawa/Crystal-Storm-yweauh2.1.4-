extends SceneTree
## Deferred fill: prime ring playable, valid only after all packages, on-demand far chunk.
## Usage: godot --headless -s scripts/verify_deferred_world_bake.gd

const _WorldState = preload("res://world/world_state.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const SEED := 424201
const RADIUS := 6

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "1")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "1")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", str(RADIUS))
	OS.set_environment("CRYSTALSTORM_BAKE_DEFER_FILL", "1")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL: %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _run() -> void:
	_WorldState.replace_active()
	_WorldBakeService.clear_active()
	var world = _InfiniteNoiseWorld.new(SEED)
	var host = _ChunkManager.new()
	var bake: _WorldBakeService = _WorldBakeService.ensure_active()
	bake.delete_bake(SEED, RADIUS)

	if not bake.has_method("_bake_one_chunk") or not bake.has_method("package_ready") \
			or not bake.has_method("prime_region") or not bake.has_method("defer_fill_from_env"):
		_fail("missing deferred-fill APIs")
		_finish()
		return
	if not bake.defer_fill_from_env():
		_fail("defer_fill_from_env should default on")
	else:
		_ok("defer fill enabled")

	var t0 := Time.get_ticks_msec()
	var result: Dictionary = await bake.bootstrap_for_world_async(world, false, host)
	var prime_ms := Time.get_ticks_msec() - t0
	var mode := str(result.get("mode", ""))
	if mode != "partial" and mode != "baked":
		_fail("bootstrap mode want partial|baked got=%s" % mode)
	else:
		_ok("bootstrap mode=%s prime_ms=%d chunks=%s" % [mode, prime_ms, str(result.get("chunks", 0))])
	if not bake.package_ready(Vector2i.ZERO):
		_fail("origin package missing after prime")
	else:
		_ok("origin package ready")
	var data = load("res://chunks/chunk_data.gd").new(Vector2i.ZERO, world)
	data.capture_base_only_snapshot()
	if not bake.try_apply_base_to_chunk_data(data):
		_fail("try_apply_base failed on primed origin")
	else:
		_ok("try_apply_base on primed origin")
		if float(data.surface_map[0][0]) < -9000.0:
			_fail("primed origin surface empty")
		else:
			_ok("primed origin surface=%.2f" % float(data.surface_map[0][0]))

	var expected: int = bake.expected_chunk_count()
	if mode == "partial":
		if bake.valid:
			_fail("partial bootstrap must not set valid")
		else:
			_ok("valid=false during fill expected=%d known=%d" % [expected, bake.fill_status().get("done", 0)])
		if not bake.bake_in_progress:
			_fail("bake_in_progress should be true while packages remain")
		else:
			_ok("bake_in_progress")
		# Far in-bounds coord should on-demand bake, not stay empty.
		var far := Vector2i(RADIUS, RADIUS)
		if bake.package_ready(far):
			_ok("far coord already primed")
		else:
			if not bake.ensure_package_for_stream(far):
				_fail("on-demand bake failed for %s" % str(far))
			elif not bake.package_ready(far):
				_fail("on-demand did not write package %s" % str(far))
			else:
				_ok("on-demand baked %s" % str(far))
		if bake.valid:
			_fail("on-demand must not commit world.index")
		else:
			_ok("index still invalid after on-demand")
		# Session replace must be blocked during fill.
		var prev = _WorldState.get_active()
		var after = _WorldState.replace_active()
		if after != prev:
			_fail("replace_active mutated session during fill")
		else:
			_ok("replace_active blocked during fill")
	else:
		_ok("smoke world fully primed; index committed immediately")

	# Rollback helper exists.
	OS.set_environment("CRYSTALSTORM_BAKE_DEFER_FILL", "0")
	if bake.defer_fill_from_env():
		_fail("DEFER_FILL=0 should disable defer")
	else:
		_ok("rollback env disables defer")
	OS.set_environment("CRYSTALSTORM_BAKE_DEFER_FILL", "1")

	_finish()


func _finish() -> void:
	if _failed > 0:
		_ProbeExit.finish_tree(self, 1, "Deferred world bake FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "All deferred world bake tests OK")
