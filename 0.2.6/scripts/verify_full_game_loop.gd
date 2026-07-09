extends SceneTree
## Structural proof that existing systems wire the full spawn→win loop.

const MAIN_SCENE := "res://scenes/main.tscn"
const _GameManager = preload("res://game/game_manager.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("main scene missing")
		_ProbeExit.finish_tree(self, 1, "Full game loop FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var crystal: CrystalManager = null
	var game_manager: _GameManager = null
	var terrain: TerrainEditor = null
	var enemy_spawner = null

	for _attempt in 1200:
		player = get_first_node_in_group("player")
		crystal = get_first_node_in_group("crystal_manager") as CrystalManager
		game_manager = get_first_node_in_group("game_manager") as _GameManager
		terrain = get_first_node_in_group("terrain_editor") as TerrainEditor
		enemy_spawner = get_first_node_in_group("crystal_enemy_spawner")
		if (
			player != null and bool(player.get("world_ready"))
			and crystal != null and crystal._initialized
			and game_manager != null and terrain != null
		):
			break
		await process_frame

	if crystal == null or not crystal._initialized:
		push_error("crystal_manager not ready")
		failed = true
	elif crystal.get_active_spawns().size() < 3:
		push_error("expected >=3 active spawns, got %d" % crystal.get_active_spawns().size())
		failed = true
	else:
		var boss_found := false
		for spawn in crystal.get_active_spawns():
			if spawn.is_boss:
				boss_found = true
				if _CrystalTypes.is_water_tile(crystal._tile_at(spawn.world_pos)):
					push_error("boss spawn on water %s" % spawn.world_pos)
					failed = true
				break
		if not boss_found:
			push_error("missing origin boss spawn")
			failed = true
		else:
			print("OK spawns=%d incl origin boss" % crystal.get_active_spawns().size())

	if player == null or player.inventory == null:
		push_error("player inventory missing")
		failed = true
	elif player.inventory.count_item("stone") < 1 or player.inventory.count_item("stone_pick") < 1:
		push_error("player missing collect/build tools")
		failed = true
	else:
		print("OK player inventory wired for collect/build")

	if terrain == null:
		push_error("terrain editor missing")
		failed = true
	else:
		print("OK terrain editor bound")

	if enemy_spawner == null:
		push_error("crystal enemy spawner missing")
		failed = true
	else:
		print("OK crystal enemy spawner present")

	if game_manager == null:
		push_error("game manager missing")
		failed = true
	else:
		game_manager._crystal = crystal
		game_manager._on_all_spawns_destroyed()
		if game_manager.run_state != _GameManager.RunState.WON:
			push_error("win path not wired")
			failed = true
		else:
			print("OK win state on all spawns destroyed")

	var lose_gm := _GameManager.new()
	lose_gm.max_crystal_coverage = 0.01
	lose_gm._crystal = crystal
	crystal.covered_cells = 50000
	lose_gm._check_crystal_overrun()
	if lose_gm.run_state != _GameManager.RunState.LOST:
		push_error("lose path not wired")
		failed = true
	else:
		print("OK lose state on coverage overrun")

	if failed:
		_ProbeExit.finish_tree(self, 1, "Full game loop FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "All full game loop tests OK")