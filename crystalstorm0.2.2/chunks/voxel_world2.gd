class_name VoxelWorld2
extends Node2D

const VIEW_DISTANCE := 4

@export var chunk_scene : PackedScene

var world := InfiniteNoiseWorld.new(12345)

var loaded_chunks := {}

@onready var player : Player = $"../Player"

func _process(_delta):

	var chunk_x = floori(
		player.voxel_position.x / Chunk.CHUNK_SIZE
	)

	var chunk_y = floori(
		player.voxel_position.y / Chunk.CHUNK_SIZE
	)

	update_chunks(chunk_x, chunk_y)
	
func update_chunks(cx:int, cy:int):

	for y in range(
		cy - VIEW_DISTANCE,
		cy + VIEW_DISTANCE + 1
	):

		for x in range(
			cx - VIEW_DISTANCE,
			cx + VIEW_DISTANCE + 1
		):

			var key = Vector2i(x,y)

			if loaded_chunks.has(key):
				continue

			spawn_chunk(key)
			
func spawn_chunk(chunk_coord:Vector2i):

	var chunk = preload("res://scenes/Chunk.tscn").instantiate()

	chunk.biome_world = world
	chunk.voxel_world = self
	chunk.chunk_position = chunk_coord
	chunk.z_index = chunk_coord.x + chunk_coord.y

	add_child(chunk)

	loaded_chunks[chunk_coord] = chunk
