extends SceneTree


const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _PlantableRegistry = preload("res://world/plantable_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _CrystalCorruption = preload("res://crystal/crystal_corruption.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalSimulation = preload("res://crystal/crystal_simulation.gd")
const _CrystalManager = preload("res://crystal/crystal_manager.gd")
const _CrystalEvolution = preload("res://crystal/crystal_evolution.gd")
const _CrystalSpawnPoint = preload("res://crystal/crystal_spawn_point.gd")
const _SpawnPointDef = preload("res://config/spawn_point_def.gd")
const _GameConfig = preload("res://config/game_config.gd")
const _WorldEntity = preload("res://entities/world_entity.gd")
const _EntityBrain = preload("res://entities/entity_brain.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _EntityBrainConfig = preload("res://config/entity_brain_config.gd")
const _RelicManager = preload("res://relics/relic_manager.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_FeatureRegistry.reset()
	_CrystalCorruption.reset()
	_PlantableRegistry.reset()
	_PlantableRegistry.ensure_builtins()
	_EntityBrainRegistry.reset()
	_EntityBrainRegistry.ensure_builtins()
	var failed := false
	failed = _test_forest_corruption() or failed
	failed = _test_protected_cells() or failed
	failed = _test_scar_heals() or failed
	failed = _test_save_roundtrip() or failed
	failed = _test_deer_converts() or failed
	failed = _test_biome_pace() or failed
	failed = _test_relics_from_spawns() or failed
	failed = _test_break_starts_scar() or failed
	failed = _test_scar_tick_budget() or failed
	_FeatureRegistry.reset()
	_CrystalCorruption.reset()
	if failed:
		push_error("corruption checks failed")
		quit(1)
		return
	print("All corruption tests OK")
	quit(0)


func _test_forest_corruption() -> bool:
	var pos := Vector2i(8, 9)
	_FeatureRegistry.register_feature(pos.x, pos.y, _WorldFeatureTypes.FeatureKind.TREE, {
		"plant_id": "tree",
		"growth_stage": 2,
		"biome": "forest",
	})
	_FeatureRegistry.set_tile_override(pos.x, pos.y, VoxelTypes.HILLS)
	var before := _FeatureRegistry.get_feature(pos.x, pos.y)
	if not _CrystalCorruption.corrupt_absorbed_cell(pos, VoxelTypes.HILLS, before):
		push_error("forest cell should corrupt")
		return true
	var feat := _FeatureRegistry.get_feature(pos.x, pos.y)
	var tile := _FeatureRegistry.get_tile_override(pos.x, pos.y)
	if str(feat.get("plant_id", "")) != "shard_tree":
		push_error("tree should become shard_tree, got %s" % feat.get("plant_id", ""))
		return true
	if not _CrystalCorruption.is_corrupted_ground(tile) or tile == VoxelTypes.CRYSTAL_SCAR:
		push_error("forest ground should be a crystal tile, got %d" % tile)
		return true
	if str(feat.get("original_plant", "")) != "tree":
		push_error("original plant was not kept")
		return true
	print("OK forest tree -> shard_tree tile=%d" % tile)
	return false


func _test_protected_cells() -> bool:
	var ruin := Vector2i(3, 3)
	_FeatureRegistry.register_feature(ruin.x, ruin.y, _WorldFeatureTypes.FeatureKind.RUIN, {
		"kind": _WorldFeatureTypes.FeatureKind.RUIN,
	})
	if _CrystalCorruption.corrupt_absorbed_cell(ruin, VoxelTypes.STONE, _FeatureRegistry.get_feature(ruin.x, ruin.y)):
		push_error("ruin absorption must not transform the ruin")
		return true
	if int(_FeatureRegistry.get_feature(ruin.x, ruin.y).get("kind", -1)) != _WorldFeatureTypes.FeatureKind.RUIN:
		push_error("ruin feature was removed")
		return true
	if _FeatureRegistry.get_tile_override(ruin.x, ruin.y) >= 0:
		push_error("ruin ground override should stay untouched")
		return true
	var built := Vector2i(4, 4)
	_FeatureRegistry.register_feature(built.x, built.y, _WorldFeatureTypes.FeatureKind.NONE, {
		"player_built": true,
		"build_id": "stone_wall",
	})
	if _CrystalCorruption.corrupt_absorbed_cell(built, VoxelTypes.STONE, _FeatureRegistry.get_feature(built.x, built.y)):
		push_error("player building must survive absorption")
		return true
	print("OK ruin and player build stay put")
	return false


func _test_scar_heals() -> bool:
	var pos := Vector2i(8, 9)
	_CrystalCorruption.begin_scar(pos, 0.4)
	if _FeatureRegistry.get_tile_override(pos.x, pos.y) != VoxelTypes.CRYSTAL_SCAR:
		push_error("broken crystal should leave a scar tile")
		return true
	if _FeatureRegistry.get_feature(pos.x, pos.y).has("plant_id"):
		push_error("scar should hide the corrupted plant")
		return true
	var healed: Array = _CrystalCorruption.tick_scars(0.5, 8)
	if healed.is_empty():
		push_error("scar should heal once its timer ends")
		return true
	if _FeatureRegistry.get_tile_override(pos.x, pos.y) != VoxelTypes.HILLS:
		push_error("healed ground should restore the forest tile")
		return true
	var feat := _FeatureRegistry.get_feature(pos.x, pos.y)
	if str(feat.get("plant_id", "")) != "tree" or int(feat.get("growth_stage", -1)) != 0:
		push_error("healed forest should replant the tree at stage 0, got %s" % feat)
		return true
	print("OK scar heals to hills + tree stage 0")
	return false


func _test_save_roundtrip() -> bool:
	var pos := Vector2i(12, 4)
	_FeatureRegistry.register_feature(pos.x, pos.y, _WorldFeatureTypes.FeatureKind.BUSH, {
		"plant_id": "bush",
		"growth_stage": 1,
		"biome": "forest",
	})
	_CrystalCorruption.corrupt_absorbed_cell(pos, VoxelTypes.HILLS2, _FeatureRegistry.get_feature(pos.x, pos.y))
	var tile_before := _FeatureRegistry.get_tile_override(pos.x, pos.y)
	var blob := _FeatureRegistry.to_dict()
	_FeatureRegistry.reset()
	_CrystalCorruption.reset()
	_FeatureRegistry.apply_save_overlay(blob)
	var feat := _FeatureRegistry.get_feature(pos.x, pos.y)
	if str(feat.get("plant_id", "")) != "crystal_bush":
		push_error("save/load dropped corrupted plant, got %s" % feat.get("plant_id", ""))
		return true
	if _FeatureRegistry.get_tile_override(pos.x, pos.y) != tile_before:
		push_error("save/load dropped crystal ground")
		return true
	_CrystalCorruption.begin_scar(pos, 9.0)
	var scar_blob := _FeatureRegistry.to_dict()
	_FeatureRegistry.reset()
	_CrystalCorruption.reset()
	_FeatureRegistry.apply_save_overlay(scar_blob)
	_CrystalCorruption.reindex_scars()
	if _CrystalCorruption.scar_count() != 1:
		push_error("save/load should restore the scar index, count=%d" % _CrystalCorruption.scar_count())
		return true
	print("OK corruption and scar survive save/load")
	return false


func _test_deer_converts() -> bool:
	var deer_cfg = _EntityBrainRegistry.get_def(&"deer")
	var deer := _WorldEntity.new()
	deer.config = deer_cfg
	deer.entity_kind = &"deer"
	deer.health = deer_cfg.max_health
	deer.brain = _EntityBrain.new(deer_cfg)
	deer.brain.reset_at(Vector2i(2, 2))
	var tint_before: Color = deer._base_tint
	deer.advance_crystal_conversion(1.0, true)
	if str(deer.entity_kind) != "deer":
		push_error("deer should still be a deer partway through the change")
		deer.free()
		return true
	if deer._base_tint.is_equal_approx(tint_before):
		push_error("conversion should tint the deer before it finishes")
		deer.free()
		return true
	deer.advance_crystal_conversion(3.0, true)
	if str(deer.entity_kind) != "crystal_stag":
		push_error("deer in crystal should become crystal_stag, got %s" % deer.entity_kind)
		deer.free()
		return true
	if deer.config.disposition != _EntityBrainConfig.Disposition.AGGRESSIVE or deer.config.contact_damage <= 0.0:
		push_error("crystal_stag should be hostile")
		deer.free()
		return true
	deer.free()
	var villager := _WorldEntity.new()
	villager.config = _EntityBrainRegistry.get_def(&"town_villager")
	villager.entity_kind = &"town_villager"
	villager.advance_crystal_conversion(8.0, true)
	if str(villager.entity_kind) != "town_villager":
		push_error("villagers must not convert")
		villager.free()
		return true
	villager.free()
	if _CrystalCorruption.hostile_for_animal("bird") != "crystal_wisp":
		push_error("bird should convert to crystal_wisp")
		return true
	print("OK deer -> crystal_stag; villager stays")
	return false


func _test_biome_pace() -> bool:
	var cfg := _CrystalSimConfig.create_default()
	if cfg.biome_spread_mult("highland") >= cfg.biome_spread_mult("plains"):
		push_error("highland should spread slower than plains")
		return true
	if cfg.biome_reserve_mult("highland") <= cfg.biome_reserve_mult("plains"):
		push_error("highland should hold a deeper reserve than plains")
		return true
	if cfg.biome_mob_mult("plains") <= cfg.biome_mob_mult("mountain"):
		push_error("plains should field more mobs than mountains")
		return true
	if not is_equal_approx(cfg.biome_spread_mult("dense forest"), cfg.biome_spread_mult("forest")):
		push_error("dense forest should use the forest pace")
		return true
	var terrain := _CrystalTerrainQuery.new()
	terrain.sim_config = cfg
	terrain.test_biome_names[Vector2i(1, 1)] = "highland"
	var fluid := _CrystalFluidSim.new(cfg, terrain)
	fluid.set_depth(Vector2i(1, 1), 100.0, 0, false)
	var cap := cfg.max_depth * cfg.biome_reserve_mult("highland")
	if not is_equal_approx(fluid.get_depth_at(1, 1), cap):
		push_error("highland depth cap got %.2f want %.2f" % [fluid.get_depth_at(1, 1), cap])
		return true
	print("OK biome pace highland spread %.2f reserve %.2f" % [
		cfg.biome_spread_mult("highland"), cfg.biome_reserve_mult("highland"),
	])
	return false


func _test_relics_from_spawns() -> bool:
	var player := Node.new()
	player.name = "Player"
	player.add_to_group("player")
	var relics := _RelicManager.new()
	relics.name = "RelicManager"
	player.add_child(relics)
	root.add_child(player)
	var crystal := _CrystalManager.new()
	crystal.evolution = _CrystalEvolution.new()
	root.add_child(crystal)
	crystal.configure_evolution()
	for _i in 10:
		crystal.evolution.record_absorption(&"grass")
	if &"mason_glove" in relics.equipped:
		push_error("absorbing grass must not equip a relic")
		player.free()
		crystal.free()
		return true
	if _GameConfig.SINGLE_CRYSTAL:
		var released := _CrystalSpawnPoint.from_def(0, Vector2i(1, 1), _SpawnPointDef.make_released())
		crystal.harness_setup_spawns([released])
		if not crystal.damage_spawn(released.id, released.health) or released.active:
			push_error("destroying the crystal failed, active=%s health=%.1f" % [released.active, released.health])
			player.free()
			crystal.free()
			return true
		if &"mason_glove" not in relics.equipped:
			push_error("destroying the crystal should grant a relic, equipped=%s" % [relics.equipped])
			player.free()
			crystal.free()
			return true
		print("OK relic from crystal destroy, not from absorption")
	else:
		var spawn := _CrystalSpawnPoint.new(0, Vector2i(1, 1), 0, 40.0, false)
		crystal._on_spawn_destroyed(spawn)
		if &"mason_glove" not in relics.equipped:
			push_error("destroying a spawn should grant a relic, equipped=%s" % [relics.equipped])
			player.free()
			crystal.free()
			return true
		print("OK relic from spawn destroy, not from absorption")
	player.free()
	crystal.free()
	return false


func _test_break_starts_scar() -> bool:
	_CrystalCorruption.reset()
	var cfg := _CrystalSimConfig.create_default()
	cfg.scar_heal_seconds = 4.0
	var sim := _CrystalSimulation.new(cfg)
	var crystal := _CrystalManager.new()
	crystal.sim_config = cfg
	crystal._simulation = sim
	crystal._sim = sim.fluid
	var cell := Vector2i(20, 2)
	sim.set_depth(cell, 0.5, 0, false)
	var hit: Dictionary = crystal.damage_crystal_at(cell, 2.4)
	if not bool(hit.broken):
		push_error("pick should remove the shallow cell")
		crystal.free()
		return true
	if _FeatureRegistry.get_tile_override(cell.x, cell.y) != VoxelTypes.CRYSTAL_SCAR:
		push_error("breaking the mass should scar the ground")
		crystal.free()
		return true
	if _CrystalCorruption.scar_count() < 1:
		push_error("scar index should include the broken cell")
		crystal.free()
		return true
	print("OK breaking crystal starts a scar")
	crystal.free()
	return false


func _test_scar_tick_budget() -> bool:
	_FeatureRegistry.reset()
	_CrystalCorruption.reset()
	for i in 24:
		_CrystalCorruption.begin_scar(Vector2i(100 + i, 7), 30.0)
	var t0 := Time.get_ticks_usec()
	var healed: Array = _CrystalCorruption.tick_scars(0.016, 8)
	var busy := Time.get_ticks_usec() - t0
	if not healed.is_empty():
		push_error("fresh scars must not heal in one frame")
		return true
	if busy > 1500:
		push_error("scar tick too slow: %d us" % busy)
		return true
	_CrystalCorruption.reset()
	var t1 := Time.get_ticks_usec()
	_CrystalCorruption.tick_scars(0.016, 8)
	var idle := Time.get_ticks_usec() - t1
	if idle > 200:
		push_error("empty scar tick should be a no-op, %d us" % idle)
		return true
	print("OK scar tick busy=%dus idle=%dus" % [busy, idle])
	return false
