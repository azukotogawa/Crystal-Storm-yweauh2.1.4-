extends SceneTree
## P1 regression: near-player vegetation uses voxels; distant plants fall back to billboards.


const _FeatureVisualLayer = preload("res://world/feature_visual_layer.gd")
const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _PerfConfig = preload("res://config/performance_quality_config.gd")


class _FakePlayer extends Node3D:
	var voxel_position := Vector3(10.5, 8.0, 10.5)

	func get_voxel_position() -> Vector3:
		return voxel_position


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var layer_src := (load("res://world/feature_visual_layer.gd") as GDScript).source_code
	if "vegetation_billboard_distance_columns" not in layer_src:
		push_error("feature_visual_layer must honor vegetation_billboard_distance_columns")
		failed = true
	elif "_player_column_distance" not in layer_src:
		push_error("feature_visual_layer must gate voxels by player distance")
		failed = true
	else:
		print("OK feature_visual_layer distance gate source")

	var med = _PerfConfig.apply_preset(1)
	if med.vegetation_billboard_distance_columns < 16:
		push_error("MEDIUM vegetation_billboard_distance_columns too small")
		failed = true
	else:
		print("OK MEDIUM vegetation_billboard_distance_columns=%d" % med.vegetation_billboard_distance_columns)

	var holder := Node.new()
	holder.name = "TestRoot"
	root.add_child(holder)

	var registry := _GameVisualRegistry.new()
	registry.name = "GameVisualRegistry"
	registry.add_to_group("game_visual_registry")
	registry.feature_billboards_enabled = true
	registry.vegetation_voxel_models_enabled = true
	registry.vegetation_billboard_distance_columns = 8
	holder.add_child(registry)

	var player := _FakePlayer.new()
	player.name = "Player"
	player.add_to_group("player")
	player.voxel_position = Vector3(10.5, 8.0, 10.5)
	holder.add_child(player)

	var layer := _FeatureVisualLayer.new()
	layer.name = "FeatureVisualLayer"
	holder.add_child(layer)
	await process_frame

	var near_wx := 10
	var near_wz := 10
	var far_wx := 30
	var far_wz := 30
	if layer._use_voxel_vegetation(near_wx, near_wz):
		print("OK near vegetation uses voxel at (%d,%d)" % [near_wx, near_wz])
	else:
		push_error("near vegetation should use voxel within distance gate")
		failed = true
	if not layer._use_voxel_vegetation(far_wx, far_wz):
		print("OK far vegetation falls back to billboard at (%d,%d)" % [far_wx, far_wz])
	else:
		push_error("far vegetation should use billboard beyond distance gate")
		failed = true

	registry.vegetation_billboard_distance_columns = 0
	if not layer._use_voxel_vegetation(far_wx, far_wz):
		push_error("distance<=0 should always use voxels when enabled")
		failed = true
	else:
		print("OK distance<=0 keeps voxel models")

	holder.queue_free()
	if failed:
		print("Vegetation billboard distance tests FAILED")
		quit(1)
		return
	print("All vegetation billboard distance tests OK")
	quit(0)