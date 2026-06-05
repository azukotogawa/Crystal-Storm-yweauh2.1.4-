class_name ChunkData
extends RefCounted

const SIZE := 16
const HEIGHT := 50

var position: Vector2i
var voxels: PackedByteArray

func _init(pos: Vector2i):
	position = pos
	voxels = PackedByteArray()
	voxels.resize(SIZE * SIZE * HEIGHT)

func _index(x:int, y:int, z:int) -> int:
	return z * SIZE * SIZE + y * SIZE + x

func set_voxel(x:int, y:int, z:int, v:int):
	voxels[_index(x,y,z)] = v

func get_voxel(x:int, y:int, z:int) -> int:
	if x < 0 or y < 0 or z < 0:
		return 0
	if x >= SIZE or y >= SIZE or z >= HEIGHT:
		return 0
	return voxels[_index(x,y,z)]
