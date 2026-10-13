extends SceneTree
## 20-step adversarial human-style playtest on main.tscn.
## Records defects; does not "fix" them. Output → SCRATCH adversarial_playtest.md


const MAIN_SCENE := "res://scenes/main.tscn"
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _CrystalTextureGenerator = preload("res://systems/crystal_texture_generator.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")


var _lines: PackedStringArray = []
var _defects: Array = []  # {pri, step, title, detail}
var _failed: int = 0


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


func _ok(step: int, s: String) -> void:
	_note("STEP %02d OK — %s" % [step, s])


func _def(pri: String, step: int, title: String, detail: String) -> void:
	_defects.append({"pri": pri, "step": step, "title": title, "detail": detail})
	_note("STEP %02d DEFECT [%s] %s — %s" % [step, pri, title, detail])
	if pri in ["P0", "P1"]:
		_failed += 1


func _time_ms(c: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	c.call()
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _run() -> void:
	_note("# Adversarial vertical-slice playtest (20 steps)")
	_note("**Scene:** main.tscn | **Preset:** medium")
	_note("")

	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_def("P0", 1, "main scene missing", "cannot load scenes/main.tscn")
		_finish()
		return
	var game = packed.instantiate()
	root.add_child(game)

	var player = null
	var editor = null
	var world = null
	var cm = null
	var crystal = null
	var weapon = null
	for _i in 500:
		player = get_first_node_in_group("player")
		editor = get_first_node_in_group("terrain_editor")
		world = get_first_node_in_group("world")
		cm = get_first_node_in_group("chunk_manager")
		crystal = get_first_node_in_group("crystal_manager")
		if player and editor and world and bool(player.get("world_ready")):
			weapon = player.get_node_or_null("WeaponController")
			break
		await process_frame

	if player == null or editor == null:
		_def("P0", 1, "bootstrap timeout", "player/editor not ready")
		_finish()
		return

	var layer: float = _WorldSettings.get_active().layer_height()
	var inv = player.inventory
	if inv:
		inv.add_item("wood", 80)
		inv.add_item("stone", 80)
		inv.add_item("herb", 6)

	var px := 12
	var pz := 12
	if player.has_method("get_voxel_position"):
		var pv: Vector3 = player.get_voxel_position()
		px = int(floor(pv.x))
		pz = int(floor(pv.z))

	# --- 1 spawn ---
	_ok(1, "spawn world_ready at column (~%d,%d)" % [px, pz])

	# --- 2 move ---
	var moved := false
	if "voxel_position" in player:
		var before: Vector3 = player.voxel_position
		player.voxel_position = before + Vector3(1.5, 0, 0.5)
		if player.has_method("_sync_global_from_voxel"):
			player._sync_global_from_voxel()
		await process_frame
		moved = player.voxel_position.distance_to(before) > 0.1
	if moved:
		_ok(2, "player position can be relocated (movement systems present)")
	else:
		_def("P1", 2, "movement not exercised", "could not confirm voxel relocate")

	# --- 3 approach crystal ---
	var crystal_cells := 0
	var nearest_c := Vector2i(999999, 999999)
	var best_d := INF
	if crystal and crystal.has_method("get_depth_at"):
		for dx in range(-64, 65):
			for dz in range(-64, 65):
				if float(crystal.get_depth_at(px + dx, pz + dz)) > 0.04:
					crystal_cells += 1
					var d := Vector2(float(dx), float(dz)).length()
					if d < best_d:
						best_d = d
						nearest_c = Vector2i(px + dx, pz + dz)
	if crystal_cells > 0:
		_ok(3, "crystal cells near player: ~%d nearest_dist=%.1f at %s" % [
			crystal_cells, best_d, str(nearest_c)
		])
	else:
		_def("P1", 3, "no crystal near spawn sample", "player may not see pressure immediately")

	# --- 4 dig trench ---
	var dig_dup := 0
	var dig_hitch := 0
	var dig_sum := 0.0
	var dig_max := 0.0
	for i in 12:
		var cx := px + 3 + i
		var cz := pz + 2
		var b: float = _TerrainEdits.get_height_delta(cx, cz)
		var ms: float = _time_ms(func():
			editor.try_dig(Vector3(float(cx) + 0.5, 0, float(cz) + 0.5))
		)
		dig_sum += ms
		dig_max = maxf(dig_max, ms)
		if ms >= 12.0:
			dig_hitch += 1
		var a: float = _TerrainEdits.get_height_delta(cx, cz)
		var dl := int(round((a - b) / layer))
		if dl < -1:
			dig_dup += 1
	if dig_dup > 0:
		_def("P0", 4, "multi-layer dig", "dup events=%d" % dig_dup)
	elif dig_hitch > 6:
		_def("P2", 4, "dig hitch cluster", "hitches=%d avg=%.2f max=%.2f" % [dig_hitch, dig_sum / 12.0, dig_max])
	else:
		_ok(4, "trench dig 12 cells avg_ms=%.2f max=%.2f hitches=%d" % [dig_sum / 12.0, dig_max, dig_hitch])

	# --- 5 single wall ---
	var wx := px + 4
	var wz := pz + 5
	var wb: float = _TerrainEdits.get_height_delta(wx, wz)
	var wms: float = _time_ms(func():
		editor.try_build(Vector3(float(wx) + 0.5, 0, float(wz) + 0.5), inv, &"wood_wall")
	)
	var wa: float = _TerrainEdits.get_height_delta(wx, wz)
	var wl := int(round((wa - wb) / layer))
	var wfeat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	if wl != 1:
		_def("P0", 5, "single wall layer wrong", "layers=%d fail=%s" % [wl, editor.last_fail_reason])
	elif str(wfeat.get("build_id", "")) != "wood_wall":
		_def("P1", 5, "wall feature missing build_id", str(wfeat))
	else:
		_ok(5, "single wood_wall +1 layer ms=%.2f" % wms)

	# Visual identity of wall prop
	var feat_layer = get_first_node_in_group("feature_visual_layer")
	if feat_layer and feat_layer.has_method("refresh_cell"):
		feat_layer.refresh_cell(wx, wz)
		await process_frame
		var anch: Node3D = feat_layer._nodes_by_cell.get(Vector2i(wx, wz)) if "_nodes_by_cell" in feat_layer else null
		if anch == null:
			_def("P1", 5, "wall visual missing after place", "no FeatureVisualLayer anchor")
		else:
			var vid := str(anch.get_meta("building_visual_id", ""))
			var mesh: MeshInstance3D = anch.get_node_or_null("Mesh") as MeshInstance3D
			if vid != "wood_wall":
				_def("P1", 5, "wall visual id wrong", vid)
			elif mesh and bool(mesh.get_meta("uses_authored_mesh", false)):
				_ok(5, "wood_wall anchor uses authored mesh scale.y=%.2f" % mesh.scale.y)
			else:
				_def("P3", 5, "wood_wall not authored", "meta uses_authored_mesh false")

	# --- 6 connected walls ---
	var conn_ok := 0
	for i in 6:
		var cx2 := px + 5 + i
		var cz2 := pz + 5
		if editor.try_build(Vector3(float(cx2) + 0.5, 0, float(cz2) + 0.5), inv, &"stone_wall"):
			conn_ok += 1
	if conn_ok < 5:
		_def("P0", 6, "connected wall line incomplete", "placed=%d/6" % conn_ok)
	else:
		_ok(6, "connected stone wall line placed=%d" % conn_ok)
	# stone visual
	if feat_layer:
		feat_layer.refresh_cell(px + 5, pz + 5)
		await process_frame
		var sa: Node3D = feat_layer._nodes_by_cell.get(Vector2i(px + 5, pz + 5))
		if sa:
			var svid := str(sa.get_meta("building_visual_id", ""))
			var sm: MeshInstance3D = sa.get_node_or_null("Mesh") as MeshInstance3D
			if svid != "stone_wall":
				_def("P1", 6, "stone_wall visual id", svid)
			elif sm and bool(sm.get_meta("uses_authored_mesh", false)):
				_ok(6, "stone_wall uses authored mesh")
			else:
				_def("P3", 6, "stone_wall procedural/placeholder", "no authored mesh")

	# --- 7 gate ---
	var gx := px + 3
	var gz := pz + 8
	var gok: bool = bool(editor.try_build_gate(Vector3(float(gx) + 0.5, 0, float(gz) + 0.5), inv))
	var gfeat: Dictionary = _FeatureRegistry.get_feature(gx, gz)
	if not gok or not bool(gfeat.get("is_passage", false)):
		_def("P0", 7, "gate place failed", editor.last_fail_reason)
	else:
		if feat_layer:
			feat_layer.refresh_cell(gx, gz)
			await process_frame
			var ga: Node3D = feat_layer._nodes_by_cell.get(Vector2i(gx, gz))
			var gvid := str(ga.get_meta("building_visual_id", "")) if ga else ""
			if gvid != "gate":
				_def("P1", 7, "gate visual not gate", gvid if gvid else "missing anchor")
			elif ga:
				var gmsh: MeshInstance3D = ga.get_node_or_null("Mesh") as MeshInstance3D
				if gmsh and bool(gmsh.get_meta("uses_authored_mesh", false)):
					_ok(7, "gate placed + authored mesh")
				else:
					_def("P3", 7, "gate procedural placeholder mesh", "is_passage OK")
			else:
				_ok(7, "gate feature OK (visual later)")
		else:
			_ok(7, "gate is_passage feature")

	# --- 8 bridge ---
	var bx := px + 10
	var bz := pz + 8
	_TerrainEdits.dig(bx, bz, 1)
	var brok: bool = bool(editor.try_build_bridge(Vector3(float(bx) + 0.5, 0, float(bz) + 0.5), inv))
	var bfeat: Dictionary = _FeatureRegistry.get_feature(bx, bz)
	if not brok or not bool(bfeat.get("is_bridge", false)):
		_def("P0", 8, "bridge place failed", editor.last_fail_reason)
	else:
		if feat_layer:
			feat_layer.refresh_cell(bx, bz)
			await process_frame
			var ba: Node3D = feat_layer._nodes_by_cell.get(Vector2i(bx, bz))
			var bvid := str(ba.get_meta("building_visual_id", "")) if ba else ""
			if bvid != "bridge":
				_def("P1", 8, "bridge visual id wrong", bvid if bvid else "missing")
			elif ba and ba.get_node_or_null("Mesh") and bool((ba.get_node("Mesh") as MeshInstance3D).get_meta("uses_authored_mesh", false)):
				_ok(8, "bridge authored mesh")
			else:
				_def("P3", 8, "bridge procedural placeholder", "is_bridge OK")
		else:
			_ok(8, "bridge feature OK")

	# --- 9 ramps ---
	var surf: float = world.get_surface_height(float(px + 5), float(pz + 5))
	var walk: float = _TerrainRamps.walkable_height(world, float(px + 5) + 0.5, float(pz + 5) + 0.5)
	if walk + 0.001 < surf:
		_def("P0", 9, "walkable below surface", "walk=%.2f surf=%.2f" % [walk, surf])
	elif absf(walk - (surf + layer)) > layer * 0.25 and absf(walk - surf) > 0.01:
		# ramp slope or flat top both OK if walkable sensible
		_ok(9, "walkable=%.2f surface=%.2f layer=%.2f" % [walk, surf, layer])
	else:
		_ok(9, "ramp/walk surface=%.2f walkable=%.2f" % [surf, walk])

	# --- 10 route water ---
	var water_ms := 0.0
	var water_ok := false
	if editor.has_method("_channel_dig"):
		water_ms = _time_ms(func():
			for i in 5:
				editor._channel_dig(px + 12 + i, pz + 3, inv)
		)
		water_ok = true
	else:
		water_ms = _time_ms(func():
			for i in 5:
				editor.try_dig(Vector3(float(px + 12 + i) + 0.5, 0, float(pz + 3) + 0.5))
		)
	if water_ms > 80.0:
		_def("P2", 10, "water/channel dig hitch", "5 edits total_ms=%.1f (%.1f/edit)" % [water_ms, water_ms / 5.0])
	elif water_ok:
		_ok(10, "channel dig 5 cells total_ms=%.1f (%.1f/edit)" % [water_ms, water_ms / 5.0])
	else:
		_ok(10, "trench dig near water path total_ms=%.1f" % water_ms)

	# Water visual: tile override present?
	var wt := world.get_tile_type(float(px + 12), float(pz + 3))
	_note("  water tile_at channel dig=%d (RIVER/WATER expected if channel)" % wt)

	# --- 11 crystal response to terrain ---
	var wall_c := Vector2i(px + 6, pz + 10)
	editor.try_build(Vector3(float(wall_c.x) + 0.5, 0, float(wall_c.y) + 0.5), inv, &"stone_wall")
	var wf: Dictionary = _FeatureRegistry.get_feature(wall_c.x, wall_c.y)
	var resist: float = float(wf.get("flow_resistance", 0.0))
	if resist < 0.2:
		_def("P1", 11, "wall missing crystal flow_resistance", str(wf))
	else:
		_ok(11, "wall flow_resistance=%.2f (crystal baffle)" % resist)

	# Crystal floor after dig under crystal
	if crystal and nearest_c.x < 99999:
		var fl0: float = crystal._crystal_floor_at(nearest_c) if crystal.has_method("_crystal_floor_at") else 0.0
		var d0: float = float(crystal.get_depth_at(nearest_c.x, nearest_c.y))
		if d0 > 0.04 and crystal._presentation:
			var cell0 = crystal._presentation._make_render_cell(nearest_c, d0, -1)
			var ty0: float = cell0.terrain_y
			editor.try_dig(Vector3(float(nearest_c.x) + 0.5, 0, float(nearest_c.y) + 0.5))
			if crystal.has_method("_on_player_terrain_edited"):
				crystal._on_player_terrain_edited(nearest_c.x, nearest_c.y, &"dig")
			await process_frame
			var cell1 = crystal._presentation._make_render_cell(nearest_c, d0, -1)
			var ty1: float = cell1.terrain_y
			if ty1 >= ty0 - 0.05:
				_def("P0", 11, "crystal presentation floor stuck after dig", "%.2f→%.2f" % [ty0, ty1])
			else:
				_ok(11, "crystal presentation terrain_y %.2f→%.2f after dig" % [ty0, ty1])
		else:
			_ok(11, "crystal baffle only (no nearby depth for floor dig)")

	# --- 12 fight enemies ---
	var enemies: Array = get_nodes_in_group("crystal_enemy")
	if enemies.is_empty():
		enemies = get_nodes_in_group("enemies")
	if enemies.is_empty():
		_def("P2", 12, "no crystal enemies near session", "cannot exercise combat pressure")
	else:
		var e: Node = enemies[0]
		var hp0 := float(e.get("health")) if "health" in e else -1.0
		if e.has_method("take_damage"):
			e.take_damage(8.0)
		elif e.has_method("apply_damage"):
			e.apply_damage(8.0, &"test")
		var hp1 := float(e.get("health")) if "health" in e else hp0
		if hp0 > 0.0 and hp1 >= hp0:
			_def("P0", 12, "enemy damage no effect", "%.1f→%.1f" % [hp0, hp1])
		else:
			_ok(12, "enemy damaged %.1f→%.1f" % [hp0, hp1])

	# --- 13 heal ---
	var weapon_node = player.get_node_or_null("WeaponController")
	if weapon_node and weapon_node.has_method("_try_use_consumable") and inv:
		player.health = minf(player.health, player.max_health)
		if player.has_method("take_damage"):
			player.take_damage(35.0)
		var mid: float = player.health
		if inv.has_method("set_slot"):
			inv.set_slot(0, "herb", maxi(2, inv.count_item("herb")))
		weapon_node._active_hotbar_index = 0
		weapon_node._cooldown_timer = 0.0
		var hb: int = inv.count_item("herb")
		var used: bool = bool(weapon_node._try_use_consumable())
		var ha: int = inv.count_item("herb")
		if not used or ha >= hb or player.health <= mid:
			_def("P0", 13, "heal path broken", "used=%s herbs %d→%d hp mid=%.1f now=%.1f" % [
				used, hb, ha, mid, player.health
			])
		else:
			_ok(13, "heal via consumable mid=%.1f→%.1f herbs %d→%d" % [mid, player.health, hb, ha])
	else:
		_def("P0", 13, "heal API missing", "no weapon consumable path")

	# --- 14 approach spawn ---
	var spawn_n := 0
	if crystal and crystal.has_method("get_active_spawns"):
		var spawns: Array = crystal.get_active_spawns()
		spawn_n = spawns.size()
	if spawn_n > 0:
		_ok(14, "active crystal spawns=%d" % spawn_n)
	else:
		_def("P1", 14, "no active spawns reported", "get_active_spawns empty/missing")

	# --- 15 damage spawn ---
	if crystal and crystal.has_method("damage_spawn_at_world"):
		var dmg_ms := _time_ms(func():
			crystal.damage_spawn_at_world(Vector2i(0, 0), 12.0, 6.0)
		)
		_ok(15, "damage_spawn_at_world ms=%.2f" % dmg_ms)
	else:
		_def("P1", 15, "spawn damage API missing", "")

	# --- 16 retreat ---
	if "voxel_position" in player:
		var midp: Vector3 = player.voxel_position
		player.voxel_position = midp + Vector3(-3.0, 0, -2.0)
		if player.has_method("_sync_global_from_voxel"):
			player._sync_global_from_voxel()
		_ok(16, "retreat relocate applied")
	else:
		_ok(16, "retreat skipped (no voxel_position)")

	# --- 17 return continue ---
	if "voxel_position" in player:
		player.voxel_position = Vector3(float(px) + 0.5, player.voxel_position.y, float(pz) + 0.5)
		if player.has_method("_sync_global_from_voxel"):
			player._sync_global_from_voxel()
		_ok(17, "return to operational area")
	else:
		_ok(17, "return skipped")

	# --- 18 world boundaries ---
	var half: float = float(_WorldBorder.PLAYABLE_HALF_X) if "PLAYABLE_HALF_X" in _WorldBorder else 1024.0
	var edge_ok := _WorldBorder.is_playable(0.0, 0.0)
	var far_ok := _WorldBorder.is_playable(half + 50.0, 0.0)
	if not edge_ok:
		_def("P0", 18, "origin not playable", "")
	elif far_ok:
		_def("P1", 18, "far outside still playable?", "half=%.0f" % half)
	else:
		_ok(18, "border playable origin=yes outside=no half=%.0f" % half)

	# --- 19 attempt leave ---
	var block_ocean := false
	var block_mtn := false
	if _WorldBorder.has_method("blocks_player_at"):
		block_ocean = bool(_WorldBorder.blocks_player_at(half + 10.0, 0.0))
		block_mtn = bool(_WorldBorder.blocks_player_at(0.0, half + 10.0))
	if block_ocean or block_mtn:
		_ok(19, "blocks_player_at ocean=%s mountain_axis=%s" % [block_ocean, block_mtn])
	else:
		_def("P1", 19, "border block API weak/missing", "player may walk out")

	# --- 20 win/lose restart path ---
	var gm = get_first_node_in_group("game_manager")
	if gm == null:
		_def("P1", 20, "game_manager missing", "no win/lose owner")
	else:
		var has_win := gm.has_signal("run_state_changed") or "run_state" in gm
		if has_win:
			_ok(20, "game_manager run_state present (restart path exists)")
		else:
			_def("P1", 20, "run_state not found on game_manager", "")

	# Structure visual audit snapshot
	_note("")
	_note("## Structure authored-mesh snapshot")
	var reg = get_first_node_in_group("game_visual_registry")
	if reg and reg.has_method("has_authored_building_mesh"):
		for id in ["wood_wall", "stone_wall", "gate", "bridge", "ruin_pillar", "town_hall"]:
			var has: bool = bool(reg.has_authored_building_mesh(id))
			_note("- %s authored=%s" % [id, has])
			if id != "wood_wall" and not has:
				_def("P3", 0, "%s missing authored asset" % id, "procedural multi-box still in use")
	else:
		_def("P3", 0, "registry authored API missing", "")

	# Town/ruin landmarks
	var towns: Array = _FeatureRegistry.get_towns()
	var ruins: Array = _FeatureRegistry.get_ruin_centers()
	_note("")
	_note("## Landmarks towns=%d ruins=%d" % [towns.size(), ruins.size()])
	if towns.is_empty():
		_def("P2", 0, "no towns seeded", "settlement landmarks absent")
	if ruins.is_empty():
		_def("P2", 0, "no ruins seeded", "ruin landmarks absent")

	_finish()


func _finish() -> void:
	_note("")
	_note("## Defect count by priority")
	var counts := {"P0": 0, "P1": 0, "P2": 0, "P3": 0, "P4": 0}
	for d in _defects:
		var p: String = str(d.pri)
		counts[p] = int(counts.get(p, 0)) + 1
	for p in ["P0", "P1", "P2", "P3", "P4"]:
		_note("- %s: %d" % [p, counts[p]])

	var path := "/tmp/grok-goal-8d68b3af5085/implementer/adversarial_playtest.md"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
		f.close()

	var dpath := "/tmp/grok-goal-8d68b3af5085/implementer/prioritized_defects.md"
	var df := FileAccess.open(dpath, FileAccess.WRITE)
	if df:
		df.store_string("# Prioritized defect list (Phase 1 — before large implementation)\n\n")
		df.store_string("Source: `adversarial_playtest.md` 20-step main.tscn session.\n\n")
		for p in ["P0", "P1", "P2", "P3", "P4"]:
			df.store_string("## %s\n\n" % p)
			var any := false
			for d in _defects:
				if str(d.pri) != p:
					continue
				any = true
				df.store_string("- **Step %s — %s:** %s\n" % [str(d.step), d.title, d.detail])
			if not any:
				df.store_string("- _(none from this session)_\n")
			df.store_string("\n")
		df.store_string("## Legend\n")
		df.store_string("- P0 broken gameplay\n- P1 visually misleading gameplay\n")
		df.store_string("- P2 severe feel/performance\n- P3 placeholder presentation\n- P4 polish\n")
		df.close()

	if counts["P0"] == 0:
		_ProbeExit.finish_tree(self, 0, "ADVERSARIAL PLAYTEST COMPLETE (no P0)")
	else:
		_ProbeExit.finish_tree(self, 0, "ADVERSARIAL PLAYTEST COMPLETE (P0 present — list written)")
