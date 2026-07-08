class_name SmokeProbeHelpers
extends RefCounted

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


static func session_seconds() -> float:
	var raw := OS.get_environment("SMOKE_SESSION_SEC").strip_edges()
	if raw.is_empty():
		return 30.0
	return maxf(float(raw), 5.0)