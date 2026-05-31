class_name Chunk
extends Node2D

const CHUNK_SIZE := 16
const WORLD_HEIGHT := 50

@export var cube_texture: Texture2D

var chunk_position := Vector2i.ZERO
var biome_world: InfiniteNoiseWorld
var voxel_world: VoxelWorld2
var voxels := []

@onready var renderer: MultiMeshInstance2D = $Renderer

func _ready():
	initialize_voxels()
	generate()
	rebuild_mesh()

func initialize_voxels():
	voxels.resize(CHUNK_SIZE)

	for x in CHUNK_SIZE:
		voxels[x] = []
		voxels[x].resize(CHUNK_SIZE)

		for y in CHUNK_SIZE:
			voxels[x][y] = []
			voxels[x][y].resize(WORLD_HEIGHT)

			for z in WORLD_HEIGHT:
				voxels[x][y][z] = VoxelTypes.OCEAN

func generate():
	for x in CHUNK_SIZE:
		for y in CHUNK_SIZE:
			var wx = x + chunk_position.x * CHUNK_SIZE
			var wy = y + chunk_position.y * CHUNK_SIZE

			var biome = biome_world.get_biome(wx, wy)
			var b_name = biome.name
			var height = biome.render_height
			
			var base_voxel_id = VoxelTypes.biome_to_voxel_id.get(b_name, VoxelTypes.AIR)
			
			for z in WORLD_HEIGHT:
				if z < height:
					voxels[x][y][z] = base_voxel_id
				else:
					voxels[x][y][z] = VoxelTypes.AIR
			

func get_voxel(x:int, y:int, z:int) -> int:
	if x < 0 or x >= CHUNK_SIZE:
		return VoxelTypes.AIR
	if y < 0 or y >= CHUNK_SIZE:
		return VoxelTypes.AIR
	if z < 0 or z >= WORLD_HEIGHT:
		return VoxelTypes.AIR

	return voxels[x][y][z]
	
func is_voxel_visible(x:int, y:int, z:int) -> bool:
	if get_voxel(x, y, z) == VoxelTypes.AIR:
		return false

	if get_voxel(x, y, z + 1) == VoxelTypes.AIR:
		return true
	if get_voxel(x + 1, y, z) == VoxelTypes.AIR:
		return true
	if get_voxel(x - 1, y, z) == VoxelTypes.AIR:
		return true
	if get_voxel(x, y + 1, z) == VoxelTypes.AIR:
		return true
	if get_voxel(x, y - 1, z) == VoxelTypes.AIR:
		return true

	return false

func rebuild_mesh():
	var visible_voxels := []

	for z in range(WORLD_HEIGHT):
		for y in range(CHUNK_SIZE):
			for x in range(CHUNK_SIZE):
				if is_voxel_visible(x, y, z):
					visible_voxels.append(Vector3i(x, y, z))

	var mm := MultiMesh.new()

	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.instance_count = 0
	mm.instance_count = visible_voxels.size()

	var mesh := QuadMesh.new()
	mesh.size = Vector2(64, 64)

	mm.mesh = mesh

	renderer.multimesh = mm
	renderer.texture = cube_texture
	
	for i in visible_voxels.size():
		var voxel: Vector3i = visible_voxels[i]

		var wx = voxel.x + chunk_position.x * CHUNK_SIZE
		var wy = voxel.y + chunk_position.y * CHUNK_SIZE

		var pos = IsoMath.voxel_to_screen(wx, wy, voxel.z)

		var t := Transform2D.IDENTITY
		t.origin = pos

		mm.set_instance_transform_2d(i, t)

		var voxel_type = get_voxel(
			voxel.x,
			voxel.y,
			voxel.z
		)
		var coord = VoxelTypes.ATLAS_COORDS[voxel_type]

		mm.set_instance_custom_data(
			i,
			Color(
				coord.x / 255.0,
				coord.y / 255.0,
				0.0
			)
		)
