class_name TerrainLook
extends RefCounted

const SURFACE_WAVE_AMPLITUDE_STEPS := 2
const STEPS_PER_BLOCK := 8
const _WAVE_SCALE := 1.05

static func palette_color(rel: int) -> Color:
	var band := palette_band(rel)
	match band:
		0:
			return Color(78.0 / 255.0, 136.0 / 255.0, 52.0 / 255.0)
		1:
			return Color(92.0 / 255.0, 152.0 / 255.0, 58.0 / 255.0)
		3:
			return Color(122.0 / 255.0, 180.0 / 255.0, 72.0 / 255.0)
		4:
			return Color(138.0 / 255.0, 192.0 / 255.0, 82.0 / 255.0)
		_:
			return Color(106.0 / 255.0, 166.0 / 255.0, 64.0 / 255.0)


static func amplitude_steps() -> int:
	return maxi(SURFACE_WAVE_AMPLITUDE_STEPS, 0)


static func column_waves(tile: int) -> bool:
	if tile < 0 or tile == VoxelTypes.AIR or tile <= VoxelTypes.OCEAN3:
		return false
	if tile == VoxelTypes.RIVER or tile == VoxelTypes.WATER:
		return false
	return true


static func paints_height(tile: int) -> bool:
	return tile >= VoxelTypes.GRASSLAND and tile <= VoxelTypes.GRASSLAND5


static func offset_steps(px: float, pz: float) -> int:
	var amp := amplitude_steps()
	if amp <= 0:
		return 0
	var w := _wave(px, pz)
	if amp <= 1:
		w += sin(TAU * (px * 1.7 + pz * 1.15) / 3.1 + 0.4) * 0.28
	var n := clampf(w / _WAVE_SCALE, -1.0, 1.0)
	return clampi(int(round(n * float(amp))), -amp, amp)


static func palette_band(rel: int) -> int:
	var amp := maxi(amplitude_steps(), 1)
	return clampi(int(round(float(rel) / float(amp) * 1.5 + 2.0)), 0, 4)


static func shade_for_band(band: int) -> float:
	return 0.88 + float(clampi(band, 0, 4)) * 0.015


static func _wave(px: float, pz: float) -> float:
	var s1 := sin(TAU * (px * 0.8 + pz * 0.35) / 4.5 + 0.7) * 0.5
	var s2 := sin(TAU * (-px * 0.3 + pz * 0.9) / 3.4 + 1.9) * 0.35
	return s1 + s2 + (_noise(px, pz) - 0.5) * 0.6


static func _noise(px: float, pz: float) -> float:
	var cell := 5.0
	var x := px / cell
	var z := pz / cell
	var x0 := int(floor(x))
	var z0 := int(floor(z))
	var fx := x - float(x0)
	var fz := z - float(z0)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var v00 := _hash_unit(x0, z0)
	var v10 := _hash_unit(x0 + 1, z0)
	var v01 := _hash_unit(x0, z0 + 1)
	var v11 := _hash_unit(x0 + 1, z0 + 1)
	return lerpf(lerpf(v00, v10, fx), lerpf(v01, v11, fx), fz)


static func _hash_unit(ix: int, iz: int) -> float:
	var n: int = ix * 374761393 + iz * 668265263
	n = n & 2147483647
	n = n ^ (n >> 13)
	n = (n * 1274126177) & 2147483647
	return float(n) / 2147483647.0
