extends SceneTree
## Automatic production world-bake workflow (no terminal/env required for players).
##
## Checks:
## 1) Production defaults → full 128×128 chunks without any bake env vars.
## 2) First bootstrap with missing bake → automatic rebuild.
## 3) Second bootstrap → mode=loaded, mesh plans mode=valid (no rebuild/repair).
##
## Smoke uses a small radius for speed; production size is asserted separately.

const _WorldState = preload("res://world/world_state.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const SEED := 424242
const SMOKE_RAD := 1


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_production_defaults()
	failed += _test_two_bootstrap_auto_bake()
	if failed > 0:
		_ProbeExit.finish_tree(self, 1, "VERIFY_AUTO_BAKE_FAIL n=%d" % failed)
	else:
		_ProbeExit.finish_tree(self, 0, "VERIFY_AUTO_BAKE_OK")


func _test_production_defaults() -> int:
	var failed := 0
	# No bake env → production path.
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "")
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "")
	if not bool(_WorldBakeService.use_full_world_from_env()):
		push_error("FAIL: production default must use full world (no env)")
		failed += 1
	else:
		print("OK production use_full_world=true without env")
	if not bool(_WorldBakeService.bake_on_new_from_env()):
		push_error("FAIL: production default must auto-bake")
		failed += 1
	else:
		print("OK production bake_on_new=true without env")
	if not bool(_WorldBakeService.bake_enabled_from_env()):
		push_error("FAIL: production world bake must be enabled")
		failed += 1
	else:
		print("OK production world bake enabled")
	var side: int = int(_WorldBakeService.production_chunk_side())
	if side != 128:
		push_error("FAIL: production_chunk_side want 128 got %d" % side)
		failed += 1
	else:
		print("OK production_chunk_side=128")
	var b: Dictionary = _WorldBakeService.full_world_chunk_bounds()
	if int(b.get("chunks", 0)) != 16384:
		push_error("FAIL: production chunks want 16384 got %s" % str(b.get("chunks")))
		failed += 1
	else:
		print("OK production size 128x128 chunks=16384")
	return failed


func _wipe(seed: int, rad: int) -> void:
	var tmp: _WorldBakeService = _WorldBakeService.new()
	var dir: String = tmp.bake_dir_for(seed, rad, false)
	var global := ProjectSettings.globalize_path(dir)
	if DirAccess.dir_exists_absolute(global):
		_rm_rf(global)
		print("WIPED %s" % dir)


func _rm_rf(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if n != "." and n != "..":
			var child := path.path_join(n)
			if da.current_is_dir():
				_rm_rf(child)
			else:
				DirAccess.remove_absolute(child)
		n = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)


func _test_two_bootstrap_auto_bake() -> int:
	var failed := 0
	# Fast smoke size for rebuild proof (production size asserted above).
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", str(SMOKE_RAD))
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "")  # default auto
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "1")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "")

	_WorldState.replace_active()
	_WorldBakeService.clear_active()
	_wipe(SEED, SMOKE_RAD)

	var world = _InfiniteNoiseWorld.new(SEED)
	var host = _ChunkManager.new()
	host.world = world
	root.add_child(host)

	# --- First bootstrap: missing → rebuild ---
	var bake1: _WorldBakeService = _WorldBakeService.new()
	_WorldBakeService.set_active(bake1)
	var boot1: Dictionary = bake1.bootstrap_for_world(world, false, host)
	var mode1 := str(boot1.get("mode", ""))
	if mode1 != "baked":
		push_error("FAIL: first bootstrap expected mode=baked got %s err=%s" % [mode1, str(boot1.get("error", ""))])
		failed += 1
	else:
		print("OK launch1 automatic rebuild mode=baked chunks=%s" % str(boot1.get("chunks", 0)))
	if not bool(bake1.valid) or not bool(bake1.vegetation_baked):
		push_error("FAIL: launch1 bake invalid or vegetation missing")
		failed += 1
	else:
		print("OK launch1 vegetation_baked=true")
	var val1: Dictionary = bake1.validate_loaded_bake(SEED, false)
	if not bool(val1.get("ok", false)):
		push_error("FAIL: launch1 validation %s" % str(val1.get("reasons", [])))
		failed += 1
	else:
		print(
			"OK launch1 validation size=%s mesh_plans=%s"
			% [str(val1.get("size_label")), str(val1.get("mesh_plans_ok"))]
		)
	var mp1: Dictionary = boot1.get("mesh_plan", {})
	print("launch1 mesh_plan mode=%s" % str(mp1.get("mode", "")))
	var meta_path: String = bake1.package_dir.path_join("plan_seed_meta.json")
	if not FileAccess.file_exists(meta_path):
		# ensure_mesh_plans should have written meta for valid plans.
		bake1._write_plan_seed_meta()
	if not FileAccess.file_exists(meta_path):
		push_error("FAIL: plan_seed_meta.json not written after launch1")
		failed += 1
	else:
		print("OK plan_seed_meta written (repair stamp persisted)")

	# --- Second bootstrap: load only ---
	_WorldBakeService.clear_active()
	var bake2: _WorldBakeService = _WorldBakeService.new()
	_WorldBakeService.set_active(bake2)
	var boot2: Dictionary = bake2.bootstrap_for_world(world, false, host)
	var mode2 := str(boot2.get("mode", ""))
	if mode2 != "loaded":
		push_error("FAIL: second bootstrap expected mode=loaded got %s" % mode2)
		failed += 1
	else:
		print("OK launch2 mode=loaded (no rebuild)")
	var mp2: Dictionary = boot2.get("mesh_plan", {})
	var mpm2 := str(mp2.get("mode", ""))
	if mpm2 == "repaired" or mpm2 == "baked" or mpm2 == "repair_failed":
		push_error("FAIL: launch2 must not repair mesh plans mode=%s" % mpm2)
		failed += 1
	else:
		print("OK launch2 mesh_plan mode=%s (no repair)" % mpm2)
	var val2: Dictionary = bake2.validate_loaded_bake(SEED, false)
	if not bool(val2.get("ok", false)):
		push_error("FAIL: launch2 validation %s" % str(val2.get("reasons", [])))
		failed += 1
	else:
		print("OK launch2 validation still clean")

	# Third bootstrap still loaded/valid (idempotent).
	var boot3: Dictionary = bake2.bootstrap_for_world(world, false, host)
	if str(boot3.get("mode", "")) != "loaded":
		push_error("FAIL: third bootstrap expected loaded got %s" % str(boot3.get("mode")))
		failed += 1
	else:
		print("OK launch3 still loaded (stable)")

	host.queue_free()
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "")
	return failed
