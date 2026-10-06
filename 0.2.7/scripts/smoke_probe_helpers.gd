class_name SmokeProbeHelpers
extends RefCounted

const _ActionTargeting = preload("res://player/action_targeting.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")

const FACE_TOP := 0


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


static func position_player_for_forward_dig(
	player: Node3D,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	wx: int,
	wz: int,
	range_v: float,
	mode: StringName = &"dig"
) -> void:
	if player == null:
		return
	var col_x := float(wx) + 0.5
	var col_z := float(wz) + 0.5
	var fwd := _ActionTargeting.attack_forward(player)
	if fwd.length_squared() < 0.0001:
		fwd = Vector3(1.0, 0.0, 0.0)
	var stand_dist := clampf(range_v * 0.82, 0.8, 2.4)
	var stand_x := col_x - fwd.x * stand_dist
	var stand_z := col_z - fwd.z * stand_dist
	var y: float = float(player.get("voxel_position").y)
	if world != null:
		var surf: float = world.get_surface_height(stand_x, stand_z)
		y = surf + _WorldSettings.get_active().layer_height()
	player.set("voxel_position", Vector3(stand_x, y, stand_z))
	if player.has_method("_sync_global_from_voxel"):
		player.call("_sync_global_from_voxel")
	if player.has_method("_snap_to_ground"):
		player.call("_snap_to_ground")
	var weapon: Node = player.get_node_or_null("WeaponController")
	var inv = player.get("inventory")
	if weapon == null or inv == null:
		return
	if mode == &"dig":
		if inv.has_method("set_slot"):
			inv.set_slot(1, "stone_pick", 1)
		if weapon.has_method("set_active_hotbar_index"):
			weapon.set_active_hotbar_index(1)
	elif mode == &"attack":
		if inv.has_method("set_slot"):
			inv.set_slot(0, "wooden_sword", 1)
		if weapon.has_method("set_active_hotbar_index"):
			weapon.set_active_hotbar_index(0)
	elif mode == &"build":
		if inv.has_method("count_item") and inv.count_item("stone") < 1 and inv.has_method("add_item"):
			inv.add_item("stone", 4)
		if inv.has_method("set_slot"):
			inv.set_slot(0, "stone", 4)
		if weapon.has_method("set_active_hotbar_index"):
			weapon.set_active_hotbar_index(0)


static func clear_mouse_offscreen(player: Node3D) -> void:
	if player == null:
		return
	var vp: Viewport = player.get_viewport()
	if vp == null:
		return
	vp.warp_mouse(Vector2(-10000.0, -10000.0))


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
		if not data._has_resident_column_maps():
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


## Live floor probe: a 1-layer build can be stepped; a 2-layer stack blocks.
static func check_built_wall_collision(
	floor_probe,
	wx: int,
	wz: int,
	expect_step: bool,
	expect_blocks: bool
) -> Dictionary:
	if floor_probe == null or not floor_probe.has_method("can_step_to"):
		return {"ok": false, "reason": "no floor probe", "raise": 0.0, "can_step": false}
	var ws = _WorldSettings.get_active()
	var layer: float = ws.layer_height()
	var wall_feet: float = float(floor_probe.walkable_height_at(float(wx) + 0.5, float(wz) + 0.5))
	var approach := Vector2i(wx - 1, wz)
	var approach_feet := wall_feet
	var found := false
	for dir in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var n := Vector2i(wx + dir.x, wz + dir.y)
		var feet: float = float(floor_probe.walkable_height_at(float(n.x) + 0.5, float(n.y) + 0.5))
		if feet >= wall_feet - layer * 0.15:
			continue
		if not found or feet > approach_feet:
			found = true
			approach = n
			approach_feet = feet
	if not found:
		approach_feet = float(floor_probe.walkable_height_at(float(approach.x) + 0.5, float(approach.y) + 0.5))
	var raise: float = wall_feet - approach_feet
	var from_pos := Vector3(float(approach.x) + 0.5, approach_feet, float(approach.y) + 0.5)
	var to_pos := Vector3(float(wx) + 0.5, approach_feet, float(wz) + 0.5)
	var can_step: bool = bool(floor_probe.can_step_to(
		from_pos,
		to_pos,
		ws.player_height(),
		ws.player_radius(),
		ws.max_step_up_walk(),
		false
	))
	var blocks := not can_step
	var ok := can_step == expect_step and blocks == expect_blocks
	var reason := ""
	if not ok:
		reason = "step=%s want %s block=%s want %s raise=%.2f from %s" % [
			str(can_step), str(expect_step), str(blocks), str(expect_blocks), raise, str(approach)
		]
	return {"ok": ok, "reason": reason, "raise": raise, "can_step": can_step}


## Production melee swing at an entity already standing on the aimed column.
static func try_forward_arc_melee_damage(
	player: Node,
	_world,
	_chunk_manager,
	weapon: Node,
	entity: Node,
	item_id: String,
	def: Dictionary
) -> Dictionary:
	if player == null or weapon == null or entity == null or not weapon.has_method("_do_melee_attack"):
		return {"ok": false, "reason": "missing melee nodes", "dist_cells": 0.0, "hp_before": 0.0, "hp_after": 0.0, "player_cell": Vector2i.ZERO, "pre_hits": 0}
	var voxel: Vector3 = player.get("voxel_position")
	var player_cell := Vector2i(floori(voxel.x), floori(voxel.z))
	var home: Vector2i = entity.get("home_cell") if "home_cell" in entity else Vector2i.ZERO
	var dist_cells: float = Vector2(float(player_cell.x - home.x), float(player_cell.y - home.y)).length()
	var hp_before: float = float(entity.get("health"))
	var pre_hits := 0
	if weapon.has_method("_attack_origin") and weapon.has_method("_attack_forward"):
		var origin: Vector3 = weapon.call("_attack_origin", 0.5)
		var forward: Vector3 = weapon.call("_attack_forward")
		var range_v: float = float(def.get("range", 2.0))
		var range_w: float = range_v * _WorldSettings.get_active().voxel_scale
		var seen: Array = CombatHitResolver.query_melee(weapon, origin, forward, range_w, null, 180.0)
		for node in seen:
			if node == entity:
				pre_hits += 1
	weapon.call("_do_melee_attack", item_id, def)
	var hp_after: float = float(entity.get("health"))
	var ok := hp_after < hp_before - 0.01
	var reason := ""
	if not ok:
		reason = "no damage" if pre_hits > 0 else "arc missed"
	return {
		"ok": ok,
		"reason": reason,
		"dist_cells": dist_cells,
		"hp_before": hp_before,
		"hp_after": hp_after,
		"player_cell": player_cell,
		"pre_hits": pre_hits,
	}


static func session_seconds() -> float:
	var raw := OS.get_environment("SMOKE_SESSION_SEC").strip_edges()
	if raw.is_empty():
		return 30.0
	return maxf(float(raw), 5.0)