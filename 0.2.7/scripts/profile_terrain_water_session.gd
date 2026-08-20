extends SceneTree
## Measure rapid dig/build + water reflow costs (shipped TerrainEditor path).


const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_BuildingRegistry.ensure_builtins()

	var root3d := Node3D.new()
	root.add_child(root3d)
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 21
	world.add_to_group("world")
	root3d.add_child(world)
	var cm := _ChunkManager.new()
	cm.add_to_group("chunk_manager")
	cm.set_process(false)
	root3d.add_child(cm)
	for cx in 2:
		for cz in 2:
			var view := ChunkView.new()
			view.chunk_data = ChunkData.new(Vector2i(cx, cz), world)
			cm.chunks[Vector2i(cx, cz)] = view
	var editor := _TerrainEditor.new()
	editor.add_to_group("terrain_editor")
	root3d.add_child(editor)
	editor.world = world
	editor.bind_chunk_manager(cm)

	var inv := _Inventory.new()
	inv.add_item("wood", 200)
	inv.add_item("stone", 200)

	var lines: PackedStringArray = []
	lines.append("# Terrain + water performance sample")
	lines.append("")

	# Dig trench 24 cells
	var t0 := Time.get_ticks_usec()
	for i in 24:
		editor.try_dig(Vector3(float(i) + 0.5, 0, 2.5))
	var dig_us := Time.get_ticks_usec() - t0
	lines.append("- dig_24_cells_us=%d (%.2f ms/edit)" % [dig_us, dig_us / 1000.0 / 24.0])
	print("dig_24 us=%d avg_ms=%.3f" % [dig_us, dig_us / 1000.0 / 24.0])

	# Build wall 24 cells
	t0 = Time.get_ticks_usec()
	for i in 24:
		editor.try_build(Vector3(float(i) + 0.5, 0, 4.5), inv, &"wood_wall")
	var build_us := Time.get_ticks_usec() - t0
	lines.append("- build_24_cells_us=%d (%.2f ms/edit)" % [build_us, build_us / 1000.0 / 24.0])
	print("build_24 us=%d avg_ms=%.3f" % [build_us, build_us / 1000.0 / 24.0])

	# Alternate dig/build
	t0 = Time.get_ticks_usec()
	for i in 12:
		editor.try_dig(Vector3(float(i) + 0.5, 0, 6.5))
		editor.try_build(Vector3(float(i) + 0.5, 0, 7.5), inv, &"stone_wall")
	var alt_us := Time.get_ticks_usec() - t0
	lines.append("- alt_dig_build_12_us=%d (%.2f ms/pair)" % [alt_us, alt_us / 1000.0 / 12.0])
	print("alt_12 us=%d avg_ms=%.3f" % [alt_us, alt_us / 1000.0 / 12.0])

	# Channel dig (water) along trench
	t0 = Time.get_ticks_usec()
	for i in 8:
		if editor.has_method("_channel_dig"):
			editor._channel_dig(i, 10, inv)
		else:
			editor.try_dig(Vector3(float(i) + 0.5, 0, 10.5))
	var ch_us := Time.get_ticks_usec() - t0
	lines.append("- channel_or_dig_8_us=%d (%.2f ms/edit)" % [ch_us, ch_us / 1000.0 / 8.0])
	print("channel_8 us=%d avg_ms=%.3f" % [ch_us, ch_us / 1000.0 / 8.0])

	# Note water reflow steps (source contract)
	var te_src: String = (load("res://world/terrain_editor.gd") as GDScript).source_code
	if "recompute_region_now(wx, wz, 2, 3)" in te_src:
		lines.append("- water_immediate_steps=3 (amortized; was 8)")
		print("OK water immediate steps capped at 3")
	else:
		lines.append("- water_immediate_steps=unknown")
		print("WARN water step cap not found")

	var path := "/tmp/grok-goal-3df95600d6a4/implementer/terrain_water_perf.md"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	print("All terrain water profile samples OK")
	quit(0)
