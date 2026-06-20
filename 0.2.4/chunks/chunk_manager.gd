class_name ChunkManager
extends Node3D

@export var RENDER_DISTANCE : int = 3

var chunks: Dictionary[Vector2i, ChunkView] = {}
var pending := {}
var _chunk_tasks := {}  # coord -> WorkerThreadPool task id for async gen

# Optimization: only update when player moves to new chunk
var _last_chunk_key: Vector2i = Vector2i(-99999, -99999)

# Player will be obtained via the 'player_ready' signal
var player: Node3D = null
var world: InfiniteNoiseWorld

const CHUNK_VIEW_SCENE = preload("res://scenes/ChunkView.tscn")

const FACE_TOP := 0
const FACE_NEG_X := 3
const FACE_POS_X := 4
const FACE_NEG_Z := 5
const FACE_POS_Z := 6

func _ready():
	add_to_group("chunk_manager")
	
	player = get_tree().get_first_node_in_group("player")
	world = get_tree().get_first_node_in_group("world")
	
	if player == null:                                                          
		print("WARNING: Player node (group 'player') not found in _ready!")
	if world == null:                                                           
		print("WARNING: World node (group 'world') not found in _ready!")

	# Request initial chunks...
	if player and world:
		var cx = floori(player.global_position.x / float(ChunkData.SIZE))
		var cz = floori(player.global_position.z / float(ChunkData.SIZE))
		update_stream(cx, cz)

func _exit_tree():
	# Wait briefly for in-flight tasks (non-fatal if not)
	for tid in _chunk_tasks.values():
		if tid is int:
			WorkerThreadPool.wait_for_task_completion(tid)
	pass

func request_chunk(coord: Vector2i, high_priority: bool = false):
	if chunks.has(coord) or pending.has(coord) or _chunk_tasks.has(coord):
		return

	pending[coord] = true

	# Async generation via WorkerThreadPool so main thread (player, input, draw) stays responsive.
	# Chunk appears when task completes -> _on_chunk_ready (deferred add).
	# high_priority helps nearby chunks get worked on sooner when the pool is busy.
	var data := ChunkData.new(coord, world)

	# All heavy noise (the chunk rect + any halo columns for side walls) now happens
	# inside the bg worker via _compute_column_maps + the heightfield emitter's oob
	# fallbacks. This eliminates the previous main-thread precompute/warm cost that
	# was a bottleneck when streaming many chunks.

	var task_id := WorkerThreadPool.add_task(Callable(self, "_generate_chunk_task").bind(coord, data), high_priority)
	_chunk_tasks[coord] = task_id

func _build_mesh(data: ChunkData) -> Dictionary:
	var out_quads := []

	# === TOP FACES (+Y normal) ===
	_greedy_mesh_plane(data, Vector3i(0, 1, 0), FACE_TOP, out_quads)
	_greedy_mesh_plane(data, Vector3i(0, -1, 0), 6, out_quads)
	_greedy_mesh_plane(data, Vector3i(0, -1, 0), 4, out_quads)

	# === -X FACES ===
	_greedy_mesh_plane(data, Vector3i(-1, 0, 0), FACE_NEG_X, out_quads)

	# === +X FACES ===
	_greedy_mesh_plane(data, Vector3i(1, 0, 0), FACE_POS_X, out_quads)

	# === -Z FACES ===
	_greedy_mesh_plane(data, Vector3i(0, 0, -1), FACE_NEG_Z, out_quads)

	# === +Z FACES ===
	_greedy_mesh_plane(data, Vector3i(0, 0, 1), FACE_POS_Z, out_quads)

	return {
		"quads": out_quads,
		"count": out_quads.size()
	}

# Generic greedy meshing for a single plane orientation (e.g., +Y, -X, etc.)
func _greedy_mesh_plane(data: ChunkData, normal_dir: Vector3i, face_code: int, out_quads: Array):
	# Fast path for Y faces (top/bottom): one voxel per column only.
	# Uses the precomputed surface + tile maps (no 160-height scan).
	# Added 2D greedy rect merging for same-height same-tile columns.
	# This dramatically reduces MultiMesh instance count on flat/similar areas
	# (big FPS win) while producing correct larger dim_x/dim_z + uv_w/uv_h for tiling.
	if normal_dir.y != 0:
		var visited := []
		visited.resize(ChunkData.SIZE)
		for i in ChunkData.SIZE:
			visited[i] = []
			visited[i].resize(ChunkData.SIZE)
			for j in ChunkData.SIZE:
				visited[i][j] = false

		for x in range(ChunkData.SIZE):
			for z in range(ChunkData.SIZE):
				if visited[x][z]:
					continue
				var sy = data.get_surface_y(x, z)
				if sy < 0 or sy >= ChunkData.HEIGHT:
					continue
				var vox = data.get_tile_type(x, z)
				if vox == VoxelTypes.AIR:
					continue

				# Expand in +x
				var dx := 1
				while x + dx < ChunkData.SIZE and not visited[x + dx][z] and data.get_surface_y(x + dx, z) == sy and data.get_tile_type(x + dx, z) == vox:
					dx += 1

				# Expand in +z for the current width
				var dz := 1
				while z + dz < ChunkData.SIZE:
					var can := true
					for xx in range(dx):
						var cx := x + xx
						var cz := z + dz
						if visited[cx][cz] or data.get_surface_y(cx, cz) != sy or data.get_tile_type(cx, cz) != vox:
							can = false
							break
					if not can:
						break
					dz += 1

				# Mark visited
				for xx in range(dx):
					for zz in range(dz):
						visited[x + xx][z + zz] = true

				# Emit merged rect (top or bottom face of the surface slab rect).
				# uv_w/uv_h same for bottom (face_code=2) as top (0); the BoxMesh -Y face
				# provides the underside with its own UV winding (fract repeat + atlas still
				# produces consistent texturing across faces).
				out_quads.append({
					"x": x,
					"y": sy,
					"z": z,
					"dim_x": float(dx),
					"dim_y": 1.0,
					"dim_z": float(dz),
					"uv_w": float(dx),   # U->X, V->Z (for both top and bottom)
					"uv_h": float(dz),
					"type": vox,
					"face_code": face_code
				})
		return

	# For one-voxel-thick surface heightfield, bypass the expensive general 3D
	# greedy (160-high masks etc.) and use a direct 2D heightmap-based side emitter.
	# This is the key improvement for _build_mesh / _generate_chunk_task perf.
	_emit_surface_side_walls(data, normal_dir, face_code, out_quads)
	return


func _process(_delta):
	if player == null or world == null:
		return

	var cx = floori(player.global_position.x / float(ChunkData.SIZE))
	var cz = floori(player.global_position.z / float(ChunkData.SIZE))
	var current_key := Vector2i(cx, cz)

	if not "_last_chunk_key" in self or _last_chunk_key != current_key:
		_last_chunk_key = current_key
		update_stream(cx, cz)
	
func update_stream(cx: int, cz: int):
	var needed := {}
	var to_request: Array = []

	for z in range(cz - RENDER_DISTANCE, cz + RENDER_DISTANCE + 2):
		for x in range(cx - RENDER_DISTANCE, cx + RENDER_DISTANCE + 2):
			var key: Vector2i = Vector2i(x, z)
			needed[key] = true

			if not chunks.has(key) and not pending.has(key) and not _chunk_tasks.has(key):
				var dist: int = abs(x - cx) + abs(z - cz)
				to_request.append({"key": key, "dist": dist})

	# Submit closest chunks first (and with high_priority) so the important terrain near the player
	# gets generated sooner when the worker pool is saturated. This makes "loading" feel much faster.
	to_request.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist"] < b["dist"])
	for item in to_request:
		var item_dict: Dictionary = item
		var dist: int = item_dict["dist"]
		var hp: bool = dist <= (RENDER_DISTANCE + 1)
		var req_key: Vector2i = item_dict["key"]
		request_chunk(req_key, hp)

	for key in chunks.keys():
		if not needed.has(key):
			chunks[key].queue_free()
			chunks.erase(key)

# Dedicated fast emitter for side "lip" quads on a one-voxel-thick heightfield.
# Emits (and merges runs of) 1-high side faces at the surface height of the higher
# column when there is a drop. Merging along the wall direction reduces instances
# on long cliffs (FPS win).
func _emit_surface_side_walls(data: ChunkData, normal_dir: Vector3i, face_code: int, out_quads: Array):
	var dx = normal_dir.x
	var dz = normal_dir.z
	if dx == 0 and dz == 0:
		return

	if abs(dx) == 1:  # X-facing walls (merge along Z)
		for x in range(ChunkData.SIZE):
			var run_start = -1
			var run_h = 0
			var run_t = 0
			for z in range(ChunkData.SIZE + 1):
				var has_wall = false
				var curr_h = 0
				var curr_t = 0
				if z < ChunkData.SIZE:
					curr_h = data.get_surface_y(x, z)
					curr_t = data.get_tile_type(x, z)
					var nx = x + dx
					var nz = z
					var neighbor_h = 0
					if nx >= 0 and nx < ChunkData.SIZE:
						neighbor_h = data.get_surface_y(nx, nz)
					else:
						var gx = data.position.x * ChunkData.SIZE + nx
						var gz = data.position.y * ChunkData.SIZE + nz
						neighbor_h = int(data.world.get_surface_height_uncached(float(gx), float(gz))) if data.world else 0
					has_wall = curr_h > neighbor_h + 0.1
				if has_wall and (run_start == -1 or curr_h == run_h and curr_t == run_t):
					if run_start == -1:
						run_start = z
						run_h = curr_h
						run_t = curr_t
				else:
					if run_start != -1:
						out_quads.append({
							"x": x,
							"y": run_h,
							"z": run_start,
							"dim_x": 1.0,
							"dim_y": 1.0,
							"dim_z": float(z - run_start),
							"uv_w": float(z - run_start),
							"uv_h": 1.0,
							"type": run_t,
							"face_code": face_code
						})
					run_start = -1
	elif abs(dz) == 1:  # Z-facing walls (merge along X)
		for z in range(ChunkData.SIZE):
			var run_start = -1
			var run_h = 0
			var run_t = 0
			for x in range(ChunkData.SIZE + 1):
				var has_wall = false
				var curr_h = 0
				var curr_t = 0
				if x < ChunkData.SIZE:
					curr_h = data.get_surface_y(x, z)
					curr_t = data.get_tile_type(x, z)
					var nz = z + dz
					var nx = x
					var neighbor_h = 0
					if nz >= 0 and nz < ChunkData.SIZE:
						neighbor_h = data.get_surface_y(nx, nz)
					else:
						var gx = data.position.x * ChunkData.SIZE + nx
						var gz = data.position.y * ChunkData.SIZE + nz
						neighbor_h = int(data.world.get_surface_height_uncached(float(gx), float(gz))) if data.world else 0
					has_wall = curr_h > neighbor_h + 0.1
				if has_wall and (run_start == -1 or curr_h == run_h and curr_t == run_t):
					if run_start == -1:
						run_start = x
						run_h = curr_h
						run_t = curr_t
				else:
					if run_start != -1:
						out_quads.append({
							"x": run_start,
							"y": run_h,
							"z": z,
							"dim_x": float(x - run_start),
							"dim_y": 1.0,
							"dim_z": 1.0,
							"uv_w": float(x - run_start),
							"uv_h": 1.0,
							"type": run_t,
							"face_code": face_code
						})
					run_start = -1

func _generate_chunk(data: ChunkData):
	if world:
		world._surface_cache.clear()
		world._tile_cache.clear()
	# Compute the 16x16 surface + tile maps using uncached noise.
	# This moves the (unavoidable first-time) noise work into the bg worker instead of
	# blocking the main thread in ChunkData.new / request_chunk.
	# The maps are then used by the fast heightfield mesher (Y + side walls).
	var start = Time.get_ticks_usec()
	data._compute_column_maps(true)

	# No more 3D voxel population or per-column world calls needed here.
	# (The legacy voxels/visibility arrays are still allocated in _init but are
	# not touched by the current one-voxel-thick paths.)

	#print("Chunk ", data.position, " generated in ", (Time.get_ticks_usec() - start)/1000.0, " ms")
					
func _on_chunk_ready(data: ChunkData, packed_quad_data: Dictionary):
	if pending.has(data.position):                                              
		pending.erase(data.position)                                                             
	if chunks.has(data.position):                                                                                     
		return                                                                                              
	if not packed_quad_data.has("count") or packed_quad_data.get("count", 0) == 0:   
		return                                                            
	var view: ChunkView = CHUNK_VIEW_SCENE.instantiate()
	if view:
		view.setup(data, packed_quad_data)
		add_child(view)
		chunks[data.position] = view
	else:
		print("ERROR: Failed to instantiate ChunkView for position: ", data.position)

# Worker task (runs off-thread): generate voxels + build quads, then defer result to main thread.
func _generate_chunk_task(coord: Vector2i, data: ChunkData):
	_generate_chunk(data)
	var quads = _build_mesh(data)
	call_deferred("_on_chunk_task_complete", coord, data, quads)

func _on_chunk_task_complete(coord: Vector2i, data: ChunkData, packed_quad_data: Dictionary):
	_chunk_tasks.erase(coord)
	_on_chunk_ready(data, packed_quad_data)

func get_chunk_data_at_world_pos(world_pos: Vector3) -> ChunkData:
	var chunk_x = floori(world_pos.x / float(ChunkData.SIZE))
	var chunk_z = floori(world_pos.z / float(ChunkData.SIZE))
	var chunk_coord = Vector2i(chunk_x, chunk_z)
	
	if chunks.has(chunk_coord):
		return chunks[chunk_coord].chunk_data
	return null # Chunk not loaded/generated yet

func rebuild_chunks():
	for coord: Vector2i in chunks.keys():
		request_chunk(coord)
		
func spawn_area_ready(center_x:int, center_z:int) -> bool:
	# Must actually test a small area (was broken empty range before)
	var r := 0
	for x in range(center_x - r, center_x + r + 1):
		for z in range(center_z - r, center_z + r + 1):
			var key = Vector2i(x, z)
			if not chunks.has(key):
				return false
	return true
