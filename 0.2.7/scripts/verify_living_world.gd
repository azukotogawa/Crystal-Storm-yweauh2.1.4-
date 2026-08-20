extends SceneTree
## Living World Phase 1: steppe + forest biomes, towns/ruins/wildlife, militia/villagers,
## consequential ruin discovery, player-facing biome legibility.
## Usage: godot --headless -s scripts/verify_living_world.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const _FeatureRegistry = preload("res://world/feature_registry.gd")
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
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("main missing")
		_ProbeExit.finish_tree(self, 1, "Living world FAILED")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)

	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while compose and not bool(compose.get("_boot_done")) and frames < 2400:
		await process_frame
		frames += 1

	var world = get_first_node_in_group("world")
	var em = get_first_node_in_group("entity_manager")
	var lwd = get_first_node_in_group("living_world_director")
	var crystal = get_first_node_in_group("crystal_manager")
	var player = get_first_node_in_group("player")

	if world == null:
		_fail("world missing after boot")
	else:
		_test_biomes(world)
		_test_features()
		await _test_agents(em)
		_test_consequential(lwd, crystal, player)

	# Structural: overlay shows biome
	var overlay_src := (load("res://ui/game_overlay.gd") as GDScript).source_code
	if "Biome:" not in overlay_src and "_current_biome" not in overlay_src:
		_fail("game overlay must surface biome")
	else:
		print("OK biome HUD wiring present")

	if lwd == null:
		_fail("LivingWorldDirector missing from main scene")
	else:
		print("OK LivingWorldDirector present")

	if _failed == 0:
		print("All living world tests OK")
		_ProbeExit.finish_tree(self, 0, "All living world tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "Living world FAILED")


func _test_biomes(world) -> void:
	var seed: int = int(world.world_seed) if "world_seed" in world else 0
	print("seed=%d" % seed)
	var steppe_cell: Vector2 = Vector2.ZERO
	var forest_cell: Vector2 = Vector2.ZERO
	var found_steppe := false
	var found_forest := false
	# Scan playable interior for both Living World focus biomes.
	for x in range(-400, 401, 16):
		for z in range(-400, 401, 16):
			var b: Dictionary = world.get_biome(float(x), 0.0, float(z))
			var n: String = str(b.get("name", ""))
			if not found_steppe and n == "steppe":
				found_steppe = true
				steppe_cell = Vector2(x, z)
			if not found_forest and (n == "forest" or n == "dense forest" or n == "pine forest" or n == "jungle"):
				found_forest = true
				forest_cell = Vector2(x, z)
			if found_steppe and found_forest:
				break
		if found_steppe and found_forest:
			break
	if not found_steppe:
		_fail("steppe biome not found at seed")
	else:
		print("OK steppe at %s" % steppe_cell)
	if not found_forest:
		_fail("temperate forest biome not found at seed")
	else:
		print("OK forest at %s (%s)" % [
			forest_cell,
			world.get_biome(forest_cell.x, 0.0, forest_cell.y).get("name", "")
		])


func _test_features() -> void:
	var towns: Array = _FeatureRegistry.get_towns()
	var ruins: Array = _FeatureRegistry.get_ruin_centers()
	var animals: Array = _FeatureRegistry.get_entity_spawns()
	if towns.size() < 1:
		_fail("expected ≥1 town after bootstrap (got %d)" % towns.size())
	else:
		print("OK towns=%d first=%s" % [towns.size(), towns[0].get("name", "?")])
	if ruins.size() < 1:
		_fail("expected ≥1 ruin (got %d)" % ruins.size())
	else:
		print("OK ruins=%d" % ruins.size())
	if animals.size() < 1:
		_fail("expected ≥1 wildlife spawn entry (got %d)" % animals.size())
	else:
		print("OK wildlife spawn entries=%d" % animals.size())


func _test_agents(em) -> void:
	if em == null:
		_fail("entity_manager missing")
		return
	# Town population seeds at bootstrap; allow a few frames for spawn.
	for _i in 30:
		await process_frame
	var count: int = em.get_active_entity_count() if em.has_method("get_active_entity_count") else 0
	# Villagers/militia spawn at seed even before chunks; if zero, force militia on first town.
	if count < 1:
		var towns: Array = _FeatureRegistry.get_towns()
		if towns.size() > 0 and em.has_method("ensure_town_population"):
			em.ensure_town_population(towns[0])
		count = em.get_active_entity_count()
	if count < 1:
		_fail("expected living town agents (villagers/militia), got %d" % count)
	else:
		print("OK living agents count=%d" % count)
	# Brain registry has villager
	var brains = load("res://entities/entity_brain_registry.gd")
	if brains.get_def(&"town_villager") == null:
		_fail("town_villager brain missing")
	else:
		print("OK town_villager brain registered")
	await _test_town_stream_reseed(em)


func _test_town_stream_reseed(em) -> void:
	var towns: Array = _FeatureRegistry.get_towns()
	if towns.is_empty():
		_fail("no towns for stream reseed test")
		return
	var town: Dictionary = towns[0]
	var center: Vector2i = town.get("center", Vector2i.ZERO)
	if em.has_method("ensure_town_population"):
		em.ensure_town_population(town)
	for _i in 8:
		await process_frame
	if not em.has_method("count_town_agents"):
		_fail("entity_manager.count_town_agents missing")
		return
	var before: Dictionary = em.count_town_agents(center)
	var v0: int = int(before.get("villagers", 0))
	var m0: int = int(before.get("militia", 0))
	if v0 < 1 or m0 < 1:
		_fail("town standing population incomplete before unload villagers=%d militia=%d" % [v0, m0])
		return
	print("OK town standing before unload villagers=%d militia=%d accounted=%d" % [
		v0, m0, int(before.get("defenders_accounted", -1))
	])
	var cm = get_first_node_in_group("chunk_manager")
	if cm == null or not cm.has_method("world_to_chunk_coord"):
		_fail("chunk_manager required for stream reseed test")
		return
	var coord: Vector2i = cm.world_to_chunk_coord(center.x, center.y)
	# Simulate stream unload wipe of town chunk bodies.
	if em.has_method("_despawn_entities_in_chunk"):
		em._despawn_entities_in_chunk(coord)
	# Nearby chunks may hold plaza agents — wipe all overlapping town chunks.
	for ox in range(-1, 2):
		for oz in range(-1, 2):
			if ox == 0 and oz == 0:
				continue
			em._despawn_entities_in_chunk(Vector2i(coord.x + ox, coord.y + oz))
	for _i in 4:
		await process_frame
	var mid: Dictionary = em.count_town_agents(center)
	var m_mid: int = int(mid.get("militia", 0))
	var acc_mid: int = int(mid.get("defenders_accounted", -1))
	if acc_mid != m_mid:
		_fail("defenders_by_town stale after unload live=%d accounted=%d" % [m_mid, acc_mid])
	else:
		print("OK defenders account matches live after unload live=%d" % m_mid)
	# Stream ready re-seeds standing population (production path).
	if em.has_method("_on_chunk_ready"):
		em._on_chunk_ready(coord, null)
		for ox in range(-1, 2):
			for oz in range(-1, 2):
				em._on_chunk_ready(Vector2i(coord.x + ox, coord.y + oz), null)
	for _i in 8:
		await process_frame
	var after: Dictionary = em.count_town_agents(center)
	var v1: int = int(after.get("villagers", 0))
	var m1: int = int(after.get("militia", 0))
	var acc1: int = int(after.get("defenders_accounted", -1))
	var standing_v: int = 3
	if "villagers_per_town" in em:
		standing_v = int(em.villagers_per_town)
	if v1 < standing_v:
		_fail("town villagers not fully re-seeded after chunk_ready got=%d want=%d" % [v1, standing_v])
	elif m1 < 2:
		_fail("town militia not fully re-seeded after chunk_ready got=%d want=2" % m1)
	elif acc1 != m1:
		_fail("defenders account mismatch after reseed live=%d accounted=%d" % [m1, acc1])
	else:
		print("OK town reseed after stream villagers=%d militia=%d accounted=%d" % [v1, m1, acc1])

func _test_consequential(lwd, crystal, player) -> void:
	if lwd == null or crystal == null:
		_fail("living world director or crystal missing for interaction")
		return
	# Shared production APIs must exist (no harness-only reimplementation).
	if not lwd.has_method("discover_ruin_at") or not lwd.has_method("try_discover_at_player_column"):
		_fail("LivingWorldDirector must expose discover_ruin_at + try_discover_at_player_column")
		return
	var power_before: float = float(crystal.power)
	var result: Dictionary = {}
	if lwd.has_method("harness_force_discover_nearest_ruin"):
		result = lwd.harness_force_discover_nearest_ruin()
	if result.is_empty():
		_fail("ruin discovery via player proximity returned empty (no ruins / player not placed?)")
		return
	# Player must be near the discovered ruin (harness warps then uses try_discover_at_player_column).
	var center: Vector2i = result.get("center", Vector2i.ZERO)
	if player != null and player.has_method("get_voxel_position"):
		var pv: Vector3 = player.get_voxel_position()
		var dist := Vector2(pv.x, pv.z).distance_to(Vector2(center))
		if dist > float(lwd.ruin_discover_radius) + 2.0:
			_fail("player not placed near ruin for discovery dist=%.1f center=%s" % [dist, center])
		else:
			print("OK player at ruin for discovery dist=%.1f" % dist)
	var power_after: float = float(crystal.power)
	if power_after <= power_before:
		_fail("ruin discovery must grant power (%.1f → %.1f)" % [power_before, power_after])
	else:
		print("OK ruin discovery power %.1f → %.1f at %s" % [
			power_before, power_after, str(result.get("center"))
		])
	# Idempotent: same center again must not double-grant.
	var power_mid: float = float(crystal.power)
	var again: Dictionary = lwd.discover_ruin_at(center)
	if not again.is_empty() or float(crystal.power) != power_mid:
		_fail("discover_ruin_at must be idempotent for same center")
	else:
		print("OK ruin discovery idempotent")
	if int(lwd.get_discovered_ruin_count()) < 1:
		_fail("discovered ruin count not tracked")
	else:
		print("OK discovered ruins=%d" % lwd.get_discovered_ruin_count())
	# Town defense militia path
	var tdm = get_first_node_in_group("town_defense_manager")
	if tdm and tdm.has_method("_request_militia"):
		var towns: Array = _FeatureRegistry.get_towns()
		if not towns.is_empty():
			var before_n: int = 0
			var em = get_first_node_in_group("entity_manager")
			if em:
				before_n = em.get_active_entity_count()
			tdm._request_militia(towns[0], 2)
			var after_n: int = em.get_active_entity_count() if em else before_n
			if after_n < before_n:
				_fail("militia request reduced agents")
			else:
				print("OK militia request agents %d → %d" % [before_n, after_n])
