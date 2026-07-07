class_name ConfigService
extends Node

const _GameConfig = preload("res://config/game_config.gd")
const _WorldGenConfig = preload("res://config/world_gen_config.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _PlantableRegistry = preload("res://world/plantable_registry.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _EnemySpawnRegistry = preload("res://entities/enemy_spawn_registry.gd")
const _SpawnPointRegistry = preload("res://config/spawn_point_registry.gd")
const _PerformanceService = preload("res://systems/performance_service.gd")
const _RelicRegistry = preload("res://relics/relic_registry.gd")
const _ConfigJsonIO = preload("res://systems/config_json_io.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

signal config_loaded

@export var game_config: _GameConfig
@export var auto_export_json_on_ready: bool = false
@export var json_export_path: String = "user://crystal_storm_config.json"

var world_settings
var world_gen: _WorldGenConfig
var crystal_sim: _CrystalSimConfig


func _enter_tree() -> void:
	add_to_group("config_service")


func _ready() -> void:
	if game_config == null:
		game_config = _GameConfig.create_default()
	game_config.ensure_defaults()
	world_settings = game_config.world_settings as _WorldSettings
	_WorldSettings.apply_active(world_settings)
	world_gen = game_config.world_gen
	crystal_sim = game_config.crystal_sim
	_BuildingRegistry.ensure_builtins()
	_PlantableRegistry.ensure_builtins()
	_EntityBrainRegistry.ensure_builtins()
	_EnemySpawnRegistry.ensure_builtins()
	_SpawnPointRegistry.ensure_builtins()
	_RelicRegistry.ensure_builtins()
	if game_config.buildables.size() > 0:
		_BuildingRegistry.register_all(game_config.buildables)
	if game_config.plantables.size() > 0:
		_PlantableRegistry.register_all(game_config.plantables)
	if game_config.entity_brains.size() > 0:
		_EntityBrainRegistry.register_all(game_config.entity_brains)
	if game_config.enemy_spawns.size() > 0:
		_EnemySpawnRegistry.register_all(game_config.enemy_spawns)
	if game_config.spawn_points.size() > 0:
		_SpawnPointRegistry.register_all(game_config.spawn_points)
	if game_config.relics.size() > 0:
		_RelicRegistry.register_all(game_config.relics)
	config_loaded.emit()
	_push_to_systems()
	if auto_export_json_on_ready:
		export_to_json(json_export_path)


func _push_to_systems() -> void:
	if world_settings:
		_WorldSettings.apply_active(world_settings)
		TerrainRamps.invalidate_mesh_cache()

	var world := get_tree().get_first_node_in_group("world") as InfiniteNoiseWorld
	if world and world.has_method("apply_world_settings"):
		world.apply_world_settings(world_settings)
	if world and world.has_method("apply_world_config"):
		world.apply_world_config(world_gen)

	var crystal := get_tree().get_first_node_in_group("crystal_manager") as CrystalManager
	if crystal and crystal.has_method("apply_sim_config"):
		crystal.apply_sim_config(crystal_sim)
	if crystal and crystal.has_method("configure_evolution"):
		crystal.configure_evolution()

	var game_manager := get_tree().get_first_node_in_group("game_manager") as GameManager
	if game_manager and game_manager.has_method("apply_game_config"):
		game_manager.apply_game_config(game_config)

	var town_mgr := get_tree().get_first_node_in_group("town_manager")
	if town_mgr and world_gen and town_mgr.has_method("apply_world_config"):
		town_mgr.apply_world_config(world_gen)

	var chunk_mgr := get_tree().get_first_node_in_group("chunk_manager")
	if chunk_mgr and world_gen and chunk_mgr.has_method("apply_world_gen_config"):
		chunk_mgr.apply_world_gen_config(world_gen)

	var growth_mgr := get_tree().get_first_node_in_group("vegetation_growth_manager")
	if growth_mgr and crystal_sim and growth_mgr.has_method("apply_sim_config"):
		growth_mgr.apply_sim_config(crystal_sim)

	var terrain_editor := get_tree().get_first_node_in_group("terrain_editor")
	if terrain_editor and crystal_sim and terrain_editor.has_method("apply_sim_config"):
		terrain_editor.apply_sim_config(crystal_sim)

	var perf_svc = get_tree().get_first_node_in_group("performance_service")
	if perf_svc and game_config and game_config.performance:
		perf_svc.apply_quality(game_config.performance)

	var veg_mgr := get_tree().get_first_node_in_group("vegetation_manager")
	if veg_mgr and world_gen:
		if "grass_density" in veg_mgr:
			veg_mgr.grass_density = world_gen.grass_density
		if "tree_density" in veg_mgr:
			veg_mgr.tree_density = world_gen.tree_density
		if "bush_density" in veg_mgr:
			veg_mgr.bush_density = world_gen.bush_density
		if "scatter_attempts" in veg_mgr:
			veg_mgr.scatter_attempts = world_gen.vegetation_scatter_attempts


func get_buildable(id: StringName):
	for def in game_config.buildables:
		if def and def.id == id:
			return def
	return null


func get_relic(id: StringName):
	for def in game_config.relics:
		if def and def.id == id:
			return def
	return null


func get_entity_brain(id: StringName):
	for def in game_config.entity_brains:
		if def and def.id == id:
			return def
	return null


func export_to_json(path: String = "") -> Error:
	if path == "":
		path = json_export_path
	return _ConfigJsonIO.export_game_config(game_config, path)


func import_from_json(path: String = "") -> void:
	if path == "":
		path = json_export_path
	var imported = _ConfigJsonIO.import_game_config(path)
	if imported:
		game_config = imported
		game_config.ensure_defaults()
		world_settings = game_config.world_settings as _WorldSettings
		world_gen = game_config.world_gen
		crystal_sim = game_config.crystal_sim
		_push_to_systems()
		config_loaded.emit()