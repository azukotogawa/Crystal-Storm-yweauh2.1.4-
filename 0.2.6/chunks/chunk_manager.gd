class_name ChunkManager
extends Node3D

const _WorldSettings = preload("res://config/world_settings.gd")
const _ChunkMeshBufferBuilder = preload("res://chunks/chunk_mesh_buffer_builder.gd")
const _VoxelGeometryKind = preload("res://helpers/voxel_geometry_kind.gd")

signal chunk_ready(coord: Vector2i, data: ChunkData)
signal chunk_unloaded(coord: Vector2i)

@export var RENDER_DISTANCE : int = 3
@export var MESH_CAVES : bool = false
@export var MAX_CHUNKS_PER_FRAME : int = 2
@export var MAX_INFLIGHT_CHUNKS : int = 6

var chunks: Dictionary[Vector2i, ChunkView] = {}
var pending := {}
var _chunk_tasks := {}  # coord -> WorkerThreadPool task id for async gen
var _chunk_gen_tokens := {}  # coord -> monotonic token; stale worker results are dropped
var _mesh_completion_queue: Array = []
var _shutting_down: bool = false

# Optimization: only update when player moves to new chunk
var _last_chunk_key: Vector2i = Vector2i(-99999, -99999)

# Player will be obtained via the 'player_ready' signal
var player: Node3D = null
var world: InfiniteNoiseWorld

const CHUNK_VIEW_SCENE = preload("res://scenes/ChunkView.tscn")

const _RAMP_DIRS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

var ramp_placement_chance: int = 28
var ramp_max_surface_height: float = 88.0
var ramp_mountain_cutoff_height: float = 72.0
var prebuild_chunk_buffers: bool = true
var chunk_upload_budget_us: int = 3500
var _rebuild_pending: Dictionary = {}

# Mirrored from WorldBorder — worker threads cannot call class_name statics reliably.
const _WB_PLAYABLE_HALF := 1024
const _WB_TRANSITION := 240.0

const FACE_TOP := 0
const FACE_BOTTOM := 2
const FACE_RAMP := 7
const FACE_RAMP_CORNER := 8
const FACE_RAMP_SIDE := 9
const FACE_NEG_X := 3
const FACE_POS_X := 4
const FACE_NEG_Z := 5
const FACE_POS_Z := 6

const CAVE_MESH_DEPTH := 32

func _ready():
	add_to_group("chunk_manager")
	TerrainRamps.invalidate_mesh_cache()

	player = get_tree().get_first_node_in_group("player")
	world = get_tree().get_first_node_in_group("world")
	
	if player == null:                                                          
		print("WARNING: Player node (group 'player') not found in _ready!")
	if world == null:                                                           
		print("WARNING: World node (group 'world') not found in _ready!")

	# Request initial chunks...
	if player and world:
		var col := _player_column_pos()
		var cx = floori(col.x / float(ChunkData.SIZE))
		var cz = floori(col.y / float(ChunkData.SIZE))
		update_stream(cx, cz)

func shutdown_workers() -> void:
	if _shutting_down:
		return
	_shutting_down = true
	_mesh_completion_queue.clear()
	for coord in _chunk_tasks.keys():
		_chunk_gen_tokens[coord] = int(_chunk_gen_tokens.get(coord, 0)) + 1
	var tasks: Array = _chunk_tasks.values()
	_chunk_tasks.clear()
	for tid in tasks:
		if tid is int:
			WorkerThreadPool.wait_for_task_completion(tid)


## Headless harness: drop chunk views before SceneTree quit to avoid teardown abort(134).
func release_all_chunks_for_teardown() -> void:
	shutdown_workers()
	_mesh_completion_queue.clear()
	for coord in _chunk_gen_tokens.keys():
		_chunk_gen_tokens[coord] = int(_chunk_gen_tokens.get(coord, 0)) + 1000
	var keys := chunks.keys()
	for key in keys:
		var view: ChunkView = chunks[key]
		if is_instance_valid(view):
			if view.get_parent() == self:
				remove_child(view)
			view.queue_free()
	chunks.clear()
	pending.clear()
	_rebuild_pending.clear()
	if has_meta("_rebuild_flush_scheduled"):
		remove_meta("_rebuild_flush_scheduled")


func _exit_tree() -> void:
	release_all_chunks_for_teardown()


func _unload_chunk_view(key: Vector2i) -> void:
	if not chunks.has(key):
		return
	var view: ChunkView = chunks[key]
	chunks.erase(key)
	if is_instance_valid(view):
		if view.get_parent() == self:
			remove_child(view)
		view.queue_free()
	chunk_unloaded.emit(key)

func request_chunk(coord: Vector2i, high_priority: bool = false):
	if chunks.has(coord) or pending.has(coord) or _chunk_tasks.has(coord):
		return
	_enqueue_chunk_generation(coord, high_priority)


func _enqueue_chunk_generation(coord: Vector2i, high_priority: bool = false) -> void:
	if pending.has(coord) or _chunk_tasks.has(coord):
		return
	if world == null:
		return

	pending[coord] = true
	var token: int = int(_chunk_gen_tokens.get(coord, 0)) + 1
	_chunk_gen_tokens[coord] = token

	var data := ChunkData.new(coord, world)
	if data == null:
		pending.erase(coord)
		return
	data.capture_worker_snapshot()

	var task_id := WorkerThreadPool.add_task(
		Callable(self, "_generate_chunk_task").bind(coord, data, token),
		high_priority
	)
	_chunk_tasks[coord] = task_id


func _regenerate_chunk_mesh(coord: Vector2i, high_priority: bool = true) -> void:
	if world == null or not chunks.has(coord):
		return
	_enqueue_chunk_generation(coord, high_priority)


func _build_mesh(data: ChunkData) -> Dictionary:
	var out_quads := []

	var concave_cells := _find_concave_corner_cells(data)
	_emit_ramps(data, out_quads, concave_cells)
	_emit_concave_corner_prisms(data, out_quads, concave_cells)
	data.finalize_surface_geometry()
	_emit_dug_strata(data, out_quads)
	_emit_build_strata(data, out_quads)
	_greedy_mesh_plane(data, Vector3i(0, 1, 0), FACE_TOP, out_quads)

	_greedy_mesh_plane(data, Vector3i(-1, 0, 0), FACE_NEG_X, out_quads)
	_greedy_mesh_plane(data, Vector3i(1, 0, 0), FACE_POS_X, out_quads)
	_greedy_mesh_plane(data, Vector3i(0, 0, -1), FACE_NEG_Z, out_quads)
	_greedy_mesh_plane(data, Vector3i(0, 0, 1), FACE_POS_Z, out_quads)
	_emit_cardinal_ramp_flank_faces(data, out_quads)
	if MESH_CAVES:
		_emit_cave_faces(data, out_quads)

	return {
		"quads": out_quads,
		"count": out_quads.size()
	}

func _skips_greedy_surface_cell(data: ChunkData, x: int, z: int) -> bool:
	return _VoxelGeometryKind.replaces_full_cube(data.get_geometry_kind(x, z))


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
				if visited[x][z] or _skips_greedy_surface_cell(data, x, z):
					continue
				var sy: float = data.get_surface_y(x, z)
				if sy >= float(ChunkData.HEIGHT):
					continue
				var vox := data.get_tile_type(x, z)
				if vox == VoxelTypes.AIR:
					continue

				var dx := 1
				while x + dx < ChunkData.SIZE and not visited[x + dx][z] \
						and not _skips_greedy_surface_cell(data, x + dx, z) \
						and is_equal_approx(data.get_surface_y(x + dx, z), sy) \
						and data.get_tile_type(x + dx, z) == vox:
					dx += 1

				var dz := 1
				while z + dz < ChunkData.SIZE:
					var can := true
					for xx in range(dx):
						var cx := x + xx
						var cz := z + dz
						if visited[cx][cz] or _skips_greedy_surface_cell(data, cx, cz) \
								or not is_equal_approx(data.get_surface_y(cx, cz), sy) \
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
	return TerrainRamps.is_step_height(diff)


func _cliff_height() -> float:
	return _WorldSettings.get_active().cliff_height()


func _has_player_build_at(data: ChunkData, x: int, z: int) -> bool:
	if data.get_worker_build_tile(x, z) >= 0:
		return true
	var layer_h: float = _WorldSettings.get_active().layer_height()
	var delta: float = data.get_worker_height_delta(x, z)
	return absf(delta) > layer_h * 0.08


func _should_place_ramp(world_x: int, world_z: int, dir: Vector2i, surface_h: float = -1.0) -> bool:
	if surface_h >= 0.0:
		if surface_h > ramp_max_surface_height:
			return false
		if _world_border_should_force_ramp(world_x, world_z) and surface_h > ramp_mountain_cutoff_height:
			return false
	var seed_val := world_x * 73856093 ^ world_z * 19349663 ^ dir.x * 83492791 ^ dir.y * 50331653
	return int(seed_val & 0x7fffffff) % 100 < ramp_placement_chance


func apply_world_gen_config(cfg) -> void:
	if cfg == null:
		return
	ramp_placement_chance = int(cfg.ramp_placement_chance)
	ramp_max_surface_height = float(cfg.ramp_max_surface_height)
	ramp_mountain_cutoff_height = float(cfg.mountain_ramp_cutoff_height)
	TerrainRamps.placement_chance = ramp_placement_chance


func apply_performance_config(cfg) -> void:
	if cfg == null:
		return
	RENDER_DISTANCE = int(cfg.render_distance)
	MAX_CHUNKS_PER_FRAME = int(cfg.max_chunks_per_frame)
	MAX_INFLIGHT_CHUNKS = int(cfg.max_inflight_chunks)
	MESH_CAVES = bool(cfg.mesh_caves)
	if "prebuild_chunk_buffers" in cfg:
		prebuild_chunk_buffers = bool(cfg.prebuild_chunk_buffers)
	if "chunk_upload_budget_us" in cfg:
		chunk_upload_budget_us = maxi(int(cfg.chunk_upload_budget_us), 500)


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


func _dirs_perpendicular(d1: Vector2i, d2: Vector2i) -> bool:
	return d1.x * d2.x + d1.y * d2.y == 0


## Cardinal landing only on the high side of a single step — not side cells with a higher opposite neighbor.
func _is_cardinal_landing_cell(
	data: ChunkData, x: int, z: int, toward_low: Vector2i, world_x: int, world_z: int
) -> bool:
	var cell_h: float = data.get_surface_y(x, z)
	var step_outs: Array = _step_out_dirs(data, x, z, cell_h, world_x, world_z)
	var opposite := Vector2i(-toward_low.x, -toward_low.y)
	for d_out in step_outs:
		if d_out == opposite or _dirs_perpendicular(d_out, toward_low):
			return false
	return true


func _ramp_entry_perpendicular_to(entry: Dictionary, toward_low: Vector2i) -> bool:
	if entry.is_empty() or toward_low == Vector2i.ZERO:
		return false
	var d_a: Vector2i = entry.get("dir", Vector2i.ZERO)
	var d_b: Vector2i = entry.get("dir2", Vector2i.ZERO)
	if d_a != Vector2i.ZERO and _dirs_perpendicular(d_a, toward_low):
		return true
	if d_b != Vector2i.ZERO and _dirs_perpendicular(d_b, toward_low):
		return true
	return false


## First landing wins in scan order — do not add a perpendicular ramp beside an existing one.
func _adjacent_perpendicular_ramp_blocks(
	data: ChunkData, x: int, z: int, toward_low: Vector2i
) -> bool:
	for d in _RAMP_DIRS:
		var nx: int = x + d.x
		var nz: int = z + d.y
		if not data.has_ramp(nx, nz):
			continue
		var entry: Dictionary = data.get_ramp_entry(nx, nz)
		if entry.get("concave", false):
			continue
		if _ramp_entry_perpendicular_to(entry, toward_low):
			return true
	return false


func _perpendicular_dirs(d: Vector2i) -> Array:
	return [Vector2i(-d.y, d.x), Vector2i(d.y, -d.x)]


func _step_out_dirs(data: ChunkData, x: int, z: int, low_h: float, world_x: int, world_z: int) -> Array:
	if _has_player_build_at(data, x, z):
		return []
	var out: Array = []
	for d in _RAMP_DIRS:
		if _has_player_build_at(data, x + d.x, z + d.y):
			continue
		var nh: float = _sample_height(data, x + d.x, z + d.y)
		if _is_step_height(nh - low_h) and _should_place_ramp(world_x, world_z, d, low_h):
			out.append(d)
	return out


## Cardinal ramps sit on the landing (higher) column, sloping down toward the lower neighbor.
func _step_in_dirs(data: ChunkData, x: int, z: int, cell_h: float, world_x: int, world_z: int) -> Array:
	if _has_player_build_at(data, x, z):
		return []
	var out: Array = []
	for d in _RAMP_DIRS:
		var lx: int = x - d.x
		var lz: int = z - d.y
		if _has_player_build_at(data, lx, lz):
			continue
		var lh: float = _sample_height(data, lx, lz)
		var toward_low := Vector2i(-d.x, -d.y)
		if _is_step_height(cell_h - lh) and _should_place_ramp(world_x, world_z, toward_low, cell_h):
			out.append(toward_low)
	return out


func _append_ramp_quad(out_quads: Array, x: int, z: int, low_h: float, vox: int, entry: Dictionary) -> void:
	var dir: Vector2i = entry.get("dir", Vector2i.ZERO)
	var dir2: Vector2i = entry.get("dir2", Vector2i.ZERO)
	var geo_kind: int = _VoxelGeometryKind.from_ramp_entry(entry)
	var face_code: int = _VoxelGeometryKind.face_code_for_kind(geo_kind)
	var quad := {
		"x": x,
		"y": low_h,
		"z": z,
		"dim_x": 1.0,
		"dim_y": 1.0,
		"dim_z": 1.0,
		"ramp_dir_x": dir.x,
		"ramp_dir_z": dir.y,
		"ramp_dir2_x": dir2.x,
		"ramp_dir2_z": dir2.y,
		"ramp_arm_h": float(entry.get("surface_h", low_h)),
		"uv_w": 1.0,
		"uv_h": 1.0,
		"type": vox,
		"face_code": face_code,
		"geometry_kind": geo_kind,
	}
	out_quads.append(quad)


func _is_cardinal_ramp_entry(entry: Dictionary) -> bool:
	return (
		not entry.is_empty()
		and not entry.get("concave", false)
		and not entry.get("corner", false)
		and entry.get("dir", Vector2i.ZERO) != Vector2i.ZERO
		and entry.get("dir2", Vector2i.ZERO) == Vector2i.ZERO
	)


func _append_voxel_face_toward(
	out_quads: Array, lx: float, ly: float, lz: float, vox: int, toward: Vector2i
) -> void:
	if toward == Vector2i(-1, 0):
		_append_voxel_face(out_quads, lx, ly, lz, 0.001, 1.0, 1.0, 1.0, 1.0, vox, FACE_NEG_X)
	elif toward == Vector2i(1, 0):
		_append_voxel_face(out_quads, lx + 1.0, ly, lz, 0.001, 1.0, 1.0, 1.0, 1.0, vox, FACE_POS_X)
	elif toward == Vector2i(0, -1):
		_append_voxel_face(out_quads, lx, ly, lz, 1.0, 1.0, 0.001, 1.0, 1.0, vox, FACE_NEG_Z)
	elif toward == Vector2i(0, 1):
		_append_voxel_face(out_quads, lx, ly, lz + 1.0, 1.0, 1.0, 0.001, 1.0, 1.0, vox, FACE_POS_Z)


func _emit_cardinal_ramp_flank_faces(data: ChunkData, out_quads: Array) -> void:
	# Cardinal ramps replace the full column mesh; same-height neighbors keep tops but lose
	# the vertical faces that used to abut the ramp cell.
	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			if not data.has_ramp(x, z):
				continue
			var entry: Dictionary = data.get_ramp_entry(x, z)
			if not _is_cardinal_ramp_entry(entry):
				continue
			var toward_low: Vector2i = entry.get("dir", Vector2i.ZERO)
			var ramp_h: float = data.get_surface_y(x, z)
			for perp in _perpendicular_dirs(toward_low):
				var nx: int = x + perp.x
				var nz: int = z + perp.y
				if nx < 0 or nx >= ChunkData.SIZE or nz < 0 or nz >= ChunkData.SIZE:
					continue
				if _has_player_build_at(data, nx, nz) or data.has_ramp(nx, nz):
					continue
				if _skips_greedy_surface_cell(data, nx, nz):
					continue
				if data.get_tile_type(nx, nz) == VoxelTypes.AIR:
					continue
				if not is_equal_approx(data.get_surface_y(nx, nz), ramp_h):
					continue
				var toward_ramp := Vector2i(-perp.x, -perp.y)
				_append_voxel_face_toward(
					out_quads, float(nx), ramp_h, float(nz), data.get_tile_type(nx, nz), toward_ramp
				)


func _append_full_cube_solid(out_quads: Array, x: int, z: int, y: float, vox: int) -> void:
	var geo := _VoxelGeometryKind.Kind.FULL_CUBE
	_append_voxel_face(out_quads, float(x), y, float(z), 1.0, 1.0, 1.0, 1.0, 1.0, vox, FACE_TOP, geo)
	_append_voxel_face(out_quads, float(x), y, float(z), 1.0, 1.0, 1.0, 1.0, 1.0, vox, FACE_BOTTOM, geo)
	_append_voxel_face(out_quads, float(x), y, float(z), 0.001, 1.0, 1.0, 1.0, 1.0, vox, FACE_NEG_X, geo)
	_append_voxel_face(out_quads, float(x) + 1.0, y, float(z), 0.001, 1.0, 1.0, 1.0, 1.0, vox, FACE_POS_X, geo)
	_append_voxel_face(out_quads, float(x), y, float(z), 1.0, 1.0, 0.001, 1.0, 1.0, vox, FACE_NEG_Z, geo)
	_append_voxel_face(out_quads, float(x), y, float(z) + 1.0, 1.0, 1.0, 0.001, 1.0, 1.0, vox, FACE_POS_Z, geo)


func _is_concave_corner_cell(data: ChunkData, x: int, z: int, arm_h: float) -> bool:
	var layer: float = _WorldSettings.get_active().layer_height()
	if x >= 0 and x < ChunkData.SIZE and z >= 0 and z < ChunkData.SIZE:
		if data.get_tile_type(x, z) == VoxelTypes.AIR:
			return true
		var sh: float = data.get_surface_y(x, z)
		return sh < arm_h - layer * 0.25
	var sh: float = _sample_height(data, x, z)
	return sh < 0.0 or sh < arm_h - layer * 0.25


func _tile_type_at(data: ChunkData, x: int, z: int) -> int:
	if x >= 0 and x < ChunkData.SIZE and z >= 0 and z < ChunkData.SIZE:
		return data.get_tile_type(x, z)
	# Worker path: never touch live world/registries for halo neighbors.
	return VoxelTypes.AIR


const _CONCAVE_L_PATTERNS := [
	{"arms": [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)], "leg_x": 1, "leg_z": 1},
	{"arms": [Vector2i(1, 0), Vector2i(0, -1), Vector2i(1, -1)], "leg_x": -1, "leg_z": 1},
	{"arms": [Vector2i(-1, 0), Vector2i(0, 1), Vector2i(-1, 1)], "leg_x": 1, "leg_z": -1},
	{"arms": [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], "leg_x": -1, "leg_z": -1},
]


func _find_concave_corner_cells(data: ChunkData) -> Dictionary:
	# Three solids in an L; concave cell (x,z) is the gap. Prism touches the two inner faces.
	var result: Dictionary = {}
	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			var cell := Vector2i(x, z)
			if result.has(cell) or _has_player_build_at(data, x, z):
				continue
			var world_x: int = data.position.x * ChunkData.SIZE + x
			var world_z: int = data.position.y * ChunkData.SIZE + z
			for pat in _CONCAVE_L_PATTERNS:
				var arms: Array = pat["arms"]
				var leg_x: int = pat["leg_x"]
				var leg_z: int = pat["leg_z"]
				var h: float = _sample_height(data, x + arms[2].x, z + arms[2].y)
				if h < 0.0:
					continue
				var valid := true
				for arm in arms:
					if not is_equal_approx(_sample_height(data, x + arm.x, z + arm.y), h):
						valid = false
						break
				if not valid:
					continue
				if not _is_concave_corner_cell(data, x, z, h):
					continue
				if not TerrainRamps.should_place_concave_prism(world_x, world_z, leg_x, leg_z):
					continue
				var vox: int = _tile_type_at(data, x + arms[2].x, z + arms[2].y)
				if vox == VoxelTypes.AIR:
					vox = _tile_type_at(data, x + arms[0].x, z + arms[0].y)
				result[cell] = {
					"h": h,
					"leg_x": leg_x,
					"leg_z": leg_z,
					"vox": vox,
				}
				break
	return result


func _emit_concave_corner_prisms(data: ChunkData, out_quads: Array, concave_cells: Dictionary) -> void:
	for cell in concave_cells:
		if _has_player_build_at(data, cell.x, cell.y):
			continue
		var entry: Dictionary = concave_cells[cell]
		var x: int = cell.x
		var z: int = cell.y
		var leg_x: int = entry["leg_x"]
		var leg_z: int = entry["leg_z"]
		var arm_h: float = entry["h"]
		var vox: int = entry["vox"]
		var layer: float = _WorldSettings.get_active().layer_height()
		data.set_concave_prism(x, z, leg_x, leg_z, arm_h)
		_append_full_cube_solid(out_quads, x, z, arm_h - layer, vox)
		_append_ramp_quad(out_quads, x, z, arm_h, vox, data.get_ramp_entry(x, z))


func _is_approach_cell_for_other_landing(cell: Vector2i, planned: Dictionary) -> bool:
	for landing_cell in planned.keys():
		if landing_cell == cell:
			continue
		var toward_low: Vector2i = planned[landing_cell]
		var approach_cell := Vector2i(landing_cell.x + toward_low.x, landing_cell.y + toward_low.y)
		if approach_cell == cell:
			return true
	return false


func _emit_ramps(data: ChunkData, out_quads: Array, concave_cells: Dictionary = {}) -> void:
	data.ramp_map.clear()
	data.geometry_map.clear()
	var planned: Dictionary = {}
	var landing_step_ins: Dictionary = {}

	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			var cell := Vector2i(x, z)
			if concave_cells.has(cell):
				continue
			if _has_player_build_at(data, x, z):
				continue
			if data.get_tile_type(x, z) == VoxelTypes.AIR:
				continue
			var cell_h: float = data.get_surface_y(x, z)
			var world_x: int = data.position.x * ChunkData.SIZE + x
			var world_z: int = data.position.y * ChunkData.SIZE + z
			var step_ins: Array = _step_in_dirs(data, x, z, cell_h, world_x, world_z)
			if not step_ins.is_empty():
				landing_step_ins[cell] = step_ins
				planned[cell] = step_ins[0]

	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			var cell := Vector2i(x, z)
			if concave_cells.has(cell):
				continue
			if _has_player_build_at(data, x, z):
				continue
			var low_h: float = data.get_surface_y(x, z)
			var vox := data.get_tile_type(x, z)
			if vox == VoxelTypes.AIR:
				continue

			if not planned.has(cell):
				continue

			if _is_approach_cell_for_other_landing(cell, planned):
				continue

			var world_x: int = data.position.x * ChunkData.SIZE + x
			var world_z: int = data.position.y * ChunkData.SIZE + z
			var step_ins: Array = landing_step_ins.get(cell, [])
			var toward_candidates: Array = step_ins if not step_ins.is_empty() else [planned[cell]]
			for d in toward_candidates:
				if _adjacent_perpendicular_ramp_blocks(data, x, z, d):
					continue
				if not _is_cardinal_landing_cell(data, x, z, d, world_x, world_z):
					continue
				data.set_ramp_cardinal(x, z, d)
				_append_ramp_quad(out_quads, x, z, low_h, vox, data.get_ramp_entry(x, z))
				break




func _strata_tile(surface_tile: int) -> int:
	match surface_tile:
		VoxelTypes.GRASSLAND, VoxelTypes.GRASSLAND2, VoxelTypes.GRASSLAND3, VoxelTypes.GRASSLAND4, VoxelTypes.GRASSLAND5:
			return VoxelTypes.DIRT
		VoxelTypes.DIRT, VoxelTypes.DIRT2:
			return VoxelTypes.DIRT2
		_:
			return VoxelTypes.STONE


func _emit_build_strata(data: ChunkData, out_quads: Array) -> void:
	if data.world == null:
		return
	var layer: float = _WorldSettings.get_active().layer_height()
	if layer <= 0.001:
		return
	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			if _skips_greedy_surface_cell(data, x, z):
				continue
			var delta: float = data.get_worker_height_delta(x, z)
			if delta <= layer * 0.15:
				continue
			var cur_h: float = data.get_surface_y(x, z)
			var wx: int = data.position.x * ChunkData.SIZE + x
			var wz: int = data.position.y * ChunkData.SIZE + z
			var natural_h: float = data.world.get_surface_height_worker(float(wx), float(wz), 0.0)
			var layers_built: int = maxi(1, int(round(delta / layer)))
			var tile: int = data.get_worker_build_tile(x, z)
			if tile < 0:
				tile = data.get_tile_type(x, z)
			if tile == VoxelTypes.AIR:
				continue
			for step in range(1, layers_built):
				var layer_y: float = natural_h + float(step) * layer
				if layer_y >= cur_h - layer * 0.05:
					break
				_append_voxel_face(out_quads, float(x), layer_y, float(z), 1.0, 1.0, 1.0, 1.0, 1.0, tile, FACE_TOP)
				_append_voxel_face(out_quads, float(x), layer_y, float(z), 0.001, 1.0, 1.0, 1.0, 1.0, tile, FACE_NEG_X)
				_append_voxel_face(out_quads, float(x) + 1.0, layer_y, float(z), 0.001, 1.0, 1.0, 1.0, 1.0, tile, FACE_POS_X)
				_append_voxel_face(out_quads, float(x), layer_y, float(z), 1.0, 1.0, 0.001, 1.0, 1.0, tile, FACE_NEG_Z)
				_append_voxel_face(out_quads, float(x), layer_y, float(z) + 1.0, 1.0, 1.0, 0.001, 1.0, 1.0, tile, FACE_POS_Z)


func _emit_dug_strata(data: ChunkData, out_quads: Array) -> void:
	if data.world == null:
		return
	var layer: float = _WorldSettings.get_active().layer_height()
	if layer <= 0.001:
		return
	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			if _skips_greedy_surface_cell(data, x, z):
				continue
			var delta: float = data.get_worker_height_delta(x, z)
			if delta >= -layer * 0.15:
				continue
			var cur_h: float = data.get_surface_y(x, z)
			var wx: int = data.position.x * ChunkData.SIZE + x
			var wz: int = data.position.y * ChunkData.SIZE + z
			var natural_h: float = data.world.get_surface_height_worker(float(wx), float(wz), 0.0)
			var depth_layers: int = maxi(1, int(round((natural_h - cur_h) / layer)))
			var top_tile: int = data.get_tile_type(x, z)
			if top_tile == VoxelTypes.AIR:
				continue
			for step in range(1, depth_layers + 1):
				var layer_y: float = cur_h + float(step) * layer
				if layer_y > natural_h + 0.01:
					break
				# Do not recreate the pre-dig horizontal cap at natural_h (greedy top uses cur_h).
				if layer_y >= natural_h - layer * 0.05:
					continue
				var tile: int = _strata_tile(top_tile) if step < depth_layers else top_tile
				out_quads.append({
					"x": x,
					"y": layer_y,
					"z": z,
					"dim_x": 1.0,
					"dim_y": 1.0,
					"dim_z": 1.0,
					"uv_w": 1.0,
					"uv_h": 1.0,
					"type": tile,
					"face_code": FACE_TOP,
				})
func _is_ramp_landing(data: ChunkData, x: int, z: int) -> bool:
	if not data.has_ramp(x, z):
		return false
	var entry: Dictionary = data.get_ramp_entry(x, z)
	return (
		not entry.get("approach", false)
		and not entry.get("corner", false)
		and entry.get("dir2", Vector2i.ZERO) == Vector2i.ZERO
	)


func _append_voxel_face(
	out_quads: Array,
	lx: float, ly: float, lz: float,
	sx: float, sy: float, sz: float,
	uv_w: float, uv_h: float,
	vox: int, face_code: int,
	geometry_kind: int = -1
) -> void:
	var quad := {
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
	}
	if geometry_kind >= 0:
		quad["geometry_kind"] = geometry_kind
	out_quads.append(quad)


func _process(_delta):
	_drain_mesh_queue()

	if player == null or world == null:
		return

	var col := _player_column_pos()
	var cx = floori(col.x / float(ChunkData.SIZE))
	var cz = floori(col.y / float(ChunkData.SIZE))
	var current_key := Vector2i(cx, cz)

	if not "_last_chunk_key" in self or _last_chunk_key != current_key:
		_last_chunk_key = current_key
		update_stream(cx, cz)


func _drain_mesh_queue() -> void:
	if _shutting_down:
		_mesh_completion_queue.clear()
		return
	var count_budget := maxi(MAX_CHUNKS_PER_FRAME, 1)
	var time_budget_us := maxi(chunk_upload_budget_us, 500)
	var t0 := Time.get_ticks_usec()
	var profiler = get_node_or_null("/root/PerfProfiler")
	while _mesh_completion_queue.size() > 0 and count_budget > 0:
		if Time.get_ticks_usec() - t0 >= time_budget_us:
			break
		var item: Dictionary = _mesh_completion_queue.pop_front()
		if profiler and profiler.has_method("begin"):
			profiler.begin("chunk_upload")
		_on_chunk_ready(item["data"], item["mesh"])
		if profiler and profiler.has_method("end"):
			profiler.end("chunk_upload")
		count_budget -= 1
	
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
	var inflight := _chunk_tasks.size() + _mesh_completion_queue.size()
	for item in to_request:
		if inflight >= MAX_INFLIGHT_CHUNKS:
			break
		var item_dict: Dictionary = item
		var dist: int = item_dict["dist"]
		var hp: bool = dist <= (RENDER_DISTANCE + 1)
		var req_key: Vector2i = item_dict["key"]
		request_chunk(req_key, hp)
		inflight += 1

	for key in chunks.keys().duplicate():
		if not needed.has(key):
			_unload_chunk_view(key)

	for key in pending.keys():
		if not needed.has(key):
			pending.erase(key)


func _player_column_pos() -> Vector2:
	if player and player.has_method("get_voxel_position"):
		var v: Vector3 = player.get_voxel_position()
		return Vector2(v.x, v.z)
	var ws = _WorldSettings.get_active()
	return Vector2(
		ws.world_to_column(player.global_position.x),
		ws.world_to_column(player.global_position.z)
	)


func _sample_height(data: ChunkData, lx: int, lz: int) -> float:
	var halo_h: float = data.get_halo_surface_y(lx, lz)
	if halo_h > -9000.0:
		return halo_h
	if lx >= 0 and lx < ChunkData.SIZE and lz >= 0 and lz < ChunkData.SIZE:
		return data.get_surface_y(lx, lz)
	# Worker path: rely on halo snapshot only (see capture_worker_snapshot).
	return 0.0


func _ramp_covers_drop(data: ChunkData, low_x: int, low_z: int, toward_high: Vector2i) -> bool:
	var hx: int = low_x + toward_high.x
	var hz: int = low_z + toward_high.y
	if hx < 0 or hx >= ChunkData.SIZE or hz < 0 or hz >= ChunkData.SIZE:
		return false
	if not data.has_ramp(hx, hz):
		return false
	var entry: Dictionary = data.get_ramp_entry(hx, hz)
	return entry.get("dir", Vector2i.ZERO) == Vector2i(-toward_high.x, -toward_high.y)


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
				if z < ChunkData.SIZE and not _skips_greedy_surface_cell(data, x, z):
					curr_h = data.get_surface_y(x, z)
					curr_t = data.get_tile_type(x, z)
					var nx = x + dx
					var nz = z
					var neighbor_h: float = _sample_height(data, nx, nz)
					var diff: float = curr_h - neighbor_h
					if diff > _cliff_height():
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
				if x < ChunkData.SIZE and not _skips_greedy_surface_cell(data, x, z):
					curr_h = data.get_surface_y(x, z)
					curr_t = data.get_tile_type(x, z)
					var nx = x
					var nz = z + dz
					var neighbor_h: float = _sample_height(data, nx, nz)
					var diff: float = curr_h - neighbor_h
					if diff > _cliff_height():
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

func _generate_chunk(data: ChunkData) -> void:
	if data == null or not data._has_worker_snapshot or data.world == null:
		return
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


func _on_chunk_ready(data: ChunkData, packed_quad_data: Dictionary) -> void:
	if not is_inside_tree() or _shutting_down:
		return
	if data == null or not pending.has(data.position):
		return
	pending.erase(data.position)
	if not packed_quad_data.has("count") or packed_quad_data.get("count", 0) == 0:
		return
	if chunks.has(data.position):
		var existing: ChunkView = chunks[data.position] as ChunkView
		if existing and is_instance_valid(existing):
			existing.setup(data, packed_quad_data)
			chunk_ready.emit(data.position, data)
			return
	var view: ChunkView = CHUNK_VIEW_SCENE.instantiate()
	if view == null:
		push_warning("ChunkManager: failed to instantiate ChunkView for %s" % str(data.position))
		return
	view.setup(data, packed_quad_data)
	add_child(view)
	chunks[data.position] = view
	chunk_ready.emit(data.position, data)


func _generate_chunk_task(coord: Vector2i, data: ChunkData, token: int) -> void:
	if data == null or not data._has_worker_snapshot:
		call_deferred("_on_chunk_task_complete", coord, null, {}, 0, 0, token)
		return
	# Worker: column maps + greedy mesh (uses halo snapshot — no live registry access).
	var t0 := Time.get_ticks_usec()
	_generate_chunk(data)
	var quads := _build_mesh(data)
	var mesh_us := Time.get_ticks_usec() - t0
	var buffer_us := 0
	var payload: Dictionary = quads.duplicate(true)
	if prebuild_chunk_buffers:
		var t_buf := Time.get_ticks_usec()
		payload = _ChunkMeshBufferBuilder.build_mesh_payload(data, quads.get("quads", []))
		buffer_us = Time.get_ticks_usec() - t_buf
	# Detach world ref before handing results back to main thread.
	data.world = null
	call_deferred("_on_chunk_task_complete", coord, data, payload, mesh_us, buffer_us, token)


func _on_chunk_task_complete(
	coord: Vector2i,
	data: ChunkData,
	packed_quad_data: Dictionary,
	mesh_us: int = 0,
	buffer_us: int = 0,
	token: int = -1
) -> void:
	_chunk_tasks.erase(coord)
	if _shutting_down or token < 0 or int(_chunk_gen_tokens.get(coord, -1)) != token:
		return
	if data == null:
		pending.erase(coord)
		return
	var profiler = get_node_or_null("/root/PerfProfiler")
	if mesh_us > 0 and profiler and profiler.has_method("record_us"):
		profiler.record_us("chunk_mesh", mesh_us)
		if profiler.has_method("record_worker_us"):
			profiler.record_worker_us(mesh_us)
	if buffer_us > 0 and profiler and profiler.has_method("record_us"):
		profiler.record_us("chunk_buffer", buffer_us)
		if profiler.has_method("record_worker_us"):
			profiler.record_worker_us(buffer_us)
	if not is_inside_tree() or not pending.has(coord):
		return
	if data.world == null and world != null:
		data.world = world
	_mesh_completion_queue.append({"coord": coord, "data": data, "mesh": packed_quad_data})

func get_ramp_dir_at_world(wx: float, wz: float) -> Vector2i:
	var entry := get_ramp_entry_at_world(wx, wz)
	return entry.get("dir", Vector2i.ZERO)


func get_ramp_entry_at_world(wx: float, wz: float) -> Dictionary:
	var ix := floori(wx)
	var iz := floori(wz)
	var chunk_coord := Vector2i(
		floori(float(ix) / float(ChunkData.SIZE)),
		floori(float(iz) / float(ChunkData.SIZE))
	)
	if not chunks.has(chunk_coord):
		return {}
	var data: ChunkData = chunks[chunk_coord].chunk_data
	var lx := ix - chunk_coord.x * ChunkData.SIZE
	var lz := iz - chunk_coord.y * ChunkData.SIZE
	if data.has_ramp(lx, lz):
		return data.get_ramp_entry(lx, lz)
	return {}


func get_chunk_data_at_world_pos(world_pos: Vector3) -> ChunkData:
	var chunk_x = floori(world_pos.x / float(ChunkData.SIZE))
	var chunk_z = floori(world_pos.z / float(ChunkData.SIZE))
	var chunk_coord = Vector2i(chunk_x, chunk_z)
	
	if chunks.has(chunk_coord):
		return chunks[chunk_coord].chunk_data
	return null

func rebuild_chunk_at_world(wx: float, wz: float) -> void:
	var key := Vector2i(
		floori(wx / float(ChunkData.SIZE)),
		floori(wz / float(ChunkData.SIZE))
	)
	rebuild_chunk(key)


func rebuild_region_at_world(wx: float, wz: float, ring: int = 1) -> void:
	var cx := floori(wx / float(ChunkData.SIZE))
	var cz := floori(wz / float(ChunkData.SIZE))
	for dx in range(-ring, ring + 1):
		for dz in range(-ring, ring + 1):
			_rebuild_pending[Vector2i(cx + dx, cz + dz)] = true
	if not is_inside_tree():
		return
	if not has_meta("_rebuild_flush_scheduled"):
		set_meta("_rebuild_flush_scheduled", true)
		call_deferred("_flush_rebuild_pending")


func flush_rebuild_pending() -> void:
	_flush_rebuild_pending()


func _flush_rebuild_pending() -> void:
	if has_meta("_rebuild_flush_scheduled"):
		remove_meta("_rebuild_flush_scheduled")
	if _rebuild_pending.is_empty():
		return
	var keys: Array = _rebuild_pending.keys()
	_rebuild_pending.clear()
	for key_variant in keys:
		rebuild_chunk(key_variant)


func await_rebuild_idle(max_frames: int = 2400) -> void:
	var frames := 0
	while (has_meta("_rebuild_flush_scheduled") or not _rebuild_pending.is_empty()) and frames < max_frames:
		await get_tree().process_frame
		frames += 1
	await get_tree().process_frame


func world_to_chunk_coord(wx: int, wz: int) -> Vector2i:
	return Vector2i(
		floori(float(wx) / float(ChunkData.SIZE)),
		floori(float(wz) / float(ChunkData.SIZE))
	)


func world_to_chunk_coord_v3(world_pos: Vector3) -> Vector2i:
	return world_to_chunk_coord(floori(world_pos.x), floori(world_pos.z))


func get_player_chunk_coord() -> Vector2i:
	var col := _player_column_pos()
	return Vector2i(
		floori(col.x / float(ChunkData.SIZE)),
		floori(col.y / float(ChunkData.SIZE))
	)


func is_chunk_loaded(coord: Vector2i) -> bool:
	return chunks.has(coord)


func is_world_cell_loaded(wx: int, wz: int) -> bool:
	return is_chunk_loaded(world_to_chunk_coord(wx, wz))


func is_world_pos_loaded(world_pos: Vector3) -> bool:
	return is_world_cell_loaded(floori(world_pos.x), floori(world_pos.z))


func rebuild_chunk(key: Vector2i) -> void:
	if _shutting_down:
		return
	_chunk_gen_tokens[key] = int(_chunk_gen_tokens.get(key, 0)) + 1
	if chunks.has(key):
		_regenerate_chunk_mesh(key, true)
		return
	pending.erase(key)
	_chunk_tasks.erase(key)
	request_chunk(key, true)


func rebuild_chunks():
	for coord: Vector2i in chunks.keys():
		rebuild_chunk(coord)
		
func spawn_area_ready(center_x:int, center_z:int) -> bool:
	var r := 0
	for x in range(center_x - r, center_x + r + 1):
		for z in range(center_z - r, center_z + r + 1):
			var key = Vector2i(x, z)
			if not chunks.has(key):
				return false
	return true
