class_name ChunkManager
extends Node2D

@export var chunk_scene: PackedScene
@export var texture: Texture2D

const RENDER_DISTANCE := 8

var chunks := {}
var job_queue := []
var mutex := Mutex.new()
var thread := Thread.new()
var pending := {}

var player: Node2D
var world: InfiniteNoiseWorld

func _init(p_world: InfiniteNoiseWorld, p_scene: PackedScene):
	world = p_world
	chunk_scene = p_scene

func _ready():
	add_to_group("chunk_manager")
	thread.start(_worker)
	# Find Player (from VoxelWorld -> Game -> Player)
	player = get_node_or_null("../../Player")
	if player == null:
		player = get_node_or_null("../Player")  # fallback
	
	if player == null:
		push_error("ChunkManager: Could not find Player node!")
	
	# World is passed in _init, but fallback just in case
	if world == null:
		world = get_node_or_null("../../World") as InfiniteNoiseWorld

func _process(_delta):
	if player == null or world == null:
		return
		
	var cx = floori(player.voxel_position.x / float(ChunkData.SIZE))
	var cy = floori(player.voxel_position.y / float(ChunkData.SIZE))

	update_stream(cx, cy)

	
func update_stream(cx:int, cy:int):

	var needed := {}

	# build desired set
	for y in range(cy - RENDER_DISTANCE, cy + RENDER_DISTANCE + 1):
		for x in range(cx - RENDER_DISTANCE, cx + RENDER_DISTANCE + 1):
			var key = Vector2i(x, y)
			needed[key] = true

			if not chunks.has(key):
				request_chunk(key)

	# unload old chunks
	for key in chunks.keys():
		if not needed.has(key):
			chunks[key].queue_free()
			chunks.erase(key)
			
func request_chunk(coord):

	if chunks.has(coord):
		return

	if pending.has(coord):
		return

	pending[coord] = true

	mutex.lock()
	job_queue.append(coord)
	mutex.unlock()
		
func _worker():

	while true:

		var coord = null

		mutex.lock()
		if job_queue.size() > 0:
			coord = job_queue.pop_front()
		mutex.unlock()

		if coord == null:
			OS.delay_msec(10)
			continue

		var data = ChunkData.new(coord)

		_generate_chunk(data)

		call_deferred("_on_chunk_ready", data)
		
func _generate_chunk(data: ChunkData):
	for y in range(ChunkData.SIZE):
		for x in range(ChunkData.SIZE):

			var wx = x + data.position.x * ChunkData.SIZE
			var wy = y + data.position.y * ChunkData.SIZE

			var biome = world.get_biome(wx, wy)

			var h = biome["render_height"]

			# IMPORTANT: clamp into real voxel range
			#var terrain_height = clamp(h + 20, 1, ChunkData.HEIGHT - 1)

			var voxel_id = VoxelTypes.biome_to_voxel_id.get(
				biome["name"],
				VoxelTypes.AIR
			)
			for z in range(ChunkData.HEIGHT):
				if z < h:
					data.set_voxel(x, y, z, voxel_id)
				else:
					data.set_voxel(x, y, z, VoxelTypes.AIR)
					
				
func _on_chunk_ready(data):

	pending.erase(data.position)

	var view: ChunkView = preload("res://scenes/ChunkView.tscn").instantiate()
	add_child(view)

	view.setup(data, texture)
	view.z_index = chunk_sort_key(
		data.position.x,
		data.position.y
	)

	chunks[data.position] = view
	
func get_or_create(coord: Vector2i) -> ChunkData:
	if chunks.has(coord):
		return chunks[coord].chunk_data

	var data := ChunkData.new(coord)
	_generate_chunk(data)
	return data
	
func chunk_sort_key(chunk_x:int, chunk_y:int) -> int:

	match IsoMath.rotation:
		0:
			return chunk_x + chunk_y

		1:
			return -chunk_y + chunk_x

		2:
			return -(chunk_x + chunk_y)

		3:
			return chunk_y - chunk_x

	return 0

func rebuild_chunks():

	for coord in chunks.keys():

		var chunk = chunks[coord]

		chunk.z_index = chunk_sort_key(
			coord.x,
			coord.y
		)

		chunk._build_and_emit()
