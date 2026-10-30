extends SceneTree

const _TerrainLook = preload("res://helpers/terrain_look.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var amp := _TerrainLook.amplitude_steps()
	var max_jump := 0
	var span := 64
	for z in span:
		for x in span:
			var a := _TerrainLook.offset_steps(float(x) / 8.0, float(z) / 8.0)
			var bx := _TerrainLook.offset_steps(float(x + 1) / 8.0, float(z) / 8.0)
			var bz := _TerrainLook.offset_steps(float(x) / 8.0, float(z + 1) / 8.0)
			if absi(a) > amp:
				failed = true
			max_jump = maxi(max_jump, absi(a - bx))
			max_jump = maxi(max_jump, absi(a - bz))
	var seam := 0
	for z in 32:
		var left := _TerrainLook.offset_steps(15.0 + 7.5 / 8.0, float(z) / 8.0)
		var right := _TerrainLook.offset_steps(16.0 + 0.5 / 8.0, float(z) / 8.0)
		if absi(left - right) > 1:
			seam += 1
	if max_jump > 1 or seam > 0 or failed:
		push_error("surface wave step fail max_jump=%d seam=%d amp=%d" % [max_jump, seam, amp])
		failed = true
	else:
		print("OK surface wave amp=%d max_neighbor_step=%d seam=%d" % [amp, max_jump, seam])

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.set("world_seed", 12349)
	var cm = _ChunkManager.new()
	cm.set("world", world)
	cm.set("ramp_placement_chance", 28)
	var layer: float = _WorldSettings.get_active().layer_height()
	var flat_ok := 0
	for z in 8:
		for x in 8:
			if _TerrainRamps.ramp_direction_at(world, x, z) != Vector2i.ZERO:
				continue
			var base: float = world.get_surface_height(float(x), float(z))
			var walk: float = _TerrainRamps.walkable_height(world, float(x) + 0.3, float(z) + 0.7)
			if absf(walk - (base + layer)) > 0.02:
				push_error("collision waved at %d,%d walk=%.3f flat=%.3f" % [x, z, walk, base + layer])
				failed = true
			else:
				flat_ok += 1
	if flat_ok > 0 and not failed:
		print("OK collision stays flat columns=%d" % flat_ok)

	var total := 0
	var tops := 0
	var sides := 0
	var ramps := 0
	var n := 0
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			var chunk = _ChunkData.new(Vector2i(cx, cz), world)
			chunk.capture_worker_snapshot()
			chunk._compute_column_maps(true)
			var built: Dictionary = cm._build_mesh(chunk)
			var quads: Array = built.get("quads", [])
			n += 1
			total += quads.size()
			for q in quads:
				var fc := int(q.get("face_code", -1))
				if fc == 0:
					tops += 1
				elif fc >= 7:
					ramps += 1
				else:
					sides += 1
	print("WAVE_QUADS chunks=%d quads=%d per=%.1f tops=%d sides=%d ramps=%d amp=%d" % [
		n, total, float(total) / float(n), tops, sides, ramps, amp
	])
	if failed:
		quit(1)
		return
	print("SURFACE WAVE OK")
	quit(0)
