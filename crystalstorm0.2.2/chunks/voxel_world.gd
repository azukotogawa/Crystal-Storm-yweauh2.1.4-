class_name VoxelWorld
extends Node3D

@export var chunk_scene: PackedScene
@onready var player: Node3D = $"../Player"

var world := InfiniteNoiseWorld.new(12349)
var manager: ChunkManager

func _ready():
	manager = ChunkManager.new()
	add_child(manager)  # Important: Add to tree
