class_name GameConfig
extends Resource

const _WorldGenConfig = preload("res://config/world_gen_config.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _BuildableDef = preload("res://config/buildable_def.gd")
const _PlantableDef = preload("res://config/plantable_def.gd")
const _EntityBrainConfig = preload("res://config/entity_brain_config.gd")
const _EnemySpawnDef = preload("res://config/enemy_spawn_def.gd")
const _AbsorptionUnlockDef = preload("res://config/absorption_unlock_def.gd")
const _RelicDef = preload("res://config/relic_def.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _CombatDef = preload("res://config/combat_def.gd")
const _SpawnPointDef = preload("res://config/spawn_point_def.gd")
const _SpawnPointRegistry = preload("res://config/spawn_point_registry.gd")
const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")

@export var world_settings: Resource
@export var world_gen: Resource
@export var crystal_sim: Resource

@export_group("Combat")
@export var combat: Resource

@export_group("Performance")
@export var performance: Resource

@export_group("Run Rules")
## Near crystal fluid → ASSAULT (fight). Farther → MAZE (dig/build prep).
@export var assault_distance: float = 48.0
@export var maze_min_distance: float = 72.0
@export var crystal_damage_per_second: float = 28.0
@export var town_fall_depth: float = 0.45

@export_group("Content")
@export var buildables: Array = []
@export var plantables: Array = []
@export var entity_brains: Array = []
@export var enemy_spawns: Array = []
@export var spawn_points: Array = []
@export var absorption_unlocks: Array = []
@export var relics: Array = []


func ensure_defaults() -> void:
	if world_settings == null:
		if ResourceLoader.exists("res://config/default_world_settings.tres"):
			world_settings = load("res://config/default_world_settings.tres")
		else:
			world_settings = _WorldSettings.create_default()
	elif not world_settings is _WorldSettings:
		world_settings = _WorldSettings.create_default()
	if world_gen == null:
		world_gen = _WorldGenConfig.create_default()
	elif not world_gen is _WorldGenConfig:
		world_gen = _WorldGenConfig.create_default()
	if crystal_sim == null:
		crystal_sim = _CrystalSimConfig.create_default()
	elif not crystal_sim is _CrystalSimConfig:
		crystal_sim = _CrystalSimConfig.create_default()
	if combat == null:
		combat = _CombatDef.create_default()
	elif not combat is _CombatDef:
		combat = _CombatDef.create_default()
	if spawn_points.is_empty():
		_SpawnPointRegistry.ensure_builtins()
		spawn_points = [
			_SpawnPointRegistry.get_def(&"origin_boss"),
			_SpawnPointRegistry.get_def(&"ruin_miniboss"),
			_SpawnPointRegistry.get_def(&"artifact_node"),
		]
	if performance == null:
		performance = _PerformanceQualityConfig.create_default()
	elif not performance is _PerformanceQualityConfig:
		performance = _PerformanceQualityConfig.create_default()


static func create_default() -> GameConfig:
	var cfg := GameConfig.new()
	cfg.ensure_defaults()
	return cfg