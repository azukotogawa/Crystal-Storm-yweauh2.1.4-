class_name ChunkManager
extends Node3D

signal chunk_ready(coord: Vector2i, data: ChunkData)

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

const _RAMP_DIRS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]
const _RAMP_STEP_MIN := 0.85
const _RAMP_STEP_MAX := 1.2
const _RAMP_PLACEMENT_CHANCE := 38
const _RAMP_VOXEL_STEPS := 8

# Mirrored from WorldBorder — worker threads cannot call class_name statics reliably.
const _WB_PLAYABLE_HALF := 1024
const _WB_TRANSITION := 240.0

const FACE_TOP := 0
const FACE_NEG_X := 3
const FACE_POS_X := 4
const FACE_NEG_Z := 5
const FACE_POS_Z := 6
const CLIFF_HEIGHT := 1.05
const CAVE_MESH_DEPTH := 32

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

	var data := ChunkData.new(coord, world)

	var task_id := WorkerThreadPool.add_task(Callable(self, "_generate_chunk_task").bind(coord, data), high_priority)
	_chunk_tasks[coord] = task_id

func _build_mesh(data: ChunkData) -> Dictionary:
	var out_quads := []

	_emit_ramps(data, out_quads)
	_greedy_mesh_plane(data, Vector3i(0, 1, 0), FACE_TOP, out_quads)
	_greedy_mesh_plane(data, Vector3i(0, -1, 0), 6, out_quads)
	_greedy_mesh_plane(data, Vector3i(0, -1, 0), 4, out_quads)

	_greedy_mesh_plane(data, Vector3i(-1, 0, 0), FACE_NEG_X, out_quads)
	_greedy_mesh_plane(data, Vector3i(1, 0, 0), FACE_POS_X, out_quads)
	_greedy_mesh_plane(data, Vector3i(0, 0, -1), FACE_NEG_Z, out_quads)
	_greedy_mesh_plane(data, Vector3i(0, 0, 1), FACE_POS_Z, out_quads)
	_emit_cave_faces(data, out_quads)

	return {
		"quads": out_quads,
		"count": out_quads.size()
	}

func _greedy_mesh_plane(data: ChunkData, normal_dir: Vector3i, face_code: int, out_quads: Array):
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
				if visited[x][z] or data.has_ramp(x, z):
					continue
				var sy: float = data.get_surface_y(x, z)
				if sy < 0.0 or sy >= float(ChunkData.HEIGHT):
					continue
				var vox := data.get_tile_type(x, z)
				if vox == VoxelTypes.AIR:
					continue

				var dx := 1
				while x + dx < ChunkData.SIZE and not visited[x + dx][z] \
						and is_equal_approx(data.get_surface_y(x + dx, z), sy) \
						and data.get_tile_type(x + dx, z) == vox:
					dx += 1

				var dz := 1
				while z + dz < ChunkData.SIZE:
					var can := true
					for xx in range(dx):
						var cx := x + xx
						var cz := z + dz
						if visited[cx][cz] or not is_equal_approx(data.get_surface_y(cx, cz), sy) \
								or data.get_tile_type(cx, cz) != vox:
							can = false
							break
					if not can:
						break
					dz += 1

				for xx in range(dx):
					for zz in range(dz):
						visited[x + xx][z + zz] = true

				out_quads.append({
					"x": x,
					"y": sy,
					"z": z,
					"dim_x": float(dx),
					"dim_y": 1.0,
					"dim_z": float(dz),
					"uv_w": float(dx),
					"uv_h": float(dz),
					"type": vox,
					"face_code": face_code
				})
		return

	_emit_surface_side_walls(data, normal_dir, face_code, out_quads)


func _is_step_height(diff: float) -> bool:
	return diff >= _RAMP_STEP_MIN and diff <= _RAMP_STEP_MAX


func _should_place_ramp(world_x: int, world_z: int, dir: Vector2i) -> bool:
	if _world_border_should_force_ramp(world_x, world_z):
		return true
	var seed_val := world_x * 73856093 ^ world_z * 19349663 ^ dir.x * 83492791 ^ dir.y * 50331653
	return int(seed_val & 0x7fffffff) % 100 < _RAMP_PLACEMENT_CHANCE


func _world_border_should_force_ramp(world_x: int, world_z: int) -> bool:
	var ox: float = maxf(absf(float(world_x)) - float(_WB_PLAYABLE_HALF), 0.0)
	var oz: float = maxf(absf(float(world_z)) - float(_WB_PLAYABLE_HALF), 0.0)
	if ox <= 0.001 and oz <= 0.001:
		return false
	var margin := 8.0
	if ox > 0.001 and oz > 0.001:
		return sqrt(ox * ox + oz * oz) <= margin + 4.0
	return minf(ox if ox > 0.001 else 1e9, oz if oz > 0.001 else 1e9) <= margin


func _prefer_diagonal_ramp(world_x: int, world_z: int) -> bool:
	var ox: float = maxf(absf(float(world_x)) - float(_WB_PLAYABLE_HALF), 0.0)
	var oz: float = maxf(absf(float(world_z)) - float(_WB_PLAYABLE_HALF), 0.0)
	return ox > 0.001 and oz > 0.001 and sqrt(ox * ox + oz * oz) / _WB_TRANSITION < 0.85


func _emit_ramps(data: ChunkData, out_quads: Array) -> void:
	data.ramp_map.clear()
	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			var low_h: float = data.get_surface_y(x, z)
			var vox := data.get_tile_type(x, z)
			if vox == VoxelTypes.AIR:
				continue
			var world_x: int = data.position.x * ChunkData.SIZE + x
			var world_z: int = data.position.y * ChunkData.SIZE + z

			var dirs: Array = []
			dirs.append_array(_RAMP_DIRS)
			if _prefer_diagonal_ramp(world_x, world_z):
				dirs.append_array([
					Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
				])
			for dir in dirs:
				var d: Vector2i = dir
				var nh: float = _sample_height(data, x + d.x, z + d.y)
				var diff: float = nh - low_h
				if not _is_step_height(diff):
					continue
				if not _should_place_ramp(world_x, world_z, d):
					continue
				data.set_ramp(x, z, d)
				_emit_ramp_voxel_boxes(x, z, low_h, d, vox, out_quads)
				break


func _append_voxel_face(
	out_quads: Array,
	lx: float, ly: float, lz: float,
	sx: float, sy: float, sz: float,
	uv_w: float, uv_h: float,
	vox: int, face_code: int
) -> void:
	out_quads.append({
		"x": lx,
		"y": ly,
		"z": lz,
		"dim_x": sx,
		"dim_y": sy,
		"dim_z": sz,
		"uv_w": uv_w,
		"uv_h": uv_h,
		"type": vox,
		"face_code": face_code,
	})


func _emit_ramp_voxel_boxes(
	x: int, z: int, low_h: float, dir: Vector2i, vox: int, out_quads: Array
) -> void:
	var steps := _RAMP_VOXEL_STEPS
	var step := 1.0 / float(steps)
	var dx := float(dir.x)
	var dz := float(dir.y)
	var x_axis := absf(dx) > 0.001
	var z_axis := absf(dz) > 0.001

	for i in steps:
		var t0 := float(i) * step
		var t1 := float(i + 1) * step
		var ox: float
		var oz: float
		if x_axis:
			ox = t0 if dx > 0.0 else 1.0 - t1
		else:
			ox = 0.0
		if z_axis:
			oz = t0 if dz > 0.0 else 1.0 - t1
		else:
			oz = 0.0

		var by := low_h + t0
		var sy := step
		_append_voxel_face(
			out_quads,
			float(x) + ox, by, float(z) + oz,
			step, sy, 1.0,
			step, 1.0,
			vox, FACE_TOP
		)

		if i < steps - 1:
			var riser_x := float(x) + (t1 if dx >= 0.0 else t0)
			var riser_z := float(z) + (t1 if dz >= 0.0 else t0)
			if x_axis:
				_append_voxel_face(
					out_quads,
					riser_x, by, float(z) + oz,
					0.001, sy, 1.0,
					1.0, sy,
					vox, FACE_POS_X if dx > 0.0 else FACE_NEG_X
				)
			if z_axis:
				_append_voxel_face(
					out_quads,
					float(x) + ox, by, riser_z,
					step if x_axis else 1.0, sy, 0.001,
					step if x_axis else 1.0, sy,
					vox, FACE_POS_Z if dz > 0.0 else FACE_NEG_Z
				)

	if x_axis:
		var low_face_x := float(x) + (0.0 if dx > 0.0 else 1.0)
		var high_face_x := float(x) + (1.0 if dx > 0.0 else 0.0)
		_append_voxel_face(
			out_quads,
			low_face_x, low_h, float(z),
			0.001, 1.0, 1.0,
			1.0, 1.0,
			vox, FACE_NEG_X if dx > 0.0 else FACE_POS_X
		)
		_append_voxel_face(
			out_quads,
			high_face_x, low_h, float(z),
			0.001, 1.0, 1.0,
			1.0, 1.0,
			vox, FACE_POS_X if dx > 0.0 else FACE_NEG_X
		)
	if z_axis:
		var low_face_z := float(z) + (0.0 if dz > 0.0 else 1.0)
		var high_face_z := float(z) + (1.0 if dz > 0.0 else 0.0)
		_append_voxel_face(
			out_quads,
			float(x), low_h, low_face_z,
			1.0, 1.0, 0.001,
			1.0, 1.0,
			vox, FACE_NEG_Z if dz > 0.0 else FACE_POS_Z
		)
		_append_voxel_face(
			out_quads,
			float(x), low_h, high_face_z,
			1.0, 1.0, 0.001,
			1.0, 1.0,
			vox, FACE_POS_Z if dz > 0.0 else FACE_NEG_Z
		)

	if not z_axis:
		_append_voxel_face(
			out_quads,
			float(x), low_h, float(z),
			1.0, 1.0, 0.001,
			1.0, 1.0,
			vox, FACE_NEG_Z
		)
		_append_voxel_face(
			out_quads,
			float(x), low_h, float(z) + 1.0,
			1.0, 1.0, 0.001,
			1.0, 1.0,
			vox, FACE_POS_Z
		)
	if not x_axis:
		_append_voxel_face(
			out_quads,
			float(x), low_h, float(z),
			0.001, 1.0, 1.0,
			1.0, 1.0,
			vox, FACE_NEG_X
		)
		_append_voxel_face(
			out_quads,
			float(x) + 1.0, low_h, float(z),
			0.001, 1.0, 1.0,
			1.0, 1.0,
			vox, FACE_POS_X
		)


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


func _sample_height(data: ChunkData, lx: int, lz: int) -> float:
	if lx >= 0 and lx < ChunkData.SIZE and lz >= 0 and lz < ChunkData.SIZE:
		return data.get_surface_y(lx, lz)
	if data.world:
		var gx := float(data.position.x * ChunkData.SIZE + lx)
		var gz := float(data.position.y * ChunkData.SIZE + lz)
		return data.world.get_surface_height_uncached(gx, gz)
	return 0.0


func _ramp_covers_drop(data: ChunkData, low_x: int, low_z: int, toward_high: Vector2i) -> bool:
	if low_x < 0 or low_x >= ChunkData.SIZE or low_z < 0 or low_z >= ChunkData.SIZE:
		return false
	return data.has_ramp(low_x, low_z) and data.get_ramp_dir(low_x, low_z) == toward_high


func _emit_surface_side_walls(data: ChunkData, normal_dir: Vector3i, face_code: int, out_quads: Array):
	var dx = normal_dir.x
	var dz = normal_dir.z
	if dx == 0 and dz == 0:
		return

	if abs(dx) == 1:
		for x in range(ChunkData.SIZE):
			var run_start = -1
			var run_h: float = 0.0
			var run_t = 0
			for z in range(ChunkData.SIZE + 1):
				var has_wall = false
				var curr_h: float = 0.0
				var curr_t = 0
				if z < ChunkData.SIZE:
					curr_h = data.get_surface_y(x, z)
					curr_t = data.get_tile_type(x, z)
					var nx = x + dx
					var nz = z
					var neighbor_h: float = _sample_height(data, nx, nz)
					var diff: float = curr_h - neighbor_h
					if diff > CLIFF_HEIGHT:
						has_wall = true
					elif diff > 0.1:
						var toward_high := Vector2i(-dx, 0)
						has_wall = not _ramp_covers_drop(data, nx, nz, toward_high)
				if has_wall and (run_start == -1 or is_equal_approx(curr_h, run_h) and curr_t == run_t):
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
	elif abs(dz) == 1:
		for z in range(ChunkData.SIZE):
			var run_start = -1
			var run_h: float = 0.0
			var run_t = 0
			for x in range(ChunkData.SIZE + 1):
				var has_wall = false
				var curr_h: float = 0.0
				var curr_t = 0
				if x < ChunkData.SIZE:
					curr_h = data.get_surface_y(x, z)
					curr_t = data.get_tile_type(x, z)
					var nx = x
					var nz = z + dz
					var neighbor_h: float = _sample_height(data, nx, nz)
					var diff: float = curr_h - neighbor_h
					if diff > CLIFF_HEIGHT:
						has_wall = true
					elif diff > 0.1:
						var toward_high := Vector2i(0, -dz)
						has_wall = not _ramp_covers_drop(data, nx, nz, toward_high)
				if has_wall and (run_start == -1 or is_equal_approx(curr_h, run_h) and curr_t == run_t):
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
	data._compute_column_maps(true)
					
func _emit_cave_faces(data: ChunkData, out_quads: Array) -> void:
	if data.world == null:
		return
	for lx in range(ChunkData.SIZE):
		for lz in range(ChunkData.SIZE):
			var wx: float = float(data.position.x * ChunkData.SIZE + lx)
			var wz: float = float(data.position.y * ChunkData.SIZE + lz)
			var surf: float = data.get_surface_y(lx, lz)
			var y_min: int = maxi(0, int(surf) - CAVE_MESH_DEPTH)
			var y_max: int = int(surf) - 1
			if y_max < y_min:
				continue
			for y in range(y_min, y_max + 1):
				var wy: float = float(y)
				var vox: int = data.world.get_voxel(wx, wy, wz)
				if vox == VoxelTypes.AIR:
					continue
				if data.world.get_voxel(wx, wy + 1.0, wz) == VoxelTypes.AIR:
					_append_voxel_face(
						out_quads,
						float(lx), wy, float(lz),
						1.0, 1.0, 1.0,
						1.0, 1.0,
						vox, FACE_TOP
					)
				if data.world.get_voxel(wx - 1.0, wy, wz) == VoxelTypes.AIR:
					_append_voxel_face(
						out_quads,
						float(lx), wy, float(lz),
						0.001, 1.0, 1.0,
						1.0, 1.0,
						vox, FACE_NEG_X
					)
				if data.world.get_voxel(wx + 1.0, wy, wz) == VoxelTypes.AIR:
					_append_voxel_face(
						out_quads,
						float(lx) + 1.0, wy, float(lz),
						0.001, 1.0, 1.0,
						1.0, 1.0,
						vox, FACE_POS_X
					)
				if data.world.get_voxel(wx, wy, wz - 1.0) == VoxelTypes.AIR:
					_append_voxel_face(
						out_quads,
						float(lx), wy, float(lz),
						1.0, 1.0, 0.001,
						1.0, 1.0,
						vox, FACE_NEG_Z
					)
				if data.world.get_voxel(wx, wy, wz + 1.0) == VoxelTypes.AIR:
					_append_voxel_face(
						out_quads,
						float(lx), wy, float(lz) + 1.0,
						1.0, 1.0, 0.001,
						1.0, 1.0,
						vox, FACE_POS_Z
					)


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
		chunk_ready.emit(data.position, data)
	else:
		print("ERROR: Failed to instantiate ChunkView for position: ", data.position)

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
	return null

func rebuild_chunks():
	for coord: Vector2i in chunks.keys():
		request_chunk(coord)
		
func spawn_area_ready(center_x:int, center_z:int) -> bool:
	var r := 0
	for x in range(center_x - r, center_x + r + 1):
		for z in range(center_z - r, center_z + r + 1):
			var key = Vector2i(x, z)
			if not chunks.has(key):
				return false
	return true
