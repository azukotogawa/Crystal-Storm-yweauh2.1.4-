extends SceneTree
## Same-frame dig/build must change VoxelFloorProbe height.
## The height-cache key must not alias one feet hint with another edit delta.
## Usage: godot --headless -s scripts/verify_floor_probe_live_edit.gd


const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelFloorProbe = preload("res://player/voxel_floor_probe.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")


var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed = true
	push_error(msg)


func _near_layer(before: float, after: float, layer: float) -> bool:
	return absf((after - before) - layer) <= 0.05


func _run() -> void:
	_TerrainEdits.reset()
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	var probe := _VoxelFloorProbe.new()
	probe.configure(world, null, null)
	var frame := Engine.get_physics_frames()
	_test_same_frame_edit(probe, world)
	_test_hint_delta_key_does_not_alias(probe, world)
	if Engine.get_physics_frames() != frame:
		_fail("floor probe live-edit checks crossed a physics frame")
	_TerrainEdits.reset()
	if _failed:
		print("Floor probe live edit tests FAILED")
		quit(1)
		return
	print("All floor probe live edit tests OK")
	quit(0)


## Build, then dig past the cached zero so both deltas are new keys.
func _test_same_frame_edit(probe, world) -> void:
	var cx := 8
	var cz := 8
	var layer: float = _WorldSettings.get_active().layer_height()
	var sx := float(cx) + 0.5
	var sz := float(cz) + 0.5
	var surf: float = world.get_surface_height(sx, sz)
	probe.feet_height_hint = surf + layer
	var h0: float = probe.walkable_height_at(sx, sz)
	var f0: float = probe.sample_walkable_feet(sx, sz)
	var c0: float = probe.cached_column_center_walkable(world, null, cx, cz)
	if not _TerrainEdits.build_wall(cx, cz, _VoxelTypes.STONE):
		_fail("build_wall failed")
		return
	var h1: float = probe.walkable_height_at(sx, sz)
	var f1: float = probe.sample_walkable_feet(sx, sz)
	var c1: float = probe.cached_column_center_walkable(world, null, cx, cz)
	if not _near_layer(h0, h1, layer) or not _near_layer(f0, f1, layer) or not _near_layer(c0, c1, layer):
		_fail(
			"same-frame build did not raise floor h %.3f->%.3f feet %.3f->%.3f center %.3f->%.3f"
			% [h0, h1, f0, f1, c0, c1]
		)
		return
	# +1 -> 0 -> -1. The negative delta was never cached.
	if not _TerrainEdits.dig(cx, cz, 1) or not _TerrainEdits.dig(cx, cz, 1):
		_fail("dig failed")
		return
	var h2: float = probe.walkable_height_at(sx, sz)
	var f2: float = probe.sample_walkable_feet(sx, sz)
	var c2: float = probe.cached_column_center_walkable(world, null, cx, cz)
	if not _near_layer(h2, h0, layer) or not _near_layer(f2, f0, layer) or not _near_layer(c2, c0, layer):
		_fail(
			"same-frame dig did not lower floor h %.3f->%.3f feet %.3f->%.3f center %.3f->%.3f"
			% [h0, h2, f0, f2, c0, c2]
		)
		return
	print("OK same-frame build raises and dig lowers floor probe")


## (hint 65536, delta 0) and (hint 65536 ^ (delta_i << 16), one layer) share the old XOR key.
func _test_hint_delta_key_does_not_alias(probe, world) -> void:
	var cx := 10
	var cz := 10
	var layer: float = _WorldSettings.get_active().layer_height()
	var delta_i := int(round(layer * 100.0))
	var hint_a := 65536
	var hint_b := hint_a ^ (delta_i << 16)
	var feet_a := float(hint_a) / 50.0
	var feet_b := float(hint_b) / 50.0
	if int(round(feet_a * 50.0)) != hint_a or int(round(feet_b * 50.0)) != hint_b:
		_fail("hint feet round-trip failed a=%s b=%s" % [hint_a, hint_b])
		return
	var sx := float(cx) + 0.5
	var sz := float(cz) + 0.5
	var surf: float = world.get_surface_height(sx, sz)
	if feet_a <= surf or feet_b <= surf:
		_fail("alias hints overlap the column surface")
		return
	probe.feet_height_hint = feet_a
	var h0: float = probe.walkable_height_at(sx, sz)
	var f0: float = probe.sample_walkable_feet(sx, sz)
	if not _TerrainEdits.build_wall(cx, cz, _VoxelTypes.STONE):
		_fail("alias build_wall failed")
		return
	probe.feet_height_hint = feet_b
	var h1: float = probe.walkable_height_at(sx, sz)
	var f1: float = probe.sample_walkable_feet(sx, sz)
	if not _near_layer(h0, h1, layer) or not _near_layer(f0, f1, layer):
		_fail(
			"hint/delta cache key aliased a build h %.3f->%.3f feet %.3f->%.3f"
			% [h0, h1, f0, f1]
		)
		return
	print("OK floor cache key does not alias hint %d with delta %d" % [hint_a, delta_i])
