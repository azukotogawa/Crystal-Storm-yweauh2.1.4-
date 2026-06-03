class_name ChunkManager
extends Node3D

@export var chunk_scene: PackedScene
@export var texture: Texture2D

const RENDER_DISTANCE := 4

var chunks: Dictionary[Vector2i, ChunkView] = {}
var job_queue := []
var mutex := Mutex.new()
var semaphore := Semaphore.new() # NEW: Keeps the thread asleep when idle
var thread := Thread.new()
var exit_thread := false        # NEW: Allows clean shutdowns
var pending := {}

var player: Node3D
var world: InfiniteNoiseWorld

const CHUNK_VIEW_SCENE = preload("res://scenes/ChunkView.tscn")

func _ready():
	add_to_group("chunk_manager")
	exit_thread = false
	thread.start(_worker)
	
	player = get_node_or_null("../../Player")
	if player == null:
		player = get_node_or_null("../Player")
	
	if world == null:
		world = get_node_or_null("../../World") as InfiniteNoiseWorld

# CRITICAL: Ensures the thread shuts down cleanly when leaving the game
func _exit_tree():
	mutex.lock()
	exit_thread = true
	mutex.unlock()
	semaphore.post() # Wake up thread so it reads the exit flag
	thread.wait_to_finish()

func request_chunk(coord):
	if chunks.has(coord) or pending.has(coord):
		return

	pending[coord] = true

	mutex.lock()
	job_queue.append(coord)
	mutex.unlock()
	semaphore.post() # NEW: Signals the thread that work is available Immediately

func _worker():
	while not exit_thread:
		# Wait passively here until semaphore.post() is called. 
		# Uses ZERO CPU while waiting, completely eliminating micro-stutters.
		semaphore.wait() 

		mutex.lock()
		if exit_thread:
			mutex.unlock()
			break
		
		var coord = job_queue.pop_front()
		mutex.unlock()

		# 1. Create LOCAL data
		var data := ChunkData.new(coord)
		_generate_chunk(data)
		
		# 2. Generate mesh locally (no class-level variables)
		var local_quads = _build_mesh_in_thread(data)
		
		# 3. Send LOCAL data to main thread
		call_deferred("_on_chunk_ready", data, local_quads)

var height_map := []
var top_type_map := []

func _build_mesh_in_thread(data) -> Array:
	var local_quads := [] # Scope stays inside this specific thread execution
	var chunk_data = data
	
	# THREAD-SAFE FIX: Do not use class variables. Scope these locally!
	var height_map := []
	var top_type_map := []

	height_map.resize(ChunkData.SIZE)
	top_type_map.resize(ChunkData.SIZE)

	for x in range(ChunkData.SIZE):
		height_map[x] = []
		top_type_map[x] = []

		for y in range(ChunkData.SIZE):
			var h := -1
			for z in range(ChunkData.HEIGHT - 1, -1, -1):
				if chunk_data.get_voxel(x, y, z) != VoxelTypes.AIR:
					h = z
					break

			height_map[x].append(h)

			if h == -1:
				top_type_map[x].append(VoxelTypes.AIR)
			else:
				top_type_map[x].append(chunk_data.get_voxel(x, y, h))
				
	var used := []
	used.resize(ChunkData.SIZE)

	for x in range(ChunkData.SIZE):
		used[x] = []
		used[x].resize(ChunkData.SIZE)
		for y in range(ChunkData.SIZE):
			used[x][y] = false

	for x in range(ChunkData.SIZE):
		for y in range(ChunkData.SIZE):

			if used[x][y]:
				continue

			var h = height_map[x][y]
			if h == -1:
				continue
			var voxel_type = top_type_map[x][y]

			# ---- EXPAND X ----
			var w = 1
			while x + w < ChunkData.SIZE:
				if used[x + w][y]:
					break
				if height_map[x + w][y] != h:
					break
				if top_type_map[x + w][y] != voxel_type:
					break
				w += 1

			# ---- EXPAND Y ----
			var d = 1
			var done = false

			while y + d < ChunkData.SIZE and not done:
				for i in range(w):
					if used[x + i][y + d]:
						done = true
						break
					if height_map[x + i][y + d] != h:
						done = true
						break
					if top_type_map[x + i][y + d] != voxel_type:
						done = true
						break
				if not done:
					d += 1
					
			for dx in range(w):
				for dy in range(d):
					used[x + dx][y + dy] = true

			# ---- FIXED 1X1 EMIT: BRING BACK THE PLAINS ----
			for dx in range(w):
				for dy in range(d):
					var tx = x + dx
					var ty = y + dy

					# 1. Check if there is an AIR block directly above this voxel on the Z axis.
					# If there is air above it, it's a visible top surface and MUST be drawn!
					var open_above = is_face_visible_global(tx, ty, h, 0, 0, 1, data)

					# 2. Check the horizontal neighbors
					var open_left  = is_face_visible_global(tx, ty, h, -1,  0, 0, data)
					var open_right = is_face_visible_global(tx, ty, h,  1,  0, 0, data)
					var open_top   = is_face_visible_global(tx, ty, h,  0, -1, 0, data)
					var open_down  = is_face_visible_global(tx, ty, h,  0,  1, 0, data)

					# CULL RULE: Only skip drawing if the block is completely buried 
					# from the top AND all sides.
					if not (open_above or open_left or open_right or open_top or open_down):
						continue

					# Emit your valid 1x1 isometric surface block
					emit_surface_quad(
						tx,
						ty,
						1,
						1,
						h,
						data,
						local_quads
					)
			
	# Automatically sort your chunks on the worker thread to clean up main loop latency
	local_quads.sort_custom(func(a, b):
		return a["sort_key"] < b["sort_key"]
	)
	
	return local_quads


func emit_surface_quad(x:int, y:int, w:int, d:int, h:int, data: ChunkData, out_quads: Array):
	var chunk_offset_x = data.position.x * ChunkData.SIZE
	var chunk_offset_y = data.position.y * ChunkData.SIZE

	var screen_pos = IsoMath.voxel_to_screen(
		x + chunk_offset_x,
		y + chunk_offset_y,
		h
	)

	var world_x := x + data.position.x * ChunkData.SIZE
	var world_y := y + data.position.y * ChunkData.SIZE

	var pos := IsoMath.voxel_to_screen(world_x, world_y, h)
	var depth_y = pos.y + h * 2.0
	
	var voxel_type = data.get_voxel(x, y, h)
	
	out_quads.append({
		"x": x,
		"y": y,
		"w": w,
		"h": d,
		"z": h,
		"type": voxel_type,
		"sort_key": depth_y
	})

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
		for x in range(cx - RENDER_DISTANCE, cx + RENDER_DISTANCE + 2):
			var key = Vector2i(x, y)
			needed[key] = true

			if not chunks.has(key):
				request_chunk(key)

	# unload old chunks
	for key in chunks.keys():
		if not needed.has(key):
			chunks[key].queue_free()
			chunks.erase(key)
		
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
					
				
func _on_chunk_ready(data: ChunkData, mesh_data: Array):
	pending.erase(data.position)

	var view: ChunkView = CHUNK_VIEW_SCENE.instantiate() 
	add_child(view)

	view.setup(data, mesh_data)


	chunks[data.position] = view

func rebuild_chunks():
	for coord: Vector2i in chunks.keys():
		var chunk := chunks[coord]
		
		# Keep chunks at 0 depth, just update their active graphics
		chunk.emit_quads()


	
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


func is_solid_voxel(x:int, y:int, z:int) -> bool:
	var biome = world.get_biome(x, y)
	var h = biome["render_height"]
	return z < h
	
func is_blocked(x:int, y:int, z:int) -> bool:
	return is_solid_voxel(x, y, z)

# Update this method inside your worker loop
func is_face_visible_global(local_x: int, local_y: int, local_z: int, dx: int, dy: int, dz: int, chunk_data: ChunkData) -> bool:
	var nx = local_x + dx
	var ny = local_y + dy
	var nz = local_z + dz

	# Convert to absolute world voxel positions using the data object's position
	var world_x = local_x + chunk_data.position.x * ChunkData.SIZE
	var world_y = local_y + chunk_data.position.y * ChunkData.SIZE
	
	# If the target coordinate is strictly inside this chunk, read local data instantly
	if nx >= 0 and ny >= 0 and nz >= 0 and nx < ChunkData.SIZE and ny < ChunkData.SIZE and nz < ChunkData.HEIGHT:
		return chunk_data.get_voxel(nx, ny, nz) == VoxelTypes.AIR

	# If it crosses a boundary, look across into the neighboring chunk or world noise
	var target_world_x = world_x + dx
	var target_world_y = world_y + dy
	
	var neighbor_voxel = get_global_voxel(target_world_x, target_world_y, nz)
	return neighbor_voxel == VoxelTypes.AIR


func get_global_voxel(wx: int, wy: int, wz: int) -> int:
	if wz < 0 or wz >= ChunkData.HEIGHT:
		return VoxelTypes.AIR
		
	# Calculate which chunk coordinates this world position lands on
	var chunk_x = floori(wx / float(ChunkData.SIZE))
	var chunk_y = floori(wy / float(ChunkData.SIZE))
	var chunk_coord = Vector2i(chunk_x, chunk_y)
	
	# Extract the local index inside that specific chunk
	var local_x = posmod(wx, ChunkData.SIZE)
	var local_y = posmod(wy, ChunkData.SIZE)
	
	# Read the chunk safely if it exists, otherwise fall back to world generation rule
	mutex.lock()
	var chunk_exists = chunks.has(chunk_coord)
	var chunk_node = chunks.get(chunk_coord)
	mutex.unlock()
	
	if chunk_exists and is_instance_valid(chunk_node) and chunk_node.chunk_data:
		return chunk_node.chunk_data.get_voxel(local_x, local_y, wz)
		
	# If the chunk isn't loaded yet, check if the height matches the world noise
	var biome = world.get_biome(wx, wy)
	if wz < biome["render_height"]:
		return VoxelTypes.biome_to_voxel_id.get(biome["name"], VoxelTypes.AIR)
		
	return VoxelTypes.AIR
