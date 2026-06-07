class_name ChunkData
extends RefCounted

const SIZE := 16
const HEIGHT := 256

var position: Vector2i
var voxels: PackedByteArray

func _init(pos: Vector2i):
	position = pos
	voxels = PackedByteArray()
	voxels.resize(SIZE * SIZE * HEIGHT)

# Spatial layout: Y layers contain Z rows, which contain X columns
func _index(x: int, y: int, z: int) -> int:
	return (y * SIZE * SIZE) + (z * SIZE) + x

func set_voxel(x: int, y: int, z: int, v: int):
	# Boundary guard prevents crashes from out-of-bounds thread calls
	if x < 0 or x >= SIZE or y < 0 or y >= HEIGHT or z < 0 or z >= SIZE:
		return
	voxels[_index(x, y, z)] = v

func get_voxel(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0:
		return 0
	if x >= SIZE or y >= HEIGHT or z >= SIZE:
		return 0
	return voxels[_index(x, y, z)]
