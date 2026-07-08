extends SceneTree
## Regression: registry must bind textures to Sprite3D material_override and building meshes.


const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _FeatureVisualLayer = preload("res://world/feature_visual_layer.gd")
const _WorldVisuals = preload("res://world/world_visuals.gd")
const _WorldEntity = preload("res://entities/world_entity.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")


func _init() -> void:
	call_deferred("_run")


func _sprite_bound(sprite: Sprite3D) -> bool:
	if sprite == null or not sprite.visible:
		return false
	if sprite.texture != null:
		return true
	var mat := sprite.material_override
	return mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null


func _run() -> void:
	var failed := false
	_FeatureRegistry.reset()

	var root3d := Node3D.new()
	root.add_child(root3d)

	var world_visuals = _WorldVisuals.new()
	root3d.add_child(world_visuals)

	var registry = _GameVisualRegistry.new()
	root3d.add_child(registry)

	var feat_layer = _FeatureVisualLayer.new()
	world_visuals.add_child(feat_layer)

	var perf = load("res://systems/performance_service.gd").new()
	root3d.add_child(perf)
	perf.apply_preset(_PerformanceQualityConfig.Preset.MEDIUM)
	await perf.ensure_ready()

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.add_to_group("world")
	root3d.add_child(world)

	var cm = ChunkManager.new()
	cm.add_to_group("chunk_manager")
	root3d.add_child(cm)
	var coord := Vector2i(0, 0)
	var view := ChunkView.new()
	view.chunk_data = ChunkData.new(coord, world)
	cm.chunks[coord] = view

	_FeatureRegistry.register_feature(2, 3, _WorldFeatureTypes.FeatureKind.TREE, {
		"plant_id": "bush",
		"growth_stage": 1,
	})
	_FeatureRegistry.register_feature(5, 5, _WorldFeatureTypes.FeatureKind.RUIN, {})

	feat_layer.on_chunk_manager_ready(cm)
	world_visuals.on_chunk_manager_ready(cm)
	await registry.post_bootstrap_refresh()
	await process_frame

	var veg_root = world_visuals.get_vegetation_root()
	var veg_ok := false
	if veg_root and veg_root.get_child_count() > 0:
		var anchor: Node3D = veg_root.get_child(0) as Node3D
		var veg_prop: Node3D = anchor.get_node_or_null("VoxelProp") as Node3D if anchor else null
		var veg_sprite: Sprite3D = anchor.get_node_or_null("Billboard") as Sprite3D if anchor else null
		veg_ok = veg_prop != null and veg_prop.get_child_count() > 0
		if not veg_ok:
			veg_ok = _sprite_bound(veg_sprite)
	if not veg_ok:
		push_error("bush vegetation missing voxel model or textured billboard")
		failed = true
	else:
		print("OK bush vegetation visual bound")

	var building_root = world_visuals.get_buildings_root()
	var bmesh: MeshInstance3D = null
	if building_root and building_root.get_child_count() > 0:
		var anchor_b: Node3D = building_root.get_child(0) as Node3D
		bmesh = anchor_b.get_node_or_null("Mesh") as MeshInstance3D if anchor_b else null
	if bmesh == null or not bmesh.visible or not bmesh.material_override is StandardMaterial3D \
			or (bmesh.material_override as StandardMaterial3D).albedo_texture == null:
		push_error("ruin building mesh missing textured material_override")
		failed = true
	else:
		print("OK ruin building mesh material bound")

	_EntityBrainRegistry.ensure_builtins()
	var brain = _EntityBrainRegistry.get_def(&"rabbit")
	var entity: _WorldEntity = _WorldEntity.new()
	world_visuals.get_entities_root().add_child(entity)
	entity.setup(brain, Vector2i(4, 6), world, cm, null)
	registry.refresh_all()
	await process_frame
	registry.apply_performance_config(perf.quality)
	entity.refresh_visual()
	await process_frame
	var evoxel: Node3D = entity.get_node_or_null("VoxelProp") as Node3D
	var esprite: Sprite3D = entity.get_node_or_null("Sprite3D") as Sprite3D
	var entity_ok := evoxel != null and evoxel.visible and evoxel.get_child_count() > 0
	if not entity_ok:
		entity_ok = _sprite_bound(esprite)
	if not entity_ok:
		push_error("rabbit entity missing voxel model or textured sprite after refresh_all")
		failed = true
	else:
		print("OK rabbit entity visual bound (voxel=%s)" % (evoxel != null and evoxel.visible))

	var spawn_tex: Texture2D = registry.get_spawn_texture(false)
	if spawn_tex == null:
		push_error("spawn_miniboss texture missing under MEDIUM preset")
		failed = true
	else:
		print("OK spawn marker texture available")

	cm.release_all_chunks_for_teardown() if cm.has_method("release_all_chunks_for_teardown") else null
	for _i in 20:
		await process_frame
	root3d.queue_free()

	if failed:
		quit(1)
	print("All visual texture binding tests OK")
	quit(0)