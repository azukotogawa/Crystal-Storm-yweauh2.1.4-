class_name SmokeProbeHelpers
extends RefCounted

const FACE_TOP := 0
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _CombatHitResolver = preload("res://systems/combat_hit_resolver.gd")
const _CombatDef = preload("res://config/combat_def.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkView = preload("res://chunks/chunk_view.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")


static func sprite_textured(spr: Sprite3D, require_billboard: bool = true) -> bool:
	if spr == null or not spr.visible or spr.modulate.a < 0.08:
		return false
	if require_billboard and spr.billboard == BaseMaterial3D.BILLBOARD_DISABLED:
		return false
	var tex: Texture2D = spr.texture
	var mat := spr.material_override
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		if sm.albedo_texture != null:
			tex = sm.albedo_texture
		elif tex == null:
			var lum := sm.albedo_color.get_luminance()
			if lum < 0.06 or lum > 0.94:
				return false
	return tex != null


static func entity_visual_visible(entity: Node) -> bool:
	if not is_instance_valid(entity):
		return false
	var prop: Node3D = entity.get_node_or_null("VoxelProp") as Node3D
	if prop and prop.visible:
		for child in prop.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).visible:
				return true
	var spr: Sprite3D = entity.get_node_or_null("Sprite3D") as Sprite3D
	if spr and sprite_textured(spr, true):
		return true
	return false


static func count_entity_sprites(tree: SceneTree) -> Dictionary:
	var textured := 0
	var total := 0
	for entity in tree.get_nodes_in_group("world_entity"):
		if not is_instance_valid(entity):
			continue
		total += 1
		if entity_visual_visible(entity):
			textured += 1
	return {"textured": textured, "total": total, "visible": textured}


static func count_vegetation(visuals: Node) -> Dictionary:
	var textured := 0
	var total := 0
	var veg_root: Node3D = visuals.get_vegetation_root() if visuals and visuals.has_method("get_vegetation_root") else null
	if veg_root:
		for child in veg_root.get_children():
			total += 1
			var prop: Node3D = child.get_node_or_null("VoxelProp") as Node3D
			if prop and prop.get_child_count() > 0:
				textured += 1
				continue
			var spr: Sprite3D = child.get_node_or_null("Billboard") as Sprite3D
			if spr and sprite_textured(spr, true):
				textured += 1
	return {"textured": textured, "total": total}


static func dig_mesh_surface_y(chunk_manager: ChunkManager, dig_wx: int, dig_wz: int) -> float:
	if chunk_manager == null:
		return -1.0
	var chunk_data: ChunkData = chunk_manager.get_chunk_data_at_world_pos(
		Vector3(float(dig_wx) + 0.5, 0.0, float(dig_wz) + 0.5)
	)
	if chunk_data == null:
		return -1.0
	var coord := chunk_manager.world_to_chunk_coord(dig_wx, dig_wz)
	var lx := dig_wx - coord.x * ChunkData.SIZE
	var lz := dig_wz - coord.y * ChunkData.SIZE
	return chunk_data.get_surface_y(lx, lz)


static func chunk_view_mesh_instances(view: ChunkView) -> int:
	if view == null or not is_instance_valid(view):
		return 0
	var count := 0
	var lc: Node3D = view.get_node_or_null("LayerContainer") as Node3D
	if lc == null:
		return 0
	for child in lc.get_children():
		if child is MultiMeshInstance3D:
			var mm := (child as MultiMeshInstance3D).multimesh
			if mm != null and mm.instance_count > 0:
				count += mm.instance_count
	return count


static func audit_loaded_chunks(chunk_manager: ChunkManager) -> Dictionary:
	var invalid_views := 0
	var empty_mesh := 0
	var missing_surface := 0
	var total := chunk_manager.chunks.size() if chunk_manager else 0
	if chunk_manager == null:
		return {
			"total": 0,
			"invalid_views": 1,
			"empty_mesh": 0,
			"missing_surface": 0,
			"ok": false,
		}
	for coord in chunk_manager.chunks.keys():
		var view = chunk_manager.chunks[coord] as ChunkView
		if view == null or not is_instance_valid(view):
			invalid_views += 1
			continue
		var data: ChunkData = view.chunk_data
		if data == null:
			invalid_views += 1
			continue
		var instances := chunk_view_mesh_instances(view)
		var mesh_count := int(view.mesh_data.get("count", 0)) if view.mesh_data else 0
		if instances <= 0 and mesh_count <= 0:
			empty_mesh += 1
			continue
		if data.surface_map.is_empty() or data.surface_map.size() < ChunkData.SIZE:
			missing_surface += 1
	var ok := invalid_views == 0 and empty_mesh == 0 and missing_surface == 0 and total > 0
	return {
		"total": total,
		"invalid_views": invalid_views,
		"empty_mesh": empty_mesh,
		"missing_surface": missing_surface,
		"ok": ok,
	}


static func combat_vfx_active(combat_vfx: Node) -> Dictionary:
	var damage_labels := 0
	var burst_sprites := 0
	if combat_vfx == null:
		return {"damage_labels": 0, "burst_sprites": 0, "ok": false}
	var labels_root: Node3D = combat_vfx.get_node_or_null("DamageLabels") as Node3D
	if labels_root:
		for child in labels_root.get_children():
			if child is Label3D and (child as Label3D).visible and not (child as Label3D).text.is_empty():
				damage_labels += 1
	var burst_root: Node3D = combat_vfx.get_node_or_null("Bursts") as Node3D
	if burst_root:
		for anchor in burst_root.get_children():
			var spr: Sprite3D = anchor.get_node_or_null("Sprite3D") as Sprite3D
			if spr and spr.visible and sprite_textured(spr, false):
				burst_sprites += 1
	var ok := damage_labels >= 1 or burst_sprites >= 1
	return {"damage_labels": damage_labels, "burst_sprites": burst_sprites, "ok": ok}


static func position_player_for_forward_dig(
	player: Node,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	dig_wx: int,
	dig_wz: int,
	range_v: float,
	action_mode: StringName = &"dig"
) -> void:
	if player == null:
		return
	var stand_offsets: Array[Vector2i] = [
		Vector2i(dig_wx, dig_wz + 2),
		Vector2i(dig_wx + 2, dig_wz),
		Vector2i(dig_wx - 2, dig_wz),
		Vector2i(dig_wx, dig_wz - 2),
		Vector2i(dig_wx + 1, dig_wz + 2),
	]
	for stand in stand_offsets:
		player.set(
			"voxel_position",
			Vector3(float(stand.x) + 0.5, player.get("voxel_position").y, float(stand.y) + 0.5)
		)
		if player.has_method("_sync_global_from_voxel"):
			player.call("_sync_global_from_voxel")
		if player.has_method("_snap_to_ground"):
			player.call("_snap_to_ground")
		var info: Dictionary = _ActionTargeting.resolve_action(
			player, world, chunk_manager, range_v, false, action_mode
		)
		if info.get("valid", false) and info.get("mode", &"") == action_mode:
			var cell: Vector2i = info.get("cell", Vector2i.ZERO)
			if cell.x == dig_wx and cell.y == dig_wz:
				_ActionTargeting.warp_mouse_to_column(
					player, world, float(dig_wx) + 0.5, float(dig_wz) + 0.5
				)
				return
	player.set(
		"voxel_position",
		Vector3(float(dig_wx) + 0.5, player.get("voxel_position").y, float(dig_wz + 2) + 0.5)
	)
	if player.has_method("_sync_global_from_voxel"):
		player.call("_sync_global_from_voxel")
	if player.has_method("_snap_to_ground"):
		player.call("_snap_to_ground")
	_ActionTargeting.warp_mouse_to_column(
		player, world, float(dig_wx) + 0.5, float(dig_wz) + 0.5
	)


static func clear_mouse_offscreen(player: Node) -> void:
	if player == null or not player.is_inside_tree():
		return
	var vp: Viewport = player.get_viewport()
	if vp:
		vp.warp_mouse(Vector2(-1.0e6, -1.0e6))


static func forward_arc_stand_distance(entity: Node, range_v: float) -> float:
	var ws = _WorldSettings.get_active()
	var hit_r: float = entity.get_combat_radius() if entity.has_method("get_combat_radius") else 0.35
	var ideal := (range_v - hit_r) * 0.82
	return clampf(ideal, ws.voxel_scale * 0.35, ws.voxel_scale * 1.05)


static func _apply_forward_arc_stand(player: Node, stand_world: Vector3) -> void:
	var ws = _WorldSettings.get_active()
	stand_world.y = player.global_position.y
	player.global_position = stand_world
	player.set(
		"voxel_position",
		Vector3(
			ws.world_to_column(stand_world.x) + 0.5,
			player.get("voxel_position").y,
			ws.world_to_column(stand_world.z) + 0.5
		)
	)
	if player.has_method("_snap_to_ground"):
		player.call("_snap_to_ground")


static func forward_arc_attack_forward(player: Node, entity: Node, range_v: float) -> Vector3:
	var e_center: Vector3 = entity.get_combat_center()
	var origin := _ActionTargeting.attack_origin_world(player, 0.5)
	var to_entity := Vector3(e_center.x - origin.x, 0.0, e_center.z - origin.z)
	if to_entity.length_squared() < 0.0001:
		return _ActionTargeting.attack_toward_column(player, range_v, &"attack")
	var hit_r: float = entity.get_combat_radius() if entity.has_method("get_combat_radius") else 0.35
	var max_dist: float = maxf(range_v - hit_r - 0.05, 0.25)
	var dist_xz := to_entity.length()
	if dist_xz > max_dist:
		var step_in := dist_xz - max_dist
		_apply_forward_arc_stand(player, player.global_position + to_entity.normalized() * step_in)
		origin = _ActionTargeting.attack_origin_world(player, 0.5)
		to_entity = Vector3(e_center.x - origin.x, 0.0, e_center.z - origin.z)
	return to_entity.normalized() if to_entity.length_squared() > 0.0001 \
		else _ActionTargeting.attack_toward_column(player, range_v, &"attack")


static func position_player_for_forward_arc_attack(
	player: Node,
	entity: Node,
	range_v: float = 2.0
) -> Dictionary:
	if player == null or entity == null or not is_instance_valid(entity):
		return {"ok": false, "reason": "missing_nodes"}
	var aim_fwd := _ActionTargeting.attack_forward(player)
	var e_center: Vector3 = entity.get_combat_center()
	var stand_dist := forward_arc_stand_distance(entity, range_v)
	var stand_world: Vector3 = e_center - Vector3(aim_fwd.x, 0.0, aim_fwd.z) * stand_dist
	_apply_forward_arc_stand(player, stand_world)
	clear_mouse_offscreen(player)
	var attack_fwd := forward_arc_attack_forward(player, entity, range_v)
	clear_mouse_offscreen(player)
	var stand_pos: Vector3 = player.get("voxel_position")
	var player_cell := Vector2i(floori(stand_pos.x), floori(stand_pos.z))
	var home: Vector2i = entity.get("home_cell")
	var dist_cells: float = Vector2(
		float(home.x) - float(player_cell.x),
		float(home.y) - float(player_cell.y)
	).length()
	return {
		"ok": dist_cells >= 0.9,
		"dist_cells": dist_cells,
		"player_cell": player_cell,
		"home_cell": home,
		"entity_center": e_center,
		"stand_dist": stand_dist,
		"attack_forward": attack_fwd,
	}


static func try_forward_arc_melee_damage(
	player: Node,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	weapon: Node,
	entity: Node,
	item_id: String,
	item_def: Dictionary
) -> Dictionary:
	if player == null or weapon == null or entity == null or not is_instance_valid(entity):
		return {"ok": false, "reason": "missing_nodes"}
	if not weapon.has_method("_do_melee_attack"):
		return {"ok": false, "reason": "no_melee_api"}
	var range_v: float = float(item_def.get("range", 2.0))
	var setup := position_player_for_forward_arc_attack(player, entity, range_v)
	if not setup.get("ok", false):
		return {"ok": false, "reason": "co_located", "dist_cells": setup.get("dist_cells", 0.0)}
	var forward: Vector3 = setup.get("attack_forward", Vector3.FORWARD)
	var origin := _ActionTargeting.attack_origin_world(player, 0.5)
	var pre_hits: Array = _CombatHitResolver.query_melee(
		weapon, origin, forward, range_v, _CombatDef.create_default(),
		float(weapon.get("melee_arc_degrees"))
	)
	if pre_hits.is_empty():
		return {
			"ok": false,
			"reason": "no_pre_hits",
			"origin": origin,
			"forward": forward,
			"entity_center": setup.get("entity_center"),
		}
	var hp_before: float = float(entity.get("health"))
	weapon.set("_cooldown_timer", 0.0)
	weapon.call("_do_melee_attack", item_id, item_def)
	var hp_after: float = float(entity.get("health"))
	return {
		"ok": hp_after < hp_before - 0.01,
		"hp_before": hp_before,
		"hp_after": hp_after,
		"dist_cells": setup.get("dist_cells", 0.0),
		"pre_hits": pre_hits.size(),
		"player_cell": setup.get("player_cell"),
		"home_cell": setup.get("home_cell"),
	}


static func session_seconds() -> float:
	var raw := OS.get_environment("SMOKE_SESSION_SEC").strip_edges()
	if raw.is_empty():
		return 60.0
	return maxf(float(raw), 5.0)


static func check_built_wall_collision(
	floor_probe,
	build_wx: int,
	build_wz: int,
	expect_one_layer_step: bool,
	expect_stacked_block: bool
) -> Dictionary:
	if floor_probe == null:
		return {"ok": false, "reason": "no_floor_probe"}
	var ws = _WorldSettings.get_active()
	var layer: float = ws.layer_height()
	var ph: float = ws.player_height()
	var pr: float = ws.player_radius()
	var max_step: float = ws.max_step_up_walk()
	var neighbor := Vector2i(build_wx - 1, build_wz)
	if neighbor.x < -512:
		neighbor = Vector2i(build_wx, build_wz - 1)
	var n_feet: float = floor_probe.walkable_height_at(float(neighbor.x) + 0.5, float(neighbor.y) + 0.5)
	floor_probe.feet_height_hint = n_feet
	var w_feet: float = floor_probe.walkable_height_at(float(build_wx) + 0.5, float(build_wz) + 0.5)
	var beside := Vector3(float(neighbor.x) + 0.5, n_feet, float(neighbor.y) + 0.5)
	var into := Vector3(float(build_wx) + 0.5, n_feet, float(build_wz) + 0.5)
	var raise: float = w_feet - n_feet
	var can_step: bool = floor_probe.can_step_to(beside, into, ph, pr, max_step)
	var ok := true
	var reason := ""
	if expect_one_layer_step:
		var built_delta: float = _TerrainEdits.get_height_delta(build_wx, build_wz)
		var min_raise: float = maxf(layer * 0.5, built_delta * 0.75)
		if raise < min_raise or not can_step:
			ok = false
			reason = "1-layer raise=%.2f min=%.2f step=%s" % [raise, min_raise, can_step]
	if expect_stacked_block and can_step:
		ok = false
		reason = "stacked wall should block natural-feet entry"
	return {
		"ok": ok,
		"reason": reason,
		"raise": raise,
		"can_step": can_step,
		"wall_feet": w_feet,
		"neighbor_feet": n_feet,
	}


static func audit_ramp_step_corner_walk(floor_probe) -> Dictionary:
	if floor_probe == null:
		return {"ok": false, "reason": "no_floor_probe"}
	var saved_world = floor_probe.world
	var saved_cm = floor_probe.chunk_manager
	var saved_crystal = floor_probe.crystal_manager
	var ws = _WorldSettings.get_active()
	var layer: float = ws.layer_height()
	var ph: float = ws.player_height()
	var pr: float = ws.player_radius()
	var max_step: float = ws.max_step_up_walk()

	var old_chance: int = _TerrainRamps.placement_chance
	_TerrainRamps.placement_chance = 100
	_TerrainRamps.invalidate_mesh_cache()

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	var data := _ChunkData.new(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	for x in _ChunkData.SIZE:
		if data.surface_map.size() <= x:
			data.surface_map.append([])
			data.tile_map.append([])
		data.surface_map[x].resize(_ChunkData.SIZE)
		data.tile_map[x].resize(_ChunkData.SIZE)
		for z in _ChunkData.SIZE:
			data.surface_map[x][z] = 8.0
			data.tile_map[x][z] = _VoxelTypes.GRASSLAND

	var cx := 6
	var cz := 6
	var low_h := 10.0
	var high_h := low_h + layer
	data.surface_map[cx][cz] = low_h
	data.tile_map[cx][cz] = _VoxelTypes.GRASSLAND
	data.surface_map[cx + 1][cz] = high_h
	data.tile_map[cx + 1][cz] = _VoxelTypes.GRASSLAND
	data.surface_map[cx][cz + 1] = high_h
	data.tile_map[cx][cz + 1] = _VoxelTypes.GRASSLAND

	var cm := _ChunkManager.new()
	cm.world = world
	cm.ramp_placement_chance = 100
	cm._build_mesh(data)
	var view := _ChunkView.new()
	view.chunk_data = data
	cm.chunks[Vector2i(0, 0)] = view

	floor_probe.configure(world, cm, null)

	var ok := true
	var reason := ""
	if not data.has_ramp(cx + 1, cz) or not data.has_ramp(cx, cz + 1):
		ok = false
		reason = "missing L-step landing ramps"

	var low_start := Vector3(float(cx) + 0.5, low_h + layer, float(cz) + 0.5)
	var x_mid := Vector3(float(cx + 1) + 0.25, 0.0, float(cz) + 0.5)
	x_mid.y = floor_probe.walkable_height_at(x_mid.x, x_mid.z)
	var x_top := Vector3(float(cx + 1) + 0.75, 0.0, float(cz) + 0.5)
	x_top.y = floor_probe.walkable_height_at(x_top.x, x_top.z)
	var z_mid := Vector3(float(cx) + 0.5, 0.0, float(cz + 1) + 0.25)
	z_mid.y = floor_probe.walkable_height_at(z_mid.x, z_mid.z)
	var z_top := Vector3(float(cx) + 0.5, 0.0, float(cz + 1) + 0.75)
	z_top.y = floor_probe.walkable_height_at(z_top.x, z_top.z)

	if ok and not floor_probe.can_step_to(low_start, x_mid, ph, pr, max_step):
		ok = false
		reason = "low -> +X ramp mid blocked"
	elif ok and not floor_probe.can_step_to(x_mid, x_top, ph, pr, max_step):
		ok = false
		reason = "+X ramp mid -> interior blocked"
	elif ok and not floor_probe.can_step_to(low_start, z_mid, ph, pr, max_step):
		ok = false
		reason = "low -> +Z ramp mid blocked"
	elif ok and not floor_probe.can_step_to(z_mid, z_top, ph, pr, max_step):
		ok = false
		reason = "+Z ramp mid -> interior blocked"

	var corner_xz := Vector2(float(cx) + 0.5, float(cz) + 0.5)
	var center_h: float = floor_probe.walkable_height_at(corner_xz.x, corner_xz.y)
	var corner_feet: float = floor_probe.sample_walkable_feet(corner_xz.x, corner_xz.y)
	if ok and corner_feet < center_h - layer * 0.25:
		ok = false
		reason = "step-corner feet %.2f below center %.2f" % [corner_feet, center_h]

	floor_probe.configure(saved_world, saved_cm, saved_crystal)
	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	return {
		"ok": ok,
		"reason": reason,
		"corner_feet": corner_feet,
		"center_h": center_h,
		"steps": 4 if ok else 0,
	}


static func audit_crystal_frontier_holes(crystal_manager, center: Vector2i, radius: int = 10) -> Dictionary:
	if crystal_manager == null or not crystal_manager.has_method("get_depth_at"):
		return {"ok": false, "reason": "no_crystal_manager"}
	var min_depth: float = _CrystalSimConfig.create_default().min_depth
	var filled := 0
	var holes := 0
	for x in range(center.x - radius, center.x + radius + 1):
		for z in range(center.y - radius, center.y + radius + 1):
			var pos := Vector2i(x, z)
			var d: float = crystal_manager.get_depth_at(pos.x, pos.y)
			if d >= min_depth:
				filled += 1
				continue
			var filled_neighbors := 0
			for dir in _CrystalTypes.NEIGHBOR_DIRS:
				var n: Vector2i = pos + dir
				if crystal_manager.get_depth_at(n.x, n.y) >= min_depth:
					filled_neighbors += 1
			if filled_neighbors >= 3:
				holes += 1
	var ok := true
	var reason := ""
	var hole_cap: int = maxi(6, filled / 8)
	if filled < 6:
		ok = false
		reason = "spread too small filled=%d" % filled
	elif holes > hole_cap:
		ok = false
		reason = "checkerboard holes=%d filled=%d cap=%d" % [holes, filled, hole_cap]
	return {"ok": ok, "reason": reason, "holes": holes, "filled": filled, "hole_cap": hole_cap}