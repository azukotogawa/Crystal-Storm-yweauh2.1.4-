class_name WorldVisuals
extends Node3D

## Root for all world-space visual content (entities, vegetation, buildings, markers, VFX).


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
	if registry and registry.has_method("ensure_ready"):
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
	if registry and registry.has_signal("visuals_ready"):
		if not registry.visuals_ready.is_connected(_on_visuals_ready):
			registry.visuals_ready.connect(_on_visuals_ready)
		if registry.has_method("is_ready") and registry.is_ready():
			_on_visuals_ready()


func _await_chunk_manager() -> void:
	while is_instance_valid(self) and is_inside_tree() and get_tree().get_first_node_in_group("chunk_manager") == null:
		await get_tree().process_frame
	if not is_instance_valid(self) or not is_inside_tree():
		return
	await get_tree().process_frame


func _on_visuals_ready() -> void:
	var feat := get_feature_layer()
	if feat and feat.has_method("repopulate_all"):
		feat.repopulate_all()