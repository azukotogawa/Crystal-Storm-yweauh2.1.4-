extends SceneTree

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")
const _FeatureVisualLayer = preload("res://world/feature_visual_layer.gd")
const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _WorldVisuals = preload("res://world/world_visuals.gd")
const _WorldEntity = preload("res://entities/world_entity.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	_WorldSettings.apply_active(_WorldSettings.create_default())
	_FeatureRegistry.reset()

	var root3d := Node3D.new()
	root3d.name = "VisualPipelineRoot"
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

	var perf = Node.new()
	perf.set_script(load("res://systems/performance_service.gd"))
	perf.name = "PerformanceService"
	root3d.add_child(perf)
	perf.apply_preset(_PerformanceQualityConfig.Preset.HIGH)

	var cm = ChunkManager.new()
	cm.name = "ChunkManager"
	cm.add_to_group("chunk_manager")
	root3d.add_child(cm)

	var coord := Vector2i(0, 0)
	var view := ChunkView.new()
	view.chunk_data = ChunkData.new(coord, null)
	cm.chunks[coord] = view

	_FeatureRegistry.register_feature(2, 3, _WorldFeatureTypes.FeatureKind.TREE, {
		"plant_id": "tree",
		"growth_stage": 2,
	})
	_FeatureRegistry.register_feature(5, 5, _WorldFeatureTypes.FeatureKind.RUIN, {})

	await registry.ensure_ready()
	feat_layer.on_chunk_manager_ready(cm)
	await process_frame

	var veg_root := world_visuals.get_vegetation_root()
	var building_root := world_visuals.get_buildings_root()
	var veg_count := veg_root.get_child_count() if veg_root else 0
	var building_count := building_root.get_child_count() if building_root else 0
	if veg_count < 1:
		push_error("expected vegetation billboard under WorldVisuals/Vegetation, got %d" % veg_count)
		failed = true
	else:
		var anchor: Node3D = veg_root.get_child(0) as Node3D
		var sprite: Sprite3D = anchor.get_node_or_null("Billboard") as Sprite3D if anchor else null
		var bound := sprite != null and sprite.visible and (
			sprite.texture != null
			or (sprite.material_override is StandardMaterial3D
				and (sprite.material_override as StandardMaterial3D).albedo_texture != null)
		)
		if not bound:
			push_error("vegetation billboard missing texture/material binding")
			failed = true
		else:
			print("OK vegetation billboard child count=", veg_count)

	if building_count < 1:
		push_error("expected building mesh under WorldVisuals/Buildings, got %d" % building_count)
		failed = true
	else:
		var anchor_b: Node3D = building_root.get_child(0) as Node3D
		var mesh: MeshInstance3D = anchor_b.get_node_or_null("Mesh") as MeshInstance3D if anchor_b else null
		var mesh_ok := mesh != null and mesh.visible and mesh.material_override is StandardMaterial3D \
			and (mesh.material_override as StandardMaterial3D).albedo_texture != null
		if not mesh_ok:
			push_error("building mesh missing textured material_override")
			failed = true
		else:
			print("OK building mesh child count=", building_count)

	_EntityBrainRegistry.ensure_builtins()
	var brain := _EntityBrainRegistry.get_def(&"rabbit")
	var entities_root := world_visuals.get_entities_root()
	var entity: _WorldEntity = _WorldEntity.new()
	entities_root.add_child(entity)
	entity.setup(brain, Vector2i(4, 6), null, null, null)
	await process_frame
	var ws = _WorldSettings.get_active()
	var expected_x: float = ws.column_to_world(4.5)
	var expected_z: float = ws.column_to_world(6.5)
	if not is_equal_approx(entity.global_position.x, expected_x):
		push_error("entity X should use voxel scale: got %s expected %s" % [entity.global_position.x, expected_x])
		failed = true
	elif not is_equal_approx(entity.global_position.z, expected_z):
		push_error("entity Z should use voxel scale: got %s expected %s" % [entity.global_position.z, expected_z])
		failed = true
	else:
		print("OK entity world position scaled x=", entity.global_position.x, " z=", entity.global_position.z)

	var anchor_pos := _WorldVisualCoords.column_to_world_pos(2.5, 8.0, 3.5)
	if not is_equal_approx(anchor_pos.x, ws.column_to_world(2.5)):
		push_error("column_to_world_pos X mismatch")
		failed = true
	else:
		print("OK walkable anchor uses column_to_world")

	root3d.queue_free()
	if failed:
		quit(1)
	print("All visual pipeline tests OK")
	quit(0)