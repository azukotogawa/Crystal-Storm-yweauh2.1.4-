class_name IsoMath
extends RefCounted

const TILE_WIDTH := 64.0
const TILE_HEIGHT := 32.0
const VOXEL_HEIGHT := 16.0

static var rotation := 0

static func voxel_to_screen(x:int, y:int, z:int) -> Vector2:

	var rx := x
	var ry := y

	match rotation:
		0: # NE
			pass

		1: # NW
			rx = -y
			ry = x

		2: # SW
			rx = -x
			ry = -y

		3: # SE
			rx = y
			ry = -x

	return Vector2(
		(rx - ry) * (TILE_WIDTH * 0.5),
		(rx + ry) * (TILE_HEIGHT * 0.5) - z * VOXEL_HEIGHT
	)
