extends SceneTree
## Verifies late ChunkManager binding for terrain editing and entity streaming.

const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _EntityManager = preload("res://entities/entity_manager.gd")
const _WorldFeatures = preload("res://world/world_features.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ConfigService = preload("res://systems/config_service.gd")


func _init() -> void:
	var failed := false

	var terrain := _TerrainEditor.new()
	terrain.chunk_manager = null
	var cm := _ChunkManager.new()
	terrain.bind_chunk_manager(cm)
	if terrain.chunk_manager != cm:
		push_error("TerrainEditor.bind_chunk_manager failed")
		failed = true
	else:
		print("OK TerrainEditor.bind_chunk_manager")

	var entity_mgr := _EntityManager.new()
	entity_mgr.on_chunk_manager_ready(cm)
	if entity_mgr.chunk_manager != cm:
		push_error("EntityManager.on_chunk_manager_ready failed")
		failed = true
	else:
		print("OK EntityManager.on_chunk_manager_ready")

	var features = load("res://world/world_features.gd").new()
	if features == null or not features.has_method("on_chunk_manager_ready"):
		push_error("world_features missing on_chunk_manager_ready")
		failed = true
	else:
		print("OK world_features on_chunk_manager_ready API")
	features.free()

	var cfg := _ConfigService.new()
	var game_cfg = load("res://config/game_config.gd").create_default()
	cfg.game_config = game_cfg
	cfg.world_gen = game_cfg.world_gen
	cfg.on_chunk_manager_ready(cm)
	if cm.ramp_placement_chance != cfg.world_gen.ramp_placement_chance:
		push_error("ConfigService did not apply ramp_placement_chance to ChunkManager")
		failed = true
	else:
		print("OK ConfigService.on_chunk_manager_ready ramp sync=", cm.ramp_placement_chance)

	terrain.free()
	entity_mgr.free()
	cm.free()
	cfg.free()

	if failed:
		quit(1)
	print("All chunk bootstrap tests OK")
	quit(0)