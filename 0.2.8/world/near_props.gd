extends Node3D

const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _TerrainLook = preload("res://helpers/terrain_look.gd")
var radius: int = 1
var max_cubes_per_chunk: int = 480
const PROP_CHANCE := 18
const GRASS_D := Color(0.30, 0.50, 0.24)
const GRASS_L := Color(0.40, 0.58, 0.28)
const GRASS_Y := Color(0.48, 0.64, 0.26)
const STONE := Color(0.50, 0.52, 0.56)
const STONE_L := Color(0.62, 0.64, 0.68)
const PETALS := [Color(0.92, 0.80, 0.30), Color(0.90, 0.88, 0.82), Color(0.78, 0.46, 0.62)]

var manager: Node = null
var _center := Vector2i(-99999, -99999)
var _built: Dictionary = {}
var _queue: Array = []
var _mesh: BoxMesh
var _mat: StandardMaterial3D


func apply_render_tier(radius_chunks: int, max_cubes: int) -> void:
	radius = maxi(radius_chunks, 0)
	max_cubes_per_chunk = maxi(max_cubes, 0)
	if radius <= 0 or max_cubes_per_chunk <= 0:
		for k in _built.keys():
			var doomed: Node = _built[k]
			if is_instance_valid(doomed):
				doomed.queue_free()
		_built.clear()
		_queue.clear()
		return
	# Drop anything outside the new radius.
	var drop: Array = []
	for k2 in _built.keys():
		if _far(k2):
			drop.append(k2)
	for k3 in drop:
		var node: Node = _built[k3]
		if is_instance_valid(node):
			node.queue_free()
		_built.erase(k3)


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var vs: float = _WorldSettings.get_active().voxel_scale / float(_TerrainLook.STEPS_PER_BLOCK)
	_mesh = BoxMesh.new()
	_mesh.size = Vector3(vs, vs, vs)
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 1.0
	_mesh.material = _mat


func set_center(c: Vector2i) -> void:
	if radius <= 0 or max_cubes_per_chunk <= 0:
		_center = c
		for k0 in _built.keys():
			var n0: Node = _built[k0]
			if is_instance_valid(n0):
				n0.queue_free()
		_built.clear()
		_queue.clear()
		return
	if c == _center:
		return
	_center = c
	for k in _built.keys():
		if _far(k):
			var n: Node = _built[k]
			if is_instance_valid(n):
				n.queue_free()
			_built.erase(k)
	_queue.clear()
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var k := c + Vector2i(dx, dz)
			if not _built.has(k):
				_queue.append(k)


func drop_chunk(k: Vector2i) -> void:
	if _built.has(k):
		var n: Node = _built[k]
		if is_instance_valid(n):
			n.queue_free()
		_built.erase(k)
		if not _far(k):
			_queue.append(k)


func _far(k: Vector2i) -> bool:
	return maxi(absi(k.x - _center.x), absi(k.y - _center.y)) > radius


func _process(_dt: float) -> void:
	if _queue.is_empty() or manager == null:
		return
	var k: Vector2i = _queue.pop_front()
	if _built.has(k) or _far(k):
		return
	var view = manager.chunks.get(k)
	if view == null or view.chunk_data == null:
		_queue.append(k)
		return
	_built[k] = _build(view.chunk_data)


static func _hash(x: int, z: int, s: int) -> int:
	var h: int = (x * 73856093) ^ (z * 19349663) ^ (s * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0x7fffffff


func _build(data: ChunkData) -> Node3D:
	var ws = _WorldSettings.get_active()
	var bs: float = ws.voxel_scale
	var n := _TerrainLook.STEPS_PER_BLOCK
	var vs: float = bs / float(n)
	var xf: Array = []
	var cols: Array = []
	for lz in ChunkData.SIZE:
		for lx in ChunkData.SIZE:
			if xf.size() >= max_cubes_per_chunk:
				break
			var t: int = data.get_tile_type(lx, lz)
			if t < _VoxelTypes.GRASSLAND or t > _VoxelTypes.GRASSLAND5:
				continue
			var wx: int = data.position.x * ChunkData.SIZE + lx
			var wz: int = data.position.y * ChunkData.SIZE + lz
			var h := _hash(wx, wz, 1)
			if h % 100 >= PROP_CHANCE:
				continue
			var mx: int = 1 + (h >> 8) % (n - 2)
			var mz: int = 1 + (h >> 12) % (n - 2)
			var y: float = manager._column_micro_top(data, lx, lz, mx, mz)
			if y < -9000.0:
				continue
			var o := Vector3(float(wx) * bs + (float(mx) + 0.5) * vs, y + vs * 0.5, float(wz) * bs + (float(mz) + 0.5) * vs)
			var kind: int = (h >> 16) % 10
			if kind < 6:
				var c1: Color = GRASS_L if (h >> 20) & 1 == 0 else GRASS_Y
				for d in [Vector3(0, 0, 0), Vector3(vs, 0, 0), Vector3(0, 0, vs), Vector3(vs, 0, vs)]:
					_add(xf, cols, o + d, GRASS_D)
				_add(xf, cols, o + Vector3(0, vs, 0), c1)
				_add(xf, cols, o + Vector3(vs, vs, vs), c1)
				_add(xf, cols, o + Vector3(0, vs * 2.0, 0), c1)
				if (h >> 21) & 1 == 1:
					_add(xf, cols, o + Vector3(vs, vs * 2.0, vs), GRASS_Y)
			elif kind < 8:
				_add(xf, cols, o, STONE)
				_add(xf, cols, o + Vector3(vs, 0, 0), STONE_L)
				if (h >> 20) & 1 == 1:
					_add(xf, cols, o + Vector3(0, 0, vs), STONE)
					_add(xf, cols, o + Vector3(0, vs, 0), STONE_L)
			else:
				var pc: Color = PETALS[(h >> 20) % PETALS.size()]
				_add(xf, cols, o, GRASS_D)
				_add(xf, cols, o + Vector3(0, vs, 0), GRASS_D)
				var top := o + Vector3(0, vs * 2.0, 0)
				for d in [Vector3(0, 0, 0), Vector3(vs, 0, 0), Vector3(-vs, 0, 0), Vector3(0, 0, vs), Vector3(0, 0, -vs)]:
					_add(xf, cols, top + d, pc)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, xf[i]))
		mm.set_instance_color(i, cols[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _add(xf: Array, cols: Array, p: Vector3, c: Color) -> void:
	xf.append(p)
	cols.append(c)
