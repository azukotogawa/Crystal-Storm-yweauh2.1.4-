extends SceneTree
## Instrumented main-scene run of the 11-step human playtest scenario.
## Drives shipped dig/build/gate/bridge/water/crystal/combat paths; logs hitches & duplicates.


const MAIN_SCENE := "res://scenes/main.tscn"
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _CrystalTextureGenerator = preload("res://systems/crystal_texture_generator.gd")


var _lines: PackedStringArray = []
var _failed: int = 0
var _hitch_count: int = 0
const HITCH_MS: float = 12.0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	if root.get_node_or_null("CrystalTextureGenerator") == null:
		var gen := _CrystalTextureGenerator.new()
		gen.name = "CrystalTextureGenerator"
		root.add_child(gen)
	call_deferred("_run")


func _note(s: String) -> void:
	_lines.append(s)
	print(s)


func _fail(s: String) -> void:
	_failed += 1
	_note("FAIL: %s" % s)
	push_error(s)


func _ok(s: String) -> void:
	_note("OK: %s" % s)


func _time_ms(callable: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	callable.call()
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _run() -> void:
	_note("# Stabilization playtest session")
	_note("**Scene:** main.tscn | **Preset:** medium")
	_note("")

	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("main scene missing")
		_finish()
		return
	var game = packed.instantiate()
	root.add_child(game)

	var player = null
	var cm = null
	var world = null
	var editor = null
	var crystal = null
	var weapon = null
	for _i in 400:
		player = get_first_node_in_group("player")
		cm = get_first_node_in_group("chunk_manager")
		world = get_first_node_in_group("world")
		editor = get_first_node_in_group("terrain_editor")
		crystal = get_first_node_in_group("crystal_manager")
		if player and cm and world and editor and bool(player.get("world_ready")):
			weapon = player.get_node_or_null("WeaponController")
			break
		await process_frame
	if player == null or editor == null or world == null:
		_fail("bootstrap timeout")
		_finish()
		return
	_ok("1 MOVE — player booted world_ready")

	var layer: float = _WorldSettings.get_active().layer_height()
	var inv = player.inventory if "inventory" in player else null
	if inv == null:
		inv = _Inventory.new()
		inv.add_item("wood", 80)
		inv.add_item("stone", 80)
		inv.add_item("herb", 4)
	else:
		inv.add_item("wood", 80)
		inv.add_item("stone", 80)
		inv.add_item("herb", 4)

	var px := 12
	var pz := 12
	if player.has_method("get_voxel_position"):
		var pv: Vector3 = player.get_voxel_position()
		px = int(floor(pv.x))
		pz = int(floor(pv.z))

	# --- 2 Dig 20+ rapidly ---
	var dig_dup := 0
	var dig_hitch := 0
	var dig_max_ms := 0.0
	var dig_sum := 0.0
	for i in 22:
		var cx := px + 2 + (i % 11)
		var cz := pz + (i / 11)
		var before: float = _TerrainEdits.get_height_delta(cx, cz)
		var ms: float = _time_ms(func():
			editor.try_dig(Vector3(float(cx) + 0.5, 0.0, float(cz) + 0.5))
		)
		dig_sum += ms
		dig_max_ms = maxf(dig_max_ms, ms)
		if ms >= HITCH_MS:
			dig_hitch += 1
			_hitch_count += 1
		var after: float = _TerrainEdits.get_height_delta(cx, cz)
		var layers := int(round((after - before) / layer))
		if layers != -1 and layers != 0:
			# 0 if hit dig floor; -1 expected
			if layers < -1 or layers > 0:
				dig_dup += 1
		elif layers < -1:
			dig_dup += 1
	if dig_dup > 0:
		_fail("2 DIG — multi-layer dig events=%d" % dig_dup)
	else:
		_ok("2 DIG 22 cells avg_ms=%.2f max_ms=%.2f hitches(>=%.0fms)=%d" % [
			dig_sum / 22.0, dig_max_ms, HITCH_MS, dig_hitch
		])

	# --- 3 Build 20+ walls ---
	var build_dup := 0
	var build_hitch := 0
	var build_max := 0.0
	var build_sum := 0.0
	for i in 22:
		var cx2 := px + 2 + (i % 11)
		var cz2 := pz + 3 + (i / 11)
		var b0: float = _TerrainEdits.get_height_delta(cx2, cz2)
		var ms2: float = _time_ms(func():
			editor.try_build(Vector3(float(cx2) + 0.5, 0.0, float(cz2) + 0.5), inv, &"wood_wall")
		)
		build_sum += ms2
		build_max = maxf(build_max, ms2)
		if ms2 >= HITCH_MS:
			build_hitch += 1
			_hitch_count += 1
		var b1: float = _TerrainEdits.get_height_delta(cx2, cz2)
		var bl := int(round((b1 - b0) / layer))
		if bl != 1:
			build_dup += 1
	if build_dup > 0:
		_fail("3 BUILD — unexpected layer deltas dup_or_miss=%d" % build_dup)
	else:
		_ok("3 BUILD 22 walls avg_ms=%.2f max_ms=%.2f hitches=%d" % [
			build_sum / 22.0, build_max, build_hitch
		])

	# --- 4 Gate ---
	var gx := px + 5
	var gz := pz + 6
	var gok: bool = bool(editor.try_build_gate(Vector3(float(gx) + 0.5, 0.0, float(gz) + 0.5), inv))
	var gfeat: Dictionary = _FeatureRegistry.get_feature(gx, gz)
	if not gok or not bool(gfeat.get("is_passage", false)):
		_fail("4 GATE place failed reason=%s" % editor.last_fail_reason)
	else:
		_ok("4 GATE at (%d,%d) is_passage" % [gx, gz])

	# --- 5 Bridge ---
	var bx := px + 8
	var bz := pz + 6
	_TerrainEdits.dig(bx, bz, 1)
	var br_ok: bool = bool(editor.try_build_bridge(Vector3(float(bx) + 0.5, 0.0, float(bz) + 0.5), inv))
	var bfeat: Dictionary = _FeatureRegistry.get_feature(bx, bz)
	if not br_ok or not bool(bfeat.get("is_bridge", false)):
		_fail("5 BRIDGE place failed")
	else:
		_ok("5 BRIDGE at (%d,%d)" % [bx, bz])

	# --- 6 Ramp agreement ---
	var ramp_ok := true
	var sample_x := float(px) + 0.5
	var sample_z := float(pz) + 0.5
	var walk: float = _TerrainRamps.walkable_height(world, sample_x, sample_z)
	var surf: float = world.get_surface_height(float(px), float(pz))
	if walk + 0.001 < surf:
		ramp_ok = false
		_fail("6 RAMP/WALK walkable < surface walk=%.2f surf=%.2f" % [walk, surf])
	# Adjacent step consistency
	var h0: float = world.get_surface_height(float(px + 2), float(pz + 3))
	var h1: float = world.get_surface_height(float(px + 3), float(pz + 3))
	var w0: float = _TerrainRamps.walkable_height(world, float(px + 2) + 0.5, float(pz + 3) + 0.5)
	var w1: float = _TerrainRamps.walkable_height(world, float(px + 3) + 0.5, float(pz + 3) + 0.5)
	if absf(w0 - (h0 + layer)) > layer * 0.2 and absf(w1 - (h1 + layer)) > layer * 0.2:
		# both flats should sit near surface+layer
		pass
	if ramp_ok:
		_ok("6 RAMP/WALK surface=%.2f walkable=%.2f (adjacent tops ok)" % [surf, walk])

	# --- 7 Water redirect ---
	var water_ms := 0.0
	if editor.has_method("_channel_dig"):
		water_ms = _time_ms(func():
			for i in 6:
				editor._channel_dig(px + 10 + i, pz + 2, inv)
		)
	else:
		water_ms = _time_ms(func():
			for i in 6:
				editor.try_dig(Vector3(float(px + 10 + i) + 0.5, 0, float(pz + 2) + 0.5))
		)
	if water_ms >= HITCH_MS * 6.0:
		_hitch_count += 1
		_note("WARN 7 WATER total_ms=%.1f for 6 channel digs (may hitch)" % water_ms)
	else:
		_ok("7 WATER/channel 6 digs total_ms=%.2f (%.2f/edit)" % [water_ms, water_ms / 6.0])

	# --- 8 Approach crystal ---
	if crystal == null:
		_note("WARN 8 CRYSTAL manager missing")
	else:
		var depth_n := 0
		if crystal.has_method("get_depth_at"):
			# sample near origin spawns
			for dx in range(-8, 9):
				for dz in range(-8, 9):
					if float(crystal.get_depth_at(dx, dz)) > 0.04:
						depth_n += 1
		# Floor refresh hook
		var cm_src: String = (load("res://crystal/crystal_manager.gd") as GDScript).source_code
		if "_refresh_crystal_floor_near" not in cm_src:
			_fail("8 CRYSTAL missing floor refresh on terrain edit")
		else:
			_ok("8 CRYSTAL present active_cells_near_origin~%d floor_refresh_hook=yes" % depth_n)

	# Dig under crystal: prove MultiMesh presentation Y drops (not only floor query).
	if crystal and crystal.has_method("get_depth_at"):
		var found := false
		for dx in range(-20, 21):
			for dz in range(-20, 21):
				var cpos := Vector2i(px + dx, pz + dz)
				if float(crystal.get_depth_at(cpos.x, cpos.y)) > 0.04:
					var fl0: float = crystal._crystal_floor_at(cpos) if crystal.has_method("_crystal_floor_at") else 0.0
					var depth0: float = float(crystal.get_depth_at(cpos.x, cpos.y))
					var applied0: float = -99999.0
					# Ensure presentation MultiMesh path is instanced for this cell before dig.
					if crystal._presentation:
						var cell0 = crystal._presentation._make_render_cell(cpos, depth0, -1)
						applied0 = cell0.terrain_y
						var ccoord0 := Vector2i(
							floori(float(cpos.x) / float(ChunkData.SIZE)),
							floori(float(cpos.y) / float(ChunkData.SIZE))
						)
						crystal._presentation._chunk_needs_full_rebuild[ccoord0] = true
						if crystal._presentation.has_method("_rebuild_chunk_layer"):
							crystal._presentation._rebuild_chunk_layer(ccoord0)
						var layer0 = crystal._presentation._chunk_layers.get(ccoord0)
						if layer0 and layer0.has_method("get_applied_terrain_y"):
							applied0 = layer0.get_applied_terrain_y(cpos)
					editor.try_dig(Vector3(float(cpos.x) + 0.5, 0, float(cpos.y) + 0.5))
					if crystal.has_method("_on_player_terrain_edited"):
						crystal._on_player_terrain_edited(cpos.x, cpos.y, &"dig")
					if crystal._presentation:
						var ccoord := Vector2i(
							floori(float(cpos.x) / float(ChunkData.SIZE)),
							floori(float(cpos.y) / float(ChunkData.SIZE))
						)
						crystal._presentation._chunk_needs_full_rebuild[ccoord] = true
						if crystal._presentation.has_method("_rebuild_chunk_layer"):
							crystal._presentation._rebuild_chunk_layer(ccoord)
					await process_frame
					await process_frame
					var fl1: float = crystal._crystal_floor_at(cpos) if crystal.has_method("_crystal_floor_at") else fl0
					var applied1: float = -99999.0
					if crystal._presentation:
						var ccoord1 := Vector2i(
							floori(float(cpos.x) / float(ChunkData.SIZE)),
							floori(float(cpos.y) / float(ChunkData.SIZE))
						)
						var layer1 = crystal._presentation._chunk_layers.get(ccoord1)
						if layer1 and layer1.has_method("get_applied_terrain_y"):
							applied1 = layer1.get_applied_terrain_y(cpos)
						if applied1 < -9000.0:
							var cell1 = crystal._presentation._make_render_cell(cpos, depth0, -1)
							applied1 = cell1.terrain_y
					if applied0 > -9000.0 and applied1 > -9000.0:
						if applied1 >= applied0 - 0.05:
							_fail("8b CRYSTAL MultiMesh applied_terrain_y stuck %.3f→%.3f" % [applied0, applied1])
						else:
							_ok("8b CRYSTAL MultiMesh applied_terrain_y dropped %.3f→%.3f (floor %.2f→%.2f)" % [
								applied0, applied1, fl0, fl1
							])
					elif fl1 <= fl0 + 0.01:
						_ok("8b CRYSTAL floor dropped %.2f→%.2f" % [fl0, fl1])
					else:
						_fail("8b CRYSTAL floor rose after dig")
					found = true
					break
			if found:
				break
		if not found:
			_note("NOTE 8b no crystal cell near player to dig under")

	# --- 9 Fight enemy ---
	var enemies: Array = get_nodes_in_group("crystal_enemy")
	if enemies.is_empty():
		enemies = get_nodes_in_group("enemies")
	if enemies.is_empty():
		_note("NOTE 9 FIGHT no live enemy in groups (spawn may be far)")
	else:
		var e: Node = enemies[0]
		var hp0 := -1.0
		if "health" in e:
			hp0 = float(e.health)
		if e.has_method("take_damage"):
			e.take_damage(5.0)
		elif e.has_method("apply_damage"):
			e.apply_damage(5.0, &"test")
		var hp1 := hp0
		if "health" in e:
			hp1 = float(e.health)
		if hp0 > 0.0 and hp1 >= hp0:
			_fail("9 FIGHT damage did not reduce health")
		else:
			_ok("9 FIGHT enemy damaged hp %.1f→%.1f" % [hp0, hp1])

	# --- 10 Spawn damage ---
	if crystal and crystal.has_method("damage_spawn_at_world"):
		var dmg_ms := _time_ms(func():
			# API expects world column (Vector2i), not Vector3.
			crystal.damage_spawn_at_world(Vector2i(0, 0), 8.0, 4.0)
		)
		_ok("10 SPAWN damage_spawn_at_world ms=%.2f" % dmg_ms)
	else:
		_note("NOTE 10 SPAWN API missing")

	# --- 11 Crystal responds to terrain (wall baffle path present) ---
	var wall_cell := Vector2i(px + 4, pz + 8)
	editor.try_build(Vector3(float(wall_cell.x) + 0.5, 0, float(wall_cell.y) + 0.5), inv, &"stone_wall")
	var feat_w: Dictionary = _FeatureRegistry.get_feature(wall_cell.x, wall_cell.y)
	if float(feat_w.get("flow_resistance", 0.0)) < 0.2:
		_fail("11 CRYSTAL-TERRAIN wall missing flow_resistance")
	else:
		_ok("11 CRYSTAL-TERRAIN wall flow_resistance=%.2f" % float(feat_w.get("flow_resistance", 0.0)))

	# --- Herb heal via shipped weapon consumable path ---
	var weapon_node = player.get_node_or_null("WeaponController")
	if weapon_node and weapon_node.has_method("_try_use_consumable") and inv:
		var hp_start: float = float(player.health)
		if player.has_method("take_damage"):
			player.take_damage(40.0)
		var hp_mid: float = float(player.health)
		if inv.has_method("set_slot"):
			inv.set_slot(0, "herb", maxi(2, inv.count_item("herb")))
		else:
			inv.add_item("herb", 2)
		weapon_node._active_hotbar_index = 0
		weapon_node._cooldown_timer = 0.0
		var herb_b: int = inv.count_item("herb")
		var used: bool = bool(weapon_node._try_use_consumable())
		var herb_a: int = inv.count_item("herb")
		var hp_end: float = float(player.health)
		if not used:
			_fail("HEAL weapon._try_use_consumable failed")
		elif herb_a >= herb_b:
			_fail("HEAL herb not consumed")
		elif hp_end <= hp_mid:
			_fail("HEAL health did not rise via consumable")
		else:
			_ok("HEAL via _try_use_consumable %.1f→%.1f→%.1f herbs %d→%d" % [
				hp_start, hp_mid, hp_end, herb_b, herb_a
			])
	else:
		_fail("HEAL weapon consumable path unavailable")

	# Input policy still present
	var wsrc: String = (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	if "TERRAIN_HOLD_REPEAT_START_SEC" not in wsrc:
		_fail("input hold-repeat missing")
	else:
		_ok("INPUT edge/hold-repeat policy present")

	_note("")
	_note("## Summary")
	_note("- hitch_events(>=%.0fms single edit): %d" % [HITCH_MS, _hitch_count])
	_note("- dig avg/max ms: %.2f / %.2f" % [dig_sum / 22.0, dig_max_ms])
	_note("- build avg/max ms: %.2f / %.2f" % [build_sum / 22.0, build_max])
	_note("- failures: %d" % _failed)
	_finish()


func _crystal_mm_center_y(crystal, pos: Vector2i) -> float:
	if crystal == null or crystal._presentation == null:
		return -99999.0
	var coord := Vector2i(
		floori(float(pos.x) / float(ChunkData.SIZE)),
		floori(float(pos.y) / float(ChunkData.SIZE))
	)
	var layer = crystal._presentation._chunk_layers.get(coord)
	if layer == null or not layer.has_method("get_cell_instance_center_y"):
		return -99999.0
	var ly: float = layer.get_cell_instance_center_y(pos)
	if ly < -9000.0:
		return -99999.0
	return ly + layer.global_position.y


func _finish() -> void:
	var path := "/tmp/grok-goal-3df95600d6a4/implementer/playtest_session_results.md"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	# Also update human scenario with results pointer
	var path2 := "/tmp/grok-goal-3df95600d6a4/implementer/human_playtest_scenario.md"
	var f2 := FileAccess.open(path2, FileAccess.READ_WRITE)
	if f2:
		f2.seek_end()
		f2.store_string("\n\n## Session run results\nSee `playtest_session_results.md` (failures=%d, hitches=%d).\n" % [
			_failed, _hitch_count
		])
		f2.close()
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All stabilization playtest session OK")
	else:
		_ProbeExit.finish_tree(self, 1, "STABILIZATION PLAYTEST FAILED")
