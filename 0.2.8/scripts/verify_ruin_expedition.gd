extends SceneTree
## Ruin Expedition loop: discover → crystal power + loot + relic + guardians + UI wiring.
## Usage: godot --headless -s scripts/verify_ruin_expedition.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _RelicRegistry = preload("res://relics/relic_registry.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	# Structural relics
	_RelicRegistry.reset()
	_RelicRegistry.ensure_builtins()
	if _RelicRegistry.get_def(&"pathfinder_charm") == null or _RelicRegistry.get_def(&"ruin_seal") == null:
		_fail("ruin loot relics missing from registry")
	else:
		print("OK pathfinder_charm + ruin_seal registered")
	var pool: Array = _RelicRegistry.ruin_loot_pool()
	if pool.size() < 2:
		_fail("ruin_loot_pool too small")
	else:
		print("OK ruin_loot_pool size=%d" % pool.size())

	var overlay_src := (load("res://ui/game_overlay.gd") as GDScript).source_code
	if "ruin_expedition_completed" not in overlay_src or "Plundered" not in overlay_src:
		_fail("overlay must surface expedition toast")
	else:
		print("OK overlay expedition wiring")
	if "get_ruins_hud_line" not in overlay_src and "ruins_line" not in overlay_src:
		_fail("overlay must surface ruins HUD")
	else:
		print("OK ruins HUD wiring")

	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("main missing")
		_ProbeExit.finish_tree(self, 1, "Ruin expedition FAILED")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while compose and not bool(compose.get("_boot_done")) and frames < 2400:
		await process_frame
		frames += 1

	var lwd = get_first_node_in_group("living_world_director")
	var crystal = get_first_node_in_group("crystal_manager")
	var player = get_first_node_in_group("player")
	var spawner = get_first_node_in_group("crystal_enemy_spawner")
	if lwd == null or crystal == null or player == null:
		_fail("lwd/crystal/player missing")
		_ProbeExit.finish_tree(self, 1, "Ruin expedition FAILED")
		return

	var pf := 0
	while player and not bool(player.get("world_ready")) and pf < 600:
		await process_frame
		pf += 1

	# Spawner API
	if spawner == null or not spawner.has_method("spawn_enemy_at_column"):
		_fail("crystal_enemy_spawner.spawn_enemy_at_column missing")
	else:
		print("OK spawn_enemy_at_column present")

	var power_before: float = float(crystal.power)
	var inv = player.get("inventory")
	var stone_before: int = inv.count_item("stone") if inv and inv.has_method("count_item") else 0
	var relic_mgr = player.get_node_or_null("RelicManager")
	var equipped_before: int = relic_mgr.equipped.size() if relic_mgr and "equipped" in relic_mgr else 0
	var enemies_before := get_nodes_in_group("crystal_enemy").size()

	var result: Dictionary = {}
	if lwd.has_method("harness_force_discover_nearest_ruin"):
		result = lwd.harness_force_discover_nearest_ruin()
	if result.is_empty():
		_fail("expedition harness returned empty")
		_ProbeExit.finish_tree(self, 1, "Ruin expedition FAILED")
		return
	print("expedition result=%s" % result)

	# Crystal power up
	if float(crystal.power) <= power_before:
		_fail("ruin must still feed crystal power")
	else:
		print("OK crystal power %.1f→%.1f" % [power_before, float(crystal.power)])

	# Loot
	var loot: Dictionary = result.get("loot", {})
	if int(loot.get("stone", 0)) < 1:
		_fail("expected stone loot")
	else:
		print("OK loot stone=%d herb=%d" % [int(loot.get("stone", 0)), int(loot.get("herb", 0))])
	if inv and inv.has_method("count_item"):
		var stone_after: int = inv.count_item("stone")
		if stone_after <= stone_before:
			_fail("inventory stone did not increase")
		else:
			print("OK inventory stone %d→%d" % [stone_before, stone_after])

	# Relic if slots free (player starts with crystal_ward — 2 free)
	var relic_id: String = str(result.get("relic_id", ""))
	if relic_id == "" and equipped_before < 3:
		_fail("expected a ruin relic when slots free equipped_before=%d" % equipped_before)
	elif relic_id != "":
		print("OK relic granted %s" % relic_id)
		if relic_mgr and relic_id not in relic_mgr.equipped:
			_fail("relic not equipped on RelicManager")
		else:
			print("OK relic equipped on manager")

	# Guardians
	await process_frame
	await process_frame
	var enemies_after := get_nodes_in_group("crystal_enemy").size()
	var gcount: int = int(result.get("guardians", 0))
	if gcount < 1 and enemies_after <= enemies_before:
		_fail("expected ruin guardians (result=%d enemies %d→%d)" % [gcount, enemies_before, enemies_after])
	else:
		print("OK guardians result=%d enemies %d→%d" % [gcount, enemies_before, enemies_after])

	# HUD line
	if lwd.has_method("get_ruins_hud_line"):
		var line: String = str(lwd.get_ruins_hud_line())
		if "Ruins" not in line:
			_fail("ruins HUD line empty/wrong: %s" % line)
		else:
			print("OK ruins HUD '%s'" % line)

	# Biome first visit
	if lwd.has_method("_try_first_biome_visit"):
		var herb_b: int = inv.count_item("herb") if inv else 0
		lwd._visited_biomes.erase("steppe")
		lwd._try_first_biome_visit("steppe")
		var herb_a: int = inv.count_item("herb") if inv else 0
		if herb_a <= herb_b:
			_fail("biome first visit should grant herbs")
		else:
			print("OK biome first visit herb %d→%d" % [herb_b, herb_a])

	# Idempotent
	var again: Dictionary = lwd.discover_ruin_at(result.get("center", Vector2i.ZERO))
	if not again.is_empty():
		_fail("second discover must be empty")
	else:
		print("OK expedition idempotent")

	if _failed == 0:
		print("All ruin expedition tests OK")
		_ProbeExit.finish_tree(self, 0, "All ruin expedition tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "Ruin expedition FAILED")
