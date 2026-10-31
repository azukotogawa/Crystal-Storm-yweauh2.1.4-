class_name TerrainLook
extends RefCounted

const SURFACE_WAVE_AMPLITUDE_STEPS := 2
const STEPS_PER_BLOCK := 8
const _WAVE_SCALE := 0.85
const _WARP_CELL := 23.0
const _WARP_AMOUNT := 7.0
const _DETAIL_CELL := 4.0
const _DETAIL_AMOUNT := 0.4
const _WAVES := [
	[0.92, 0.39, 7.3, 0.7, 0.40],
	[-0.31, 0.95, 5.3, 1.9, 0.30],
	[0.57, -0.82, 3.9, 3.1, 0.18],
	[0.99, 0.14, 11.7, 4.4, 0.25],
]


static func amplitude_steps() -> int:
	return maxi(SURFACE_WAVE_AMPLITUDE_STEPS, 0)


static func max_offset(layer: float) -> float:
	return float(amplitude_steps()) * layer / float(STEPS_PER_BLOCK)


static func column_waves(tile: int) -> bool:
	if tile < 0 or tile == VoxelTypes.AIR or tile <= VoxelTypes.OCEAN3:
		return false
	if tile == VoxelTypes.RIVER or tile == VoxelTypes.WATER:
		return false
	return true



static func offset_steps(px: float, pz: float) -> int:
	var amp := amplitude_steps()
	if amp <= 0:
		return 0
	var n := clampf(_wave(px, pz) / _WAVE_SCALE, -1.0, 1.0)
	return clampi(int(round(n * float(amp))), -amp, amp)


static func max_step_per_micro_column() -> float:
	var g := 0.0
	for wv in _WAVES:
		g += float(wv[4]) * TAU / float(wv[2])
	g *= 1.0 + _WARP_AMOUNT * 1.5 / _WARP_CELL
	g += _DETAIL_AMOUNT * 1.5 / _DETAIL_CELL
	return g / _WAVE_SCALE * float(amplitude_steps()) / float(STEPS_PER_BLOCK)




static func _wave(px: float, pz: float) -> float:
	var wx := px + (_noise_cell(px + 71.3, pz - 19.1, _WARP_CELL) - 0.5) * _WARP_AMOUNT
	var wz := pz + (_noise_cell(px - 43.7, pz + 88.9, _WARP_CELL) - 0.5) * _WARP_AMOUNT
	var w := 0.0
	for wv in _WAVES:
		w += float(wv[4]) * sin(TAU * (wx * float(wv[0]) + wz * float(wv[1])) / float(wv[2]) + float(wv[3]))
	return w + (_noise_cell(px, pz, _DETAIL_CELL) - 0.5) * _DETAIL_AMOUNT


static func _noise_cell(px: float, pz: float, cell: float) -> float:
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
