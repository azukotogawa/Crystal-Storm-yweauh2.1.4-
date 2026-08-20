extends SceneTree
## Measure GameVisualRegistry / generate_image across teleports (measure only).
##
## Usage:
##   CRYSTALSTORM_BAKE_RADIUS=2 godot --headless -s scripts/profile_teleport_visuals.gd


func _initialize() -> void:
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_PERF_PRESET").is_empty():
		OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	call_deferred("_run")


func _run() -> void:
	print("=== TELEPORT VISUAL REGEN PROFILE ===")
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		push_error("scene fail")
		quit(1)
		return
	await process_frame
	await process_frame

	var frames := 0
	var reg = null
	var player = null
	var world = null
	var cm = null
	var gen = null
	while frames < 1500:
		await process_frame
		frames += 1
		var root := current_scene
		if root == null:
			continue
		var tree := root.get_tree()
		reg = tree.get_first_node_in_group("game_visual_registry")
		player = tree.get_first_node_in_group("player")
		world = tree.get_first_node_in_group("world")
		cm = tree.get_first_node_in_group("chunk_manager")
		var composition = tree.get_first_node_in_group("composition_root")
		gen = tree.root.get_node_or_null("CrystalTextureGenerator")
		if composition and int(composition.stage) >= 7 and reg and player and bool(reg.get("_initialized")):
			break

	if reg == null or player == null:
		push_error("missing reg/player")
		quit(1)
		return

	# Arm generators after boot so we measure teleport delta only.
	if reg.has_method("reset_trace_counters"):
		reg.reset_trace_counters()
	if gen and gen.has_method("set_gen_trace_enabled"):
		gen.set_gen_trace_enabled(true)
		gen.reset_gen_trace()
	elif reg.get("_gen") != null:
		gen = reg._gen
		if gen.has_method("set_gen_trace_enabled"):
			gen.set_gen_trace_enabled(true)
			gen.reset_gen_trace()

	var snap0 := _snap(reg, gen)
	print("[TPVis] baseline after boot: ", JSON.stringify(snap0))

	# Three teleports far enough to force stream
	var offsets: Array[Vector2] = [
		Vector2(128, 128),
		Vector2(-192, 64),
		Vector2(256, -128),
	]
	var per_tp: Array = []
	for off in offsets:
		if reg.has_method("reset_trace_counters"):
			reg.reset_trace_counters()
		if gen and gen.has_method("reset_gen_trace"):
			gen.reset_gen_trace()
		var before := _snap(reg, gen)
		_teleport(player, world, cm, off)
		# Allow stream + feature populate frames
		for _i in 90:
			await process_frame
		var after := _snap(reg, gen)
		var delta := {
			"offset": [off.x, off.y],
			"bundle_gen_delta": int(after.get("bundle_gen_count", 0)) - int(before.get("bundle_gen_count", 0)),
			"refresh_all_delta": int(after.get("refresh_all_count", 0)) - int(before.get("refresh_all_count", 0)),
			"refresh_scene_delta": int(after.get("refresh_scene_count", 0)) - int(before.get("refresh_scene_count", 0)),
			"trace": after.get("trace", {}),
			"gen_trace": after.get("gen_trace", {}),
			"bundle_ready": after.get("bundle_ready"),
			"cache_size": after.get("cache_size"),
		}
		per_tp.append(delta)
		print("[TPVis] teleport ", off, " delta=", JSON.stringify(delta))

	# Explicit clear_cache to show what regeneration looks like (control)
	if reg.has_method("reset_trace_counters"):
		reg.reset_trace_counters()
	if gen and gen.has_method("reset_gen_trace"):
		gen.reset_gen_trace()
	if reg.has_method("clear_cache"):
		reg.clear_cache("probe_control")
	if reg.has_method("preload_game_bundle"):
		reg.preload_game_bundle(false, "probe_control_after_clear")
	var control := _snap(reg, gen)
	print("[TPVis] control after clear_cache+preload: ", JSON.stringify(control))

	var report := {
		"baseline": snap0,
		"teleports": per_tp,
		"control_full_regen": control,
		"bundle_key_count_expected": 41,
		"generate_image_per_full_bundle": 35,  # combat+entity+veg+building; items use generate_item_icon
	}
	_print_summary(report)

	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-23417f42e77b/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)
	var path := scratch.path_join("teleport_visuals_profile.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
		print("WROTE ", path)
	print("=== TELEPORT VISUAL REGEN PROFILE END ===")
	quit(0)


func _snap(reg, gen) -> Dictionary:
	var d := {
		"bundle_gen_count": int(reg.get("_bundle_gen_count")) if "_bundle_gen_count" in reg else -1,
		"refresh_all_count": int(reg.get("_refresh_all_count")) if "_refresh_all_count" in reg else -1,
		"refresh_scene_count": int(reg.get("_refresh_scene_count")) if "_refresh_scene_count" in reg else -1,
		"bundle_ready": bool(reg.get("_bundle_ready")) if "_bundle_ready" in reg else false,
		"cache_size": int(reg._cache.size()) if "_cache" in reg and reg._cache is Dictionary else -1,
	}
	if reg and reg.has_method("get_trace_refresh_counts"):
		d["trace"] = reg.get_trace_refresh_counts()
	if gen and gen.has_method("get_gen_trace"):
		d["gen_trace"] = gen.get_gen_trace()
	return d


func _teleport(player, world, cm, off: Vector2) -> void:
	var base := Vector2.ZERO
	if cm and cm.has_method("get_player_chunk_coord"):
		var c: Vector2i = cm.get_player_chunk_coord()
		base = Vector2(float(c.x * 16 + 8), float(c.y * 16 + 8))
	elif player and player.has_method("get_voxel_position"):
		var v: Vector3 = player.get_voxel_position()
		base = Vector2(v.x, v.z)
	var wx := base.x + off.x
	var wz := base.y + off.y
	var sy := 20.0
	if world and world.has_method("get_surface_height"):
		sy = float(world.get_surface_height(wx, wz))
	if "voxel_position" in player:
		player.voxel_position = Vector3(wx, sy + 2.0, wz)
		if player.has_method("_sync_global_from_voxel"):
			player._sync_global_from_voxel()
	else:
		player.global_position = Vector3(wx, sy + 2.0, wz)


func _print_summary(report: Dictionary) -> void:
	print("\n========== TELEPORT → VISUAL SUMMARY ==========")
	print("Expected full bundle: ~41 keys, ~35 generate_image via generate_texture")
	print("210 generate_image ≈ ~6 full bundle regenerations (35*6) if fully rebuilt")
	var any_regen := false
	for tp in report.get("teleports", []):
		var gt: Dictionary = tp.get("gen_trace", {})
		var tr: Dictionary = tp.get("trace", {})
		var imgs := int(gt.get("generate_image_count", 0))
		var bundle_d := int(tp.get("bundle_gen_delta", 0))
		print("TP %s: generate_image=%d bundle_gen_delta=%d refresh_all=%s preload_regen=%s fallback_gen=%s callers_refresh=%s callers_preload=%s" % [
			str(tp.get("offset")),
			imgs,
			bundle_d,
			tr.get("refresh_all", 0),
			tr.get("preload_regen", 0),
			tr.get("fallback_generate", 0),
			tr.get("refresh_callers", []),
			tr.get("preload_callers", []),
		])
		if imgs > 0 or bundle_d > 0 or int(tr.get("preload_regen", 0)) > 0:
			any_regen = true
	var ctrl: Dictionary = report.get("control_full_regen", {})
	var cgt: Dictionary = ctrl.get("gen_trace", {})
	print("CONTROL clear+preload generate_image=%s generate_texture=%s" % [
		cgt.get("generate_image_count", -1), cgt.get("generate_texture_count", -1),
	])
	print("teleport_caused_texture_regeneration=%s" % str(any_regen))
	print("================================================\n")
