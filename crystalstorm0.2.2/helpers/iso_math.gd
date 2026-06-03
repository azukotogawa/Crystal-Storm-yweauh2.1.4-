class_name IsoMath
extends RefCounted

const TILE_WIDTH := 64.0
const TILE_HEIGHT := 32.0
const VOXEL_HEIGHT := 16.0

static var rotation := 0

static func voxel_to_screen(x: float, y: float, z: float) -> Vector2:
	var rx := x
	var ry := y

	match rotation:
		0: pass 
		1: 
			rx = -y
			ry = x
		2: 
			rx = -x
			ry = -y
		3: 
			rx = y
			ry = -x

	return Vector2(
		(rx - ry) * (TILE_WIDTH * 0.5),
		(rx + ry) * (TILE_HEIGHT * 0.5) - z * VOXEL_HEIGHT
	)
	
static func iso_depth(x:float, y:float, z:float) -> float:
	var screen := IsoMath.voxel_to_screen(x, y, z)
	return screen.y + z * IsoMath.VOXEL_HEIGHT
