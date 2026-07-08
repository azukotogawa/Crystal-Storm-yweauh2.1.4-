class_name FeatureVisualLayer
extends Node3D

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _PlantableRegistry = preload("res://world/plantable_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")

var chunk_manager: ChunkManager
var world: InfiniteNoiseWorld
var _crystal: CrystalManager
var _registry: _GameVisualRegistry
var _vegetation_root: Node3D
var _buildings_root: Node3D
var _nodes_by_chunk: Dictionary = {}
var _nodes_by_cell: Dictionary = {}


func _ready() -> void:
	add_to_group("feature_visual_layer")
	_PlantableRegistry.ensure_builtins()
	call_deferred("_bind")


func _bind() -> void:
	_bind_layer_roots()
	world = get_tree().get_first_node_in_group("world")
	_crystal = get_tree().get_first_node_in_group("crystal_manager")
	_registry = get_tree().get_first_node_in_group("game_visual_registry")
	if _registry and _registry.has_method("ensure_ready"):
		await _registry.ensure_ready()
	var world_features = get_tree().get_first_node_in_group("world_features")
	if world_features and world_features.has_method("ensure_ready"):
		await world_features.ensure_ready()
	await _await_chunk_manager()
	_bind_chunk_streaming()
	var growth = get_tree().get_first_node_in_group("vegetation_growth_manager")
	if growth and growth.has_signal("growth_stage_changed"):
		if not growth.growth_stage_changed.is_connected(_on_growth_stage_changed):
			growth.growth_stage_changed.connect(_on_growth_stage_changed)


func on_chunk_manager_ready(cm: ChunkManager) -> void:
	if cm == null:
		return
	chunk_manager = cm
	_bind_layer_roots()
	_bind_chunk_streaming()
	if _registry and _registry.feature_billboards_enabled:
		repopulate_all()


func _await_chunk_manager() -> void:
	while chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
		if chunk_manager != null:
			break
		await get_tree().process_frame


func _bind_chunk_streaming() -> void:
	if chunk_manager == null:
		return
	if chunk_manager.has_signal("chunk_ready") and not chunk_manager.chunk_ready.is_connected(_on_chunk_ready):
		chunk_manager.chunk_ready.connect(_on_chunk_ready)
	if chunk_manager.has_signal("chunk_unloaded") and not chunk_manager.chunk_unloaded.is_connected(_on_chunk_unloaded):
		chunk_manager.chunk_unloaded.connect(_on_chunk_unloaded)
	if _registry and _registry.feature_billboards_enabled:
		for coord in chunk_manager.chunks.keys():
			_on_chunk_ready(coord, null)


func _bind_layer_roots() -> void:
	var visuals = get_tree().get_first_node_in_group("world_visuals_root")
	if visuals:
		if visuals.has_method("get_vegetation_root"):
			_vegetation_root = visuals.get_vegetation_root()
		if visuals.has_method("get_buildings_root"):
			_buildings_root = visuals.get_buildings_root()
	if _vegetation_root == null:
		_vegetation_root = get_node_or_null("../Vegetation") as Node3D
	if _buildings_root == null:
		_buildings_root = get_node_or_null("../Buildings") as Node3D
	if _vegetation_root == null:
		_vegetation_root = Node3D.new()
		_vegetation_root.name = "Vegetation"
		add_child(_vegetation_root)
	if _buildings_root == null:
		_buildings_root = Node3D.new()
		_buildings_root.name = "Buildings"
		add_child(_buildings_root)


func repopulate_all() -> void:
	_bind_layer_roots()
	if _registry == null:
		_registry = get_tree().get_first_node_in_group("game_visual_registry")
	if world == null:
		world = get_tree().get_first_node_in_group("world")
	if _crystal == null:
		_crystal = get_tree().get_first_node_in_group("crystal_manager")
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	if _registry == null or not _registry.feature_billboards_enabled or chunk_manager == null:
		return
	for coord in chunk_manager.chunks.keys():
		_on_chunk_ready(coord, null)


func apply_performance_config(cfg) -> void:
	if cfg == null:
		return
	if _registry:
		_registry.apply_performance_config(cfg)
	if "feature_billboards_enabled" in cfg and not bool(cfg.feature_billboards_enabled):
		_clear_all()
	elif _registry and _registry.feature_billboards_enabled and chunk_manager:
		for coord in chunk_manager.chunks.keys():
			_on_chunk_ready(coord, null)


func _on_chunk_ready(coord: Vector2i, _data: ChunkData) -> void:
	if _registry == null or not _registry.feature_billboards_enabled:
		return
	_populate_chunk(coord)


func _on_chunk_unloaded(coord: Vector2i) -> void:
	_clear_chunk(coord)


func _on_growth_stage_changed(world_pos: Vector2i, plant_id: StringName, stage: int) -> void:
	if _registry == null or not _registry.feature_billboards_enabled:
		return
	var anchor: Node3D = _nodes_by_cell.get(world_pos)
	if anchor == null or not is_instance_valid(anchor):
		return
	var sprite: Sprite3D = anchor.get_node_or_null("Billboard") as Sprite3D
	if sprite == null:
		return
	var col_x := float(world_pos.x) + 0.5
	var col_z := float(world_pos.y) + 0.5
	anchor.position = _anchor_pos(col_x, col_z, _sprite_height_offset_for_plant(plant_id, stage))
	_apply_plant_texture(sprite, plant_id, stage)


func _populate_chunk(coord: Vector2i) -> void:
	_clear_chunk(coord)
	var budget := _registry.max_feature_billboards_per_chunk
	var placed := 0
	var min_x := coord.x * ChunkData.SIZE
	var min_z := coord.y * ChunkData.SIZE
	var chunk_nodes: Array = []

	for x in ChunkData.SIZE:
		for z in ChunkData.SIZE:
			if placed >= budget:
				break
			var wx := min_x + x
			var wz := min_z + z
			var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
			if feat.is_empty():
				continue
			var anchor := _make_feature_anchor(wx, wz, feat)
			if anchor == null:
				continue
			var parent := _parent_for_feature(feat)
			parent.add_child(anchor)
			chunk_nodes.append(anchor)
			_nodes_by_cell[Vector2i(wx, wz)] = anchor
			placed += 1
		if placed >= budget:
			break

	_nodes_by_chunk[coord] = chunk_nodes


func _parent_for_feature(feat: Dictionary) -> Node3D:
	if feat.has("plant_id"):
		return _vegetation_root
	var kind: int = int(feat.get("kind", _WorldFeatureTypes.FeatureKind.NONE))
	match kind:
		_WorldFeatureTypes.FeatureKind.RUIN, _WorldFeatureTypes.FeatureKind.TOWN_BUILDING:
			return _buildings_root
		_:
			return _buildings_root


func _make_feature_anchor(wx: int, wz: int, feat: Dictionary) -> Node3D:
	var col_x := float(wx) + 0.5
	var col_z := float(wz) + 0.5

	if feat.has("plant_id"):
		var plant_id: StringName = StringName(str(feat.plant_id))
		var stage: int = int(feat.get("growth_stage", 0))
		return _make_vegetation_anchor(wx, wz, col_x, col_z, plant_id, stage)

	var kind: int = int(feat.get("kind", _WorldFeatureTypes.FeatureKind.NONE))
	match kind:
		_WorldFeatureTypes.FeatureKind.RUIN:
			return _make_building_anchor(wx, wz, col_x, col_z, "ruin_pillar", Vector3(1.2, 2.2, 1.2), 1.1)
		_WorldFeatureTypes.FeatureKind.TOWN_BUILDING:
			return _make_building_anchor(wx, wz, col_x, col_z, "town_hall", Vector3(2.4, 3.0, 2.4), 1.4)
		_WorldFeatureTypes.FeatureKind.TOWN:
			return null
		_:
			var tile_override: int = _FeatureRegistry.get_tile_override(wx, wz)
			if tile_override == VoxelTypes.STONE:
				return _make_building_anchor(wx, wz, col_x, col_z, "stone_wall", Vector3(1.0, 1.7, 1.0), 0.85)
			if tile_override == VoxelTypes.DIRT:
				return _make_building_anchor(wx, wz, col_x, col_z, "wood_wall", Vector3(1.0, 1.5, 1.0), 0.85)
			return null


func _make_vegetation_anchor(
	wx: int,
	wz: int,
	col_x: float,
	col_z: float,
	plant_id: StringName,
	stage: int
) -> Node3D:
	var tex := _billboard_texture(str(plant_id), stage)
	if tex == null:
		return null
	var anchor := Node3D.new()
	anchor.name = "Veg_%d_%d" % [wx, wz]
	anchor.position = _anchor_pos(col_x, col_z, _sprite_height_offset_for_plant(plant_id, stage))
	var sprite := Sprite3D.new()
	sprite.name = "Billboard"
	anchor.add_child(sprite)
	_apply_plant_texture(sprite, plant_id, stage)
	return anchor


func _make_building_anchor(
	wx: int,
	wz: int,
	col_x: float,
	col_z: float,
	building_id: String,
	size: Vector3,
	height_offset: float
) -> Node3D:
	var tex := _billboard_texture(building_id)
	if tex == null:
		return null
	var anchor := Node3D.new()
	anchor.name = "Building_%s_%d_%d" % [building_id, wx, wz]
	anchor.position = _anchor_pos(col_x, col_z, height_offset)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	anchor.add_child(mesh_inst)
	_apply_building_mesh(mesh_inst, tex, size)
	return anchor


func _apply_plant_texture(sprite: Sprite3D, plant_id: StringName, stage: int) -> void:
	if sprite == null or _registry == null:
		return
	var tex: Texture2D = _billboard_texture(str(plant_id), stage)
	_apply_sprite(sprite, tex, 0.009)


func _apply_building_mesh(mesh_inst: MeshInstance3D, tex: Texture2D, size: Vector3) -> void:
	if mesh_inst == null or _registry == null:
		return
	if _registry.has_method("configure_building_mesh"):
		_registry.configure_building_mesh(mesh_inst, tex, size)
	else:
		var box := BoxMesh.new()
		box.size = size
		mesh_inst.mesh = box
		mesh_inst.position.y = size.y * 0.5


func _billboard_texture(id: String, stage: int = -1) -> Texture2D:
	if _registry == null:
		return null
	if _registry.has_method("get_billboard_texture"):
		return _registry.get_billboard_texture(id, stage)
	if stage >= 0 and _registry.has_method("get_vegetation_texture"):
		return _registry.get_vegetation_texture(StringName(id), stage)
	if _registry.has_method("get_building_texture"):
		return _registry.get_building_texture(StringName(id))
	return null


func _apply_sprite(sprite: Sprite3D, tex: Texture2D, pixel_size: float) -> void:
	if _registry == null or sprite == null:
		return
	if _registry.has_method("apply_to_sprite3d"):
		_registry.apply_to_sprite3d(sprite, tex, Color.WHITE, pixel_size)
	elif _registry.has_method("configure_sprite3d"):
		_registry.configure_sprite3d(sprite, tex, Color.WHITE, pixel_size)


func _anchor_pos(column_x: float, column_z: float, height_offset: float) -> Vector3:
	if _registry and _registry.has_method("column_sprite_position"):
		return _registry.column_sprite_position(world, chunk_manager, _crystal, column_x, column_z, height_offset)
	var y := _anchor_y(column_x, column_z, height_offset)
	return _WorldVisualCoords.column_to_world_pos(column_x, y, column_z)


func _anchor_y(column_x: float, column_z: float, height_offset: float) -> float:
	if _registry and _registry.has_method("anchor_sprite_y"):
		return _registry.anchor_sprite_y(world, chunk_manager, _crystal, column_x, column_z, height_offset)
	var lift: float = _GameVisualRegistry.SURFACE_LIFT
	var surface := _EntityNavigation.walkable_y_light(world, chunk_manager, _crystal, column_x, column_z)
	return surface + height_offset + lift


func _sprite_height_offset_for_plant(plant_id: StringName, stage: int) -> float:
	var growth := float(stage + 1) / 3.0
	match str(plant_id):
		"grass_tuft":
			return 0.25 + growth * 0.15
		"bush":
			return 0.45 + growth * 0.35
		_:
			return 0.9 + growth * 1.1


func _clear_chunk(coord: Vector2i) -> void:
	if not _nodes_by_chunk.has(coord):
		return
	for node_variant in _nodes_by_chunk[coord]:
		var anchor: Node3D = node_variant
		if anchor == null:
			continue
		for key in _nodes_by_cell.keys().duplicate():
			if _nodes_by_cell.get(key) == anchor:
				_nodes_by_cell.erase(key)
		if is_instance_valid(anchor):
			anchor.queue_free()
	_nodes_by_chunk.erase(coord)


func _clear_all() -> void:
	for coord in _nodes_by_chunk.keys():
		_clear_chunk(coord)
	_nodes_by_chunk.clear()
	_nodes_by_cell.clear()