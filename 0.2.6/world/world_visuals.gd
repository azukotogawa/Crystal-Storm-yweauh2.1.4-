class_name WorldVisuals
extends Node3D

## Root for all world-space visual content (entities, vegetation, buildings, markers, VFX).

var _post_bootstrap_done: bool = false


func _enter_tree() -> void:
	add_to_group("world_visuals_root")


func _ready() -> void:
	_ensure_layer_roots()
	call_deferred("_bootstrap")


func get_entities_root() -> Node3D:
	return _layer_node("Entities")


func get_vegetation_root() -> Node3D:
	return _layer_node("Vegetation")


func get_buildings_root() -> Node3D:
	return _layer_node("Buildings")


func get_spawn_markers_root() -> Node3D:
	return _layer_node("SpawnMarkers")


func get_combat_vfx_root() -> Node3D:
	return _layer_node("CombatVFX")


func get_feature_layer() -> Node3D:
	var n := get_node_or_null("FeatureVisualLayer")
	return n as Node3D if n is Node3D else null


func _layer_node(layer_name: String) -> Node3D:
	var n := get_node_or_null(layer_name)
	if n is Node3D:
		return n
	var created := Node3D.new()
	created.name = layer_name
	add_child(created)
	return created


func _ensure_layer_roots() -> void:
	get_entities_root()
	get_vegetation_root()
	get_buildings_root()
	get_spawn_markers_root()
	get_combat_vfx_root()


func _bootstrap() -> void:
	var registry = get_tree().get_first_node_in_group("game_visual_registry")
	if registry and registry.has_method("ensure_textures_ready"):
		await registry.ensure_textures_ready()
	elif registry and registry.has_method("ensure_ready"):
		await registry.ensure_ready()
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var world_features = get_tree().get_first_node_in_group("world_features")
	if world_features and world_features.has_method("ensure_ready"):
		await world_features.ensure_ready()
	if not is_instance_valid(self) or not is_inside_tree():
		return
	await _await_chunk_manager()
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var cm: ChunkManager = get_tree().get_first_node_in_group("chunk_manager")
	if cm and registry and registry.has_method("on_chunk_manager_ready"):
		registry.on_chunk_manager_ready(cm)
	if registry and registry.has_signal("visuals_ready"):
		if not registry.visuals_ready.is_connected(_on_visuals_ready):
			registry.visuals_ready.connect(_on_visuals_ready)
		if registry.has_method("is_ready") and registry.is_ready():
			_on_visuals_ready()
	call_deferred("post_bootstrap_refresh")


func on_chunk_manager_ready(cm: ChunkManager) -> void:
	if cm == null:
		return
	_bind_chunk_streaming(cm)
	var registry = get_tree().get_first_node_in_group("game_visual_registry")
	if registry and registry.has_method("on_chunk_manager_ready"):
		registry.on_chunk_manager_ready(cm)
	var feat := get_feature_layer()
	if feat and feat.has_method("on_chunk_manager_ready"):
		feat.on_chunk_manager_ready(cm)
	call_deferred("post_bootstrap_refresh")


func post_bootstrap_refresh() -> void:
	if _post_bootstrap_done:
		return
	var registry = get_tree().get_first_node_in_group("game_visual_registry")
	if registry and registry.has_method("post_bootstrap_refresh"):
		await registry.post_bootstrap_refresh()
	elif registry and registry.has_method("refresh_all"):
		await get_tree().process_frame
		registry.refresh_all()
	_post_bootstrap_done = true


func _bind_chunk_streaming(cm: ChunkManager) -> void:
	if cm.has_signal("chunk_ready") and not cm.chunk_ready.is_connected(_on_chunk_ready):
		cm.chunk_ready.connect(_on_chunk_ready)


func _on_chunk_ready(_coord: Vector2i, _data: ChunkData) -> void:
	call_deferred("_refresh_all_layers")


func _await_chunk_manager() -> void:
	while is_instance_valid(self) and is_inside_tree() and get_tree().get_first_node_in_group("chunk_manager") == null:
		await get_tree().process_frame
	if not is_instance_valid(self) or not is_inside_tree():
		return
	await get_tree().process_frame


func _on_visuals_ready() -> void:
	_refresh_all_layers()


func _refresh_all_layers() -> void:
	var feat := get_feature_layer()
	if feat and feat.has_method("repopulate_all"):
		feat.repopulate_all()
	var registry = get_tree().get_first_node_in_group("game_visual_registry")
	if registry and registry.has_method("refresh_all"):
		registry.refresh_all()
	var combat = get_tree().get_first_node_in_group("combat_visual_feedback")
	if combat and combat.has_method("reload_textures"):
		combat.reload_textures()