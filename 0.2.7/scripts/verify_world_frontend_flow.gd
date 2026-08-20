extends SceneTree
## Catalog flow: cold/deferred create, warm load, incomplete bake row, return-to-select.

const _WorldManager = preload("res://systems/world_manager.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const CAT := "user://worlds_test_frontend_flow/catalog.json"
const SEED_COLD := 880021
const SEED_WARM := 880022
const SEED_INC := 880023

var _failed: int = 0


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL: %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _wipe_dir(rel: String) -> void:
	var abs := ProjectSettings.globalize_path(rel)
	if not DirAccess.dir_exists_absolute(abs):
		return
	var da := DirAccess.open(rel)
	if da == null:
		return
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if n != "." and n != "..":
			if da.current_is_dir():
				_wipe_dir(rel.path_join(n))
			else:
				DirAccess.remove_absolute(abs.path_join(n))
		n = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(abs)


func _run() -> void:
	_wipe_dir("user://worlds_test_frontend_flow")
	_WorldManager.catalog_path = CAT
	_WorldManager.pending_launch = {}
	_WorldManager.return_to_select = false

	var cold: Dictionary = _WorldManager.create_world("Cold Deferred", SEED_COLD)
	if not bool(cold.get("ok", false)):
		_fail("cold create")
	elif bool(cold.get("bake_valid", true)):
		_fail("cold create must not require valid index")
	else:
		_ok("cold/deferred create catalog row incomplete=%s" % str(cold.get("bake_incomplete", true)))

	var loaded: Dictionary = _WorldManager.load_world(str(cold.get("id", "")))
	if not bool(loaded.get("ok", false)) or _WorldManager.pending_launch.is_empty():
		_fail("load still allowed when incomplete")
	else:
		_ok("incomplete load allowed seed=%s" % str(_WorldManager.pending_launch.get("seed", "")))
	_WorldManager.take_pending_launch()

	var warm: Dictionary = _WorldManager.create_world("Warm Complete", SEED_WARM)
	var bake_dir := "user://world_bakes/v4_s%d_full" % SEED_WARM
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(bake_dir))
	var idx := FileAccess.open(bake_dir.path_join("world.index"), FileAccess.WRITE)
	if idx:
		idx.store_string("TEST_INDEX")
		idx.close()
	var warm_row: Dictionary = _WorldManager.get_world(str(warm.get("id", "")))
	if not bool(warm_row.get("bake_valid", false)):
		_fail("warm catalog should show index-complete")
	else:
		_ok("warm load of complete catalog entry progress=%s" % str(warm_row.get("progress", "")))
	var warm_load: Dictionary = _WorldManager.load_world(str(warm.get("id", "")))
	if not bool(warm_load.get("ok", false)):
		_fail("warm load_world")
	else:
		_ok("warm load_world pending seed=%s" % str(_WorldManager.take_pending_launch().get("seed", "")))

	var inc: Dictionary = _WorldManager.create_world("Partial Bake", SEED_INC)
	var inc_dir := "user://world_bakes/v4_s%d_full/chunks" % SEED_INC
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(inc_dir))
	var fake := FileAccess.open(inc_dir.path_join("0_0.chk"), FileAccess.WRITE)
	if fake:
		fake.store_string("not-a-real-package")
		fake.close()
	var inc_row: Dictionary = _WorldManager.get_world(str(inc.get("id", "")))
	if not bool(inc_row.get("bake_incomplete", false)):
		_fail("incomplete bake row")
	elif not _WorldManager.load_world(str(inc.get("id", ""))).get("ok", false):
		_fail("incomplete still playable")
	else:
		_ok("incomplete deferred-bake row progress=%s" % str(inc_row.get("progress", "")))
	_WorldManager.take_pending_launch()

	_WorldManager.request_return_to_select()
	if not _WorldManager.consume_return_to_select():
		_fail("return-from-game path")
	elif _WorldManager.consume_return_to_select():
		_fail("return flag should be one-shot")
	elif _WorldManager.list_worlds().size() < 3:
		_fail("return wiped catalog")
	else:
		_ok("return-from-game-to-world-select leaves catalog")

	_WorldBakeService.ensure_active().delete_bake(SEED_WARM, -1)
	_WorldBakeService.ensure_active().delete_bake(SEED_INC, -1)
	_WorldManager.reset_paths()
	_wipe_dir("user://worlds_test_frontend_flow")
	_finish()


func _finish() -> void:
	if _failed > 0:
		_ProbeExit.finish_tree(self, 1, "World frontend flow FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "All world frontend flow tests OK")
