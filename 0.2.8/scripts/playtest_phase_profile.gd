extends SceneTree
## Phase-time dig/build on main scene to locate ≥12ms hitches.


const MAIN_SCENE := "res://scenes/main.tscn"
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _CrystalTextureGenerator = preload("res://systems/crystal_texture_generator.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	if root.get_node_or_null("CrystalTextureGenerator") == null:
		var gen := _CrystalTextureGenerator.new()
		gen.name = "CrystalTextureGenerator"
		root.add_child(gen)
	call_deferred("_run")


func _run() -> void:
	var game = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(game)
	var player = null
	var editor = null
	var world = null
	var cm = null
	for _i in 400:
		player = get_first_node_in_group("player")
		editor = get_first_node_in_group("terrain_editor")
		world = get_first_node_in_group("world")
		cm = get_first_node_in_group("chunk_manager")
		if player and editor and world and bool(player.get("world_ready")):
			break
		await process_frame
	if editor == null:
		push_error("boot fail")
		_ProbeExit.finish_tree(self, 1, "PHASE PROFILE FAIL")
		return

	var inv := _Inventory.new()
	inv.add_item("wood", 80)
	_BuildingRegistry.ensure_builtins()
	var px := 20
	var pz := 20
	if player.has_method("get_voxel_position"):
		var pv: Vector3 = player.get_voxel_position()
		px = int(floor(pv.x)) + 4
		pz = int(floor(pv.z)) + 4

	var lines: PackedStringArray = []
	lines.append("# Hot-path phase profile (main.tscn)")
	lines.append("")

	editor.try_dig(Vector3(float(px) + 0.5, 0, float(pz) + 0.5))
	await process_frame
	await process_frame

	var dig_state := {
		"ms": 0.0, "inv": 0.0, "water": 0.0, "emit": 0.0, "state_only": 0.0, "n": 0
	}
	var n := 16
	for i in n:
		var cx := px + (i % 8)
		var cz := pz + 2 + int(i / 8)
		var t0 := Time.get_ticks_usec()
		_TerrainEdits.dig(cx, cz, 1)
		var t1 := Time.get_ticks_usec()
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if world.has_method("invalidate_column_cache"):
					world.invalidate_column_cache(cx + dx, cz + dz)
		if cm.has_method("invalidate_columns_at_world"):
			cm.invalidate_columns_at_world(cx, cz)
		if cm.has_method("flush_rebuild_pending"):
			cm.flush_rebuild_pending()
		var t2 := Time.get_ticks_usec()
		if editor.has_method("_notify_water_reflow"):
			editor._notify_water_reflow(cx, cz, true)
		var t3 := Time.get_ticks_usec()
		if editor.has_signal("terrain_edited"):
			editor.terrain_edited.emit(cx, cz, &"dig")
		var t4 := Time.get_ticks_usec()
		dig_state.ms += float(t4 - t0) / 1000.0
		dig_state.state_only += float(t1 - t0) / 1000.0
		dig_state.inv += float(t2 - t1) / 1000.0
		dig_state.water += float(t3 - t2) / 1000.0
		dig_state.emit += float(t4 - t3) / 1000.0
		dig_state.n += 1

	lines.append("## Dig phases (n=%d)" % n)
	lines.append("- state_only_avg_ms=%.3f" % (dig_state.state_only / n))
	lines.append("- invalidate_flush_avg_ms=%.3f" % (dig_state.inv / n))
	lines.append("- water_reflow_avg_ms=%.3f" % (dig_state.water / n))
	lines.append("- emit_listeners_avg_ms=%.3f" % (dig_state.emit / n))
	lines.append("- total_avg_ms=%.3f" % (dig_state.ms / n))
	print("DIG state=%.3f inv=%.3f water=%.3f emit=%.3f total=%.3f" % [
		dig_state.state_only / n,
		dig_state.inv / n,
		dig_state.water / n,
		dig_state.emit / n,
		dig_state.ms / n,
	])

	var b_ms := 0.0
	for i in n:
		var cx2 := px + (i % 8)
		var cz2 := pz + 5 + int(i / 8)
		var t0b := Time.get_ticks_usec()
		editor.try_build(Vector3(float(cx2) + 0.5, 0, float(cz2) + 0.5), inv, &"wood_wall")
		var t1b := Time.get_ticks_usec()
		b_ms += float(t1b - t0b) / 1000.0
	lines.append("")
	lines.append("## Build try_build total (n=%d)" % n)
	lines.append("- total_avg_ms=%.3f" % (b_ms / n))
	print("BUILD total_avg_ms=%.3f" % (b_ms / n))

	var ch_ms := 0.0
	var ch_n := 6
	for i in ch_n:
		var t0c := Time.get_ticks_usec()
		if editor.has_method("_channel_dig"):
			editor._channel_dig(px + 12 + i, pz + 8, inv)
		var t1c := Time.get_ticks_usec()
		ch_ms += float(t1c - t0c) / 1000.0
	lines.append("")
	lines.append("## Channel dig (n=%d)" % ch_n)
	lines.append("- total_avg_ms=%.3f" % (ch_ms / ch_n))
	print("CHANNEL avg_ms=%.3f" % (ch_ms / ch_n))

	var path := "/tmp/grok-goal-3df95600d6a4/implementer/hotpath_phases.md"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	_ProbeExit.finish_tree(self, 0, "HOTPATH PHASE PROFILE OK")
