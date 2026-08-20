extends SceneTree
## WorldManager + PlayerSettings CRUD against shipped catalog/settings I/O.

const _WorldManager = preload("res://systems/world_manager.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const CAT := "user://worlds_test_frontend/catalog.json"
const SET := "user://worlds_test_frontend/settings.json"
const SEED := 880011

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
	_wipe_dir("user://worlds_test_frontend")
	_WorldManager.catalog_path = CAT
	_PlayerSettings.settings_path = SET

	var created: Dictionary = _WorldManager.create_world("Storm Alpha", SEED)
	if not bool(created.get("ok", false)) or str(created.get("id", "")).is_empty():
		_fail("create world")
		_finish()
		return
	_ok("create world id=%s seed=%d" % [created.id, int(created.seed)])
	if int(created.get("seed", 0)) != SEED:
		_fail("seed persist on create")
	else:
		_ok("seed persist on create")

	var listed: Array = _WorldManager.list_worlds()
	if listed.size() != 1 or str(listed[0].get("id", "")) != str(created.id):
		_fail("list world")
	else:
		_ok("list world n=1")

	var got: Dictionary = _WorldManager.get_world(str(created.id))
	if got.is_empty() or int(got.get("seed", 0)) != SEED:
		_fail("load metadata")
	else:
		_ok("load metadata name=%s" % str(got.get("name", "")))

	var renamed: Dictionary = _WorldManager.rename_world(str(created.id), "Storm Beta")
	if not bool(renamed.get("ok", false)) or str(renamed.get("name", "")) != "Storm Beta":
		_fail("rename world")
	else:
		_ok("rename world")

	var unconf: Dictionary = _WorldManager.delete_world(str(created.id), false)
	if bool(unconf.get("ok", false)) or str(unconf.get("error", "")) != "confirmation_required":
		_fail("delete without confirm")
	elif _WorldManager.get_world(str(created.id)).is_empty():
		_fail("delete without confirm removed row")
	else:
		_ok("delete without confirm does not delete")

	var gone: Dictionary = _WorldManager.delete_world(str(created.id), true)
	if not bool(gone.get("ok", false)) or not _WorldManager.get_world(str(created.id)).is_empty():
		_fail("delete world")
	else:
		_ok("delete world")

	if not _PlayerSettings.save_settings({
		"quality_preset": 2,
		"render_distance": 4,
		"vegetation_scatter_multiplier": 0.25,
		"combat_visuals_enabled": false,
	}):
		_fail("settings write")
	else:
		var again: Dictionary = _PlayerSettings.load_settings()
		if int(again.get("render_distance", 0)) != 4 or bool(again.get("combat_visuals_enabled", true)):
			_fail("settings reread")
		else:
			_ok("settings write+reread rd=%d" % int(again.render_distance))

	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("main scene missing")
	else:
		var game: Node = packed.instantiate()
		root.add_child(game)
		var compose = game.get_node_or_null("CompositionRoot")
		var frames := 0
		while compose != null and int(compose.stage) < compose.Stage.QUALITY_APPLIED and frames < 600:
			await process_frame
			frames += 1
		var perf = game.get_node_or_null("PerformanceService")
		if compose == null or int(compose.stage) < compose.Stage.QUALITY_APPLIED:
			_fail("boot did not reach QUALITY_APPLIED")
		elif perf == null or perf.quality == null:
			_fail("performance quality missing after boot")
		elif int(perf.quality.render_distance) != 4:
			_fail("settings did not reach game rd=%s" % str(perf.quality.render_distance))
		elif bool(perf.quality.combat_visuals_enabled):
			_fail("settings did not reach game combat_visuals")
		elif absf(float(perf.quality.vegetation_scatter_multiplier) - 0.25) > 0.001:
			_fail("settings did not reach game veg=%s" % str(perf.quality.vegetation_scatter_multiplier))
		elif int(perf.quality.preset) != 2:
			_fail("settings did not reach game preset=%s" % str(perf.quality.preset))
		else:
			_ok("settings reach running game after QUALITY_APPLIED rd=%d veg=%.2f fx=%s" % [
				int(perf.quality.render_distance),
				float(perf.quality.vegetation_scatter_multiplier),
				str(perf.quality.combat_visuals_enabled),
			])
		if game.get_parent() == root:
			game.queue_free()
			await process_frame

	_WorldManager.reset_paths()
	_PlayerSettings.reset_path()
	_wipe_dir("user://worlds_test_frontend")
	_finish()


func _finish() -> void:
	if _failed > 0:
		_ProbeExit.finish_tree(self, 1, "World frontend FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "All world frontend tests OK")
