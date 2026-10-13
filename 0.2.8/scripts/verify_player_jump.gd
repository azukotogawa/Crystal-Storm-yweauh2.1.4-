extends SceneTree
## Verifies jump landing uses walkable floor probe (world heightfield, no scene tree required).

const _VoxelFloorProbe = preload("res://player/voxel_floor_probe.gd")


func _init() -> void:
	var failed := false
	var world_scr = load("res://world/InfiniteNoiseWorld.gd")
	var world = world_scr.new()
	world.world_seed = 99

	var probe := _VoxelFloorProbe.new()
	probe.configure(world, null, null)
	var feet := probe.sample_walkable_feet(4.5, 6.5)
	if feet <= 0.0:
		push_error("probe sample_walkable_feet should be positive")
		failed = true
	else:
		print("OK probe walkable feet=", feet)

	var grounded := probe.is_grounded_at(Vector3(4.5, feet, 6.5))
	if not grounded:
		push_error("player should be grounded at walkable feet height")
		failed = true
	else:
		print("OK grounded at walkable height")

	var snapped: Vector3 = probe.snap_position_y(Vector3(4.5, feet + 3.0, 6.5))
	if snapped.y > feet + 0.5:
		push_error("snap_position_y should pull airborne player toward floor")
		failed = true
	else:
		print("OK snap_position_y from jump apex -> ", snapped.y)

	world = null

	if failed:
		quit(1)
	print("All player jump probe tests OK")
	quit(0)