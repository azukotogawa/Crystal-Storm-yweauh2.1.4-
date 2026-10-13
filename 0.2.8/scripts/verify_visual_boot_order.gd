extends SceneTree
## Regression: visuals must not commit before ChunkManager late-bind.


const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _EntityManager = preload("res://entities/entity_manager.gd")
const _WorldVisuals = preload("res://world/world_visuals.gd")
const _FeatureVisualLayer = preload("res://world/feature_visual_layer.gd")
const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var root3d := Node3D.new()
	root.add_child(root3d)

	var world_visuals = _WorldVisuals.new()
	world_visuals.name = "WorldVisuals"
	root3d.add_child(world_visuals)

	var registry = _GameVisualRegistry.new()
	registry.name = "GameVisualRegistry"
	root3d.add_child(registry)

	var feat_layer = _FeatureVisualLayer.new()
	feat_layer.name = "FeatureVisualLayer"
	world_visuals.add_child(feat_layer)

	var entity_mgr = _EntityManager.new()
	entity_mgr.name = "EntityManager"
	root3d.add_child(entity_mgr)

	var cm = ChunkManager.new()
	cm.name = "ChunkManager"

	for _i in 120:
		await process_frame
		if registry.textures_ready():
			break
	if not registry.textures_ready():
		push_error("registry texture bundle failed to initialize")
		failed = true
	elif registry.is_ready():
		push_error("registry should not commit visuals before ChunkManager bind")
		failed = true
	else:
		print("OK registry textures load without ChunkManager; visuals commit on bind")

	cm.add_to_group("chunk_manager")
	root3d.add_child(cm)
	registry.on_chunk_manager_ready(cm)
	entity_mgr.on_chunk_manager_ready(cm)
	world_visuals.on_chunk_manager_ready(cm)
	await process_frame

	if not registry.is_ready():
		push_error("registry should be ready after on_chunk_manager_ready")
		failed = true
	elif entity_mgr.chunk_manager != cm:
		push_error("EntityManager chunk_manager not bound")
		failed = true
	else:
		print("OK visual boot order: late-bind before visuals_ready")

	var med := _PerformanceQualityConfig.apply_preset(_PerformanceQualityConfig.Preset.MEDIUM)
	if not med.entity_sprites_enabled or not med.feature_billboards_enabled:
		push_error("MEDIUM preset must enable entity sprites and billboards")
		failed = true
	elif not med.entity_voxel_models_enabled or not med.vegetation_voxel_models_enabled:
		push_error("MEDIUM preset must enable voxel entity/vegetation models")
		failed = true
	else:
		print("OK MEDIUM preset enables sprites, billboards, and voxel models")

	var probe := Sprite3D.new()
	registry.configure_sprite3d(probe, registry.get_sprite_texture("rabbit"))
	var expected_px: float = registry.sprite_pixel_size()
	if not is_equal_approx(probe.pixel_size, expected_px):
		push_error("sprite pixel_size should scale with voxel_size got %.4f expected %.4f" % [
			probe.pixel_size, expected_px
		])
		failed = true
	elif not probe.visible or probe.material_override == null:
		push_error("configure_sprite3d must assign material and visibility")
		failed = true
	else:
		print("OK world-scaled sprite pixel_size=", probe.pixel_size)

	probe.free()
	root3d.queue_free()

	if failed:
		quit(1)
	print("All visual boot order tests OK")
	quit(0)