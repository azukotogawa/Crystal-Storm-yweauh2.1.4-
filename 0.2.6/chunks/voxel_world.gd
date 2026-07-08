class_name VoxelWorld
extends Node3D

@export var chunk_scene: PackedScene
@onready var player: Node3D = $"../Player"

var manager: ChunkManager

func _ready() -> void:
	var features = get_tree().get_first_node_in_group("world_features")
	if features and features.has_method("ensure_ready"):
		await features.ensure_ready()

	manager = ChunkManager.new()
	add_child(manager)

	if features and features.has_method("on_chunk_manager_ready"):
		features.on_chunk_manager_ready(manager)
