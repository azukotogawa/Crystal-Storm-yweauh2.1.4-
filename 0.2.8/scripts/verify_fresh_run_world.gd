extends SceneTree

const _Worlds = preload("res://systems/world_manager.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const TEST_CATALOG := "user://verify_fresh_run_world/worlds/catalog.json"
const ENTRY_POINTS := [
	"res://scripts/honest_bot/honest_scenario.gd",
	"res://scripts/verify_honest_bot_run.gd",
	"res://scripts/verify_honest_bot_showcase.gd",
]

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL " + msg)


func _run() -> void:
	_Worlds.catalog_path = TEST_CATALOG
	var dummy: Dictionary = _Worlds.create_world("Dummy", 777)
	var dummy_id := str(dummy.get("id", ""))
	var junk := TEST_CATALOG.get_base_dir().path_join("dummy_world/region.bin")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(junk.get_base_dir()))
	var f := FileAccess.open(junk, FileAccess.WRITE)
	f.store_string("old")
	f.close()
	if _Worlds.get_world(dummy_id).is_empty() or not FileAccess.file_exists(junk):
		_fail("dummy world was not seeded")
	var launch: Dictionary = _Worlds.start_fresh_run()
	if not bool(launch.get("ok", false)):
		_fail("fresh run did not create a world: %s" % str(launch))
	if not _Worlds.get_world(dummy_id).is_empty():
		_fail("dummy world still in the catalog")
	if FileAccess.file_exists(junk) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(junk.get_base_dir())):
		_fail("dummy world files survived")
	var worlds: Array = _Worlds.list_worlds()
	if worlds.size() != 1 or int(worlds[0].get("seed", -1)) != 12349:
		_fail("catalog must hold one world seeded 12349: %s" % str(worlds))
	if int(_Worlds.pending_launch.get("seed", -1)) != 12349 or _Worlds.pending_resume:
		_fail("pending launch must be a fresh seed 12349 start")
	else:
		print("OK dummy world wiped and fresh world 12349 queued")
	_check_entry_points()
	await _check_boot()
	_Worlds.wipe_worlds()
	_Worlds.reset_paths()
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "FRESH RUN WORLD OK")
	else:
		_ProbeExit.finish_tree(self, 1, "FRESH RUN WORLD FAILED")


func _check_entry_points() -> void:
	for path in ENTRY_POINTS:
		if not FileAccess.get_file_as_string(path).contains("start_fresh_run("):
			_fail("%s does not start a fresh world" % path)


func _check_boot() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	for _i in 2400:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
	for _i in 30:
		await process_frame
	var world = game.get_node_or_null("World")
	if world == null or int(world.world_seed) != 12349:
		_fail("booted world seed is not 12349")
	var gm = get_first_node_in_group("game_manager")
	if gm == null:
		_fail("no game manager")
		return
	if int(gm.run_state) != int(gm.RunState.PLAYING) or int(gm.phase) != int(gm.Phase.MAZE):
		_fail("run did not start in the opening phase")
	if gm.enemies_killed != 0 or gm.blocks_mined != 0 or gm.deaths != 0 or gm.boss_defeated or gm.spawns_destroyed != 0:
		_fail("run carried progress from an old world: kills %d mined %d deaths %d boss %s spawns %d" % [gm.enemies_killed, gm.blocks_mined, gm.deaths, str(gm.boss_defeated), gm.spawns_destroyed])
	if _failed == 0:
		print("OK booted seed 12349 at the beginning state")