class_name VoxelWorld
extends Node3D

@export var chunk_scene: PackedScene
@onready var player: Node3D = $"../Player"

var manager: ChunkManager
var _composition_driven: bool = false


func _ready() -> void:
	add_to_group("voxel_world")
	ChunkData.configure_macro_terrain_from_env()
	ChunkData.configure_micro_terrain_from_env()
	call_deferred("_maybe_legacy_create")


func _maybe_legacy_create() -> void:
	if _composition_driven or manager != null:
		return
	await get_tree().process_frame
	if _composition_driven or manager != null:
		return
	if get_tree().get_first_node_in_group("composition_root") != null:
		return
	# Legacy path without composition root.
	var features = get_tree().get_first_node_in_group("world_features")
	if features and features.has_method("ensure_ready"):
		await features.ensure_ready()
	manager = ChunkManager.new()
	add_child(manager)
	if features and features.has_method("on_chunk_manager_ready"):
		features.on_chunk_manager_ready(manager)


## Composition-root path: features already seeded; create ChunkManager and return it.
## World bake load/rebuild is awaited cooperatively so the loading UI stays responsive.
func create_chunk_manager_with_services(registry) -> ChunkManager:
	_composition_driven = true
	if manager != null:
		return manager
	var features = registry.resolve(&"world_features") if registry else null
	# Features already seeded by CompositionRoot FEATURES_SEEDED; only wait if incomplete.
	if features and not bool(features.get("bootstrap_complete")) and features.has_method("ensure_ready"):
		await features.ensure_ready()
	manager = ChunkManager.new()
	manager.defer_world_bake_bootstrap = true
	add_child(manager)
	if manager.has_method("bootstrap_world_bake_async"):
		await manager.bootstrap_world_bake_async()
	# Root performs explicit handoff; still notify features for chunk_manager field.
	if features:
		features.chunk_manager = manager
	return manager
