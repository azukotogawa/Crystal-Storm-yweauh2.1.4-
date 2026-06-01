# chunk_view.gd
class_name ChunkView
extends Node2D

@onready var renderer: MultiMeshInstance2D = $Renderer

var chunk_data: ChunkData
var texture: Texture2D

var thread := Thread.new()
var queue := []
var lock := Mutex.new()
var quads := []

const FACES = [
	Vector3i(0, 1, 0),   # top
	Vector3i(1, 0, 0),   # right
	Vector3i(-1, 0, 0),  # left
	Vector3i(0, -1, 0),  # bottom (optional)
	Vector3i(0, 0, 1),   # front (3D extension)
	Vector3i(0, 0, -1)   # back
]

func setup(data: ChunkData, tex: Texture):
	chunk_data = data
	texture = tex

	if not is_node_ready():
		await ready
	
	_build_and_emit()

func is_face_visible(x:int, y:int, z:int, dx:int, dy:int, dz:int) -> bool:
	var nx = x + dx
	var ny = y + dy
	var nz = z + dz

	if nx < 0 or ny < 0 or nz < 0 or nx >= ChunkData.SIZE or ny >= ChunkData.SIZE or nz >= ChunkData.HEIGHT:
		return true

	return chunk_data.get_voxel(nx, ny, nz) == VoxelTypes.AIR


func _build_and_emit():
	if renderer == null:
		push_error("ChunkView: Renderer is still null!")
		return

	quads.clear()

	build_height_map()
	build_top_surface()

	quads.sort_custom(func(a, b):
		return a["sort_key"] < b["sort_key"]
	)

	emit_quads()
	
var height_map := []
var top_type_map := []

func build_height_map():
	height_map.clear()
	top_type_map.clear()

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
				top_type_map[x].append(
					chunk_data.get_voxel(x, y, h)
				)

func emit_quads():
	if renderer == null or not is_instance_valid(renderer):
		push_error("ChunkView: Renderer is null or invalid.")
		return
		
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.instance_count = quads.size()

	var mesh := QuadMesh.new()
	mesh.size = Vector2(64, 64)
	mm.mesh = mesh
	
	renderer.multimesh = mm

	for i in range(quads.size()):
		var q = quads[i]

		var center_x = q.x + (q.w - 1) * 0.5
		var center_y = q.y + (q.h - 1) * 0.5

		var chunk_offset_x = chunk_data.position.x * ChunkData.SIZE
		var chunk_offset_y = chunk_data.position.y * ChunkData.SIZE
		var pos = IsoMath.voxel_to_screen(
			center_x + chunk_offset_x,
			center_y + chunk_offset_y,
			q.z
		)

		var t = Transform2D.IDENTITY
		t.origin = pos

		mm.set_instance_transform_2d(i, t)
		# encode size in custom data (for shader or scaling)
		var voxel_type = q.type
		if voxel_type == VoxelTypes.AIR:
			continue
		var coord = get_atlas_coord(voxel_type)
		mm.set_instance_custom_data(
			i,
			Color(
				coord.x / 255.0,
				coord.y / 255.0,
				min(q.w / 255.0, 1.0),
				min(q.h / 255.0, 1.0)
			)
		)

func build_top_surface():
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

			# mark used
			for dx in range(w):
				for dy in range(d):
					used[x + dx][y + dy] = true

			for dx in range(w):
				for dy in range(d):
					emit_surface_quad(
						x + dx,
						y + dy,
						1,
						1,
						h
					)

func emit_surface_quad(x:int, y:int, w:int, d:int, h:int):
	var chunk_offset_x = chunk_data.position.x * ChunkData.SIZE
	var chunk_offset_y = chunk_data.position.y * ChunkData.SIZE

	var screen_pos = IsoMath.voxel_to_screen(
		x + chunk_offset_x,
		y + chunk_offset_y,
		h
	)

	var depth_y = screen_pos.y + h * IsoMath.VOXEL_HEIGHT
	
	var voxel_type = chunk_data.get_voxel(x, y, h)

	quads.append({
		"x": x,
		"y": y,
		"w": w,
		"h": d,
		"z": h,
		"type": voxel_type,
		"sort_key": depth_y
	})
			
func get_atlas_coord(voxel_type: int) -> Vector2i:
	if voxel_type == VoxelTypes.AIR:
		return Vector2i(6, 0)
	return VoxelTypes.ATLAS_COORDS.get(voxel_type, Vector2i(6, 0))
