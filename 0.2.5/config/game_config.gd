class_name GameConfig
extends Resource

const _WorldGenConfig = preload("res://config/world_gen_config.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _BuildableDef = preload("res://config/buildable_def.gd")
const _RelicDef = preload("res://config/relic_def.gd")
const _EntityBrainConfig = preload("res://config/entity_brain_config.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

@export var world_settings: Resource
@export var world_gen: Resource
@export var crystal_sim: Resource

@export_group("Run Rules")
@export var assault_distance: float = 140.0
@export var maze_min_distance: float = 200.0
@export var crystal_damage_per_second: float = 28.0
@export var town_fall_depth: float = 0.45

@export_group("Content")
@export var buildables: Array = []
@export var relics: Array = []
@export var entity_brains: Array = []


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


static func create_default() -> GameConfig:
	var cfg := GameConfig.new()
	cfg.ensure_defaults()
	return cfg