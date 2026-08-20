extends SceneTree
## Regression: world_features bootstrap must not await ChunkManager-bound visual commit.


const _WorldFeatures = preload("res://world/world_features.gd")
const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _ConfigService = preload("res://systems/config_service.gd")
const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var root3d := Node3D.new()
	root.add_child(root3d)

	var cfg := _ConfigService.new()
	cfg.name = "ConfigService"
	root3d.add_child(cfg)
	await process_frame

	var perf = load("res://systems/performance_service.gd").new()
	perf.name = "PerformanceService"
	root3d.add_child(perf)
	perf.apply_preset(_PerformanceQualityConfig.Preset.MEDIUM)
	await perf.ensure_ready()

	var registry = _GameVisualRegistry.new()
	registry.name = "GameVisualRegistry"
	root3d.add_child(registry)

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.name = "World"
	world.add_to_group("world")
	root3d.add_child(world)

	var features = _WorldFeatures.new()
	features.name = "WorldFeatures"
	root3d.add_child(features)

	var frames := 0
	while frames < 600:
		await process_frame
		frames += 1
		if registry.textures_ready() and features.bootstrap_complete:
			break

	if not registry.textures_ready():
		push_error("registry textures did not load")
		failed = true
	if not features.bootstrap_complete:
		push_error("world_features bootstrap did not complete (deadlock?)")
		failed = true

	var cm = ChunkManager.new()
	cm.name = "ChunkManager"
	cm.add_to_group("chunk_manager")
	root3d.add_child(cm)
	features.on_chunk_manager_ready(cm)
	await process_frame
	await process_frame

	if not registry.is_ready():
		push_error("registry visuals not committed after on_chunk_manager_ready")
		failed = true
	else:
		print("OK bootstrap completes before ChunkManager; visuals commit on bind")

	if cm.has_method("release_all_chunks_for_teardown"):
		cm.release_all_chunks_for_teardown()
	if failed:
		_ProbeExit.finish_tree(self, 1, "Bootstrap deadlock tests FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "All bootstrap deadlock tests OK")