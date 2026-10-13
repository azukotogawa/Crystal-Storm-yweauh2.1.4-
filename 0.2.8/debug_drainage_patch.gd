# debug_drainage_patch.gd
# PR1 validation: drainage patch build + cross-patch stitch assertions.
# Run: godot --headless --path . debug_drainage_patch.gd
extends SceneTree

const TEST_PCX := 104
const TEST_PCZ := 64
const SEED := 12349

func _init() -> void:
	print("=== Drainage Patch Debug (seed %d, origin %d,%d) ===" % [SEED, TEST_PCX, TEST_PCZ])
	var world := InfiniteNoiseWorld.new(SEED)
	var elev_fn := Callable(world, "_compute_raw_elevation")
	var meander_fn := Callable(world, "_river_meander_offset")
	var trib_fn := Callable(world, "_river_tributary_noise")
	var cache: Dictionary = {}

	var patch = RiverDrainage.build_drainage_patch(
		TEST_PCX, TEST_PCZ, SEED, elev_fn, meander_fn, trib_fn, cache
	)

	print("Segments: %d" % patch.segments.size())
	var max_acc := 0.0
	for i in patch.flow_acc.size():
		max_acc = maxf(max_acc, patch.flow_acc[i])
	print("Max interior flow_acc: %.1f" % max_acc)

	if patch.segments.size() == 0:
		print("FAIL: no segments")
		quit(1)
		return

	for seg in patch.segments:
		if seg.hydraulic_points.size() >= 2:
			var a: Vector2 = seg.hydraulic_points[0]
			var b: Vector2 = seg.hydraulic_points[seg.hydraulic_points.size() - 1]
			print("  seg#%d acc=%.1f order=%d pts=%d  (%.0f,%.0f)->(%.0f,%.0f)" % [
				seg.segment_id, seg.acc, seg.order, seg.hydraulic_points.size(), a.x, a.y, b.x, b.y
			])

	var stitch_cases := [
		{"hx": 0, "hz": 0, "up": Vector2i(-1, -1), "norigin": Vector2i(TEST_PCX - 32, TEST_PCZ - 32), "local": Vector2i(30, 30)},
		{"hx": 0, "hz": 16, "up": Vector2i(-1, 16), "norigin": Vector2i(TEST_PCX - 32, TEST_PCZ), "local": Vector2i(30, 15)},
		{"hx": 16, "hz": 0, "up": Vector2i(16, -1), "norigin": Vector2i(TEST_PCX, TEST_PCZ - 32), "local": Vector2i(15, 30)},
		{"hx": 33, "hz": 33, "up": Vector2i(34, 34), "norigin": Vector2i(TEST_PCX + 32, TEST_PCZ + 32), "local": Vector2i(1, 1)},
	]

	var stitch_ok := true
	for c in stitch_cases:
		var norigin := RiverDrainage.neighbor_patch_origin_for_up_cell(c.up, TEST_PCX, TEST_PCZ)
		var local := RiverDrainage.stitch_test_local(c.up, TEST_PCX, TEST_PCZ)
		var ok: bool = norigin == c.norigin and local == c.local
		print("Stitch (%d,%d) up=%s -> norigin=%s local=%s %s" % [
			c.hx, c.hz, str(c.up), str(norigin), str(local), "OK" if ok else "FAIL"
		])
		if not ok:
			stitch_ok = false

	if not stitch_ok:
		print("FAIL: stitch coordinate assertions")
		quit(1)
		return

	print("PASS: drainage patch + stitch assertions")
	quit(0)