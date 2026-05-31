class_name VoxelWorld
extends Node2D

@export var chunk_scene: PackedScene
@onready var player: Node2D = $"../Player"

var world := InfiniteNoiseWorld.new(12349)
var manager: ChunkManager

func _ready():
	manager = ChunkManager.new(world, chunk_scene)
	add_child(manager)  # Important: Add to tree

func _process(_dt):
	var cx = floori(player.voxel_position.x / float(ChunkData.SIZE))
	var cy = floori(player.voxel_position.y / float(ChunkData.SIZE))
	manager.update_stream(cx, cy)
