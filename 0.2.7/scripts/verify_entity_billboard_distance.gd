extends SceneTree
## P1 regression: near-player entities use voxels; distant entities fall back to sprites.


const _VisualProximity = preload("res://helpers/visual_proximity.gd")
const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _PerfConfig = preload("res://config/performance_quality_config.gd")
const _WorldEntity = preload("res://entities/world_entity.gd")


class _FakePlayer extends Node3D:
	var voxel_position := Vector3(10.5, 8.0, 10.5)

	func get_voxel_position() -> Vector3:
		return voxel_position


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var entity_src := (load("res://entities/world_entity.gd") as GDScript).source_code
	if "entity_billboard_distance_columns" not in entity_src:
		push_error("world_entity must honor entity_billboard_distance_columns")
		failed = true
	elif "visual_proximity.gd" not in entity_src:
		push_error("world_entity must use visual_proximity distance gate")
		failed = true
	else:
		print("OK world_entity distance gate source")

	var enemy_src := (load("res://entities/crystal_enemy.gd") as GDScript).source_code
	if "_use_entity_voxel_model" not in enemy_src:
		push_error("crystal_enemy must gate voxel models by distance")
		failed = true
	else:
		print("OK crystal_enemy distance gate source")

	var med = _PerfConfig.apply_preset(1)
	if med.entity_billboard_distance_columns < 16:
		push_error("MEDIUM entity_billboard_distance_columns too small")
		failed = true
	else:
		print("OK MEDIUM entity_billboard_distance_columns=%d" % med.entity_billboard_distance_columns)

	var holder := Node.new()
	holder.name = "TestRoot"
	root.add_child(holder)

	var registry := _GameVisualRegistry.new()
	registry.name = "GameVisualRegistry"
	registry.add_to_group("game_visual_registry")
	registry.entity_voxel_models_enabled = true
	registry.entity_billboard_distance_columns = 8
	holder.add_child(registry)

	var player := _FakePlayer.new()
	player.name = "Player"
	player.add_to_group("player")
	player.voxel_position = Vector3(10.5, 8.0, 10.5)
	holder.add_child(player)

	var entity := _WorldEntity.new()
	entity.name = "Rabbit"
	entity.home_cell = Vector2i(10, 10)
	holder.add_child(entity)
	await process_frame

	if entity._use_entity_voxel_model(registry, Vector2i(10, 10)):
		print("OK near entity uses voxel at (10,10)")
	else:
		push_error("near entity should use voxel within distance gate")
		failed = true
	if not entity._use_entity_voxel_model(registry, Vector2i(30, 30)):
		print("OK far entity falls back to sprite at (30,30)")
	else:
		push_error("far entity should use sprite beyond distance gate")
		failed = true

	registry.entity_billboard_distance_columns = 0
	if not entity._use_entity_voxel_model(registry, Vector2i(30, 30)):
		push_error("distance<=0 should always use voxels when enabled")
		failed = true
	else:
		print("OK distance<=0 keeps entity voxel models")

	holder.queue_free()
	if failed:
		print("Entity billboard distance tests FAILED")
		quit(1)
		return
	print("All entity billboard distance tests OK")
	quit(0)