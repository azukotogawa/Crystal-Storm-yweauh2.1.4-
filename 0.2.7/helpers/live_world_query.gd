class_name LiveWorldQuery
extends RefCounted
## Read-only snapshot of one world column for the Live World Inspector.

const _ChunkData = preload("res://chunks/chunk_data.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")


static func inspect_targeted(tree: SceneTree) -> Dictionary:
	if tree == null:
		return {"ok": false, "error": "no_tree"}
	var player = tree.get_first_node_in_group("player")
	var world = tree.get_first_node_in_group("world")
	var cm = tree.get_first_node_in_group("chunk_manager")
	if player == null:
		return {"ok": false, "error": "no_player"}
	var world0 = tree.get_first_node_in_group("world")
	var cm0 = tree.get_first_node_in_group("chunk_manager")
	var info: Dictionary = _ActionTargeting.resolve_action(player, world0, cm0, 8.0)
	var cell: Vector2i = info.get("cell", Vector2i.ZERO) if not info.is_empty() else Vector2i.ZERO
	if info.is_empty() or cell == Vector2i.ZERO:
		if player.has_method("get_voxel_position"):
			var p: Vector3 = player.get_voxel_position()
			cell = Vector2i(floori(p.x), floori(p.z))
	return inspect_cell(tree, cell.x, cell.y, world, cm, player)


static func inspect_cell(tree: SceneTree, wx: int, wz: int, world = null, cm = null, player = null) -> Dictionary:
	if world == null and tree:
		world = tree.get_first_node_in_group("world")
	if cm == null and tree:
		cm = tree.get_first_node_in_group("chunk_manager")
	if player == null and tree:
		player = tree.get_first_node_in_group("player")
	var ws = _WorldSettings.get_active()
	var layer: float = ws.layer_height() if ws else 1.0
	var cx := int(floor(float(wx) / float(_ChunkData.SIZE)))
	var cz := int(floor(float(wz) / float(_ChunkData.SIZE)))
	var chunk := Vector2i(cx, cz)
	var surf := 0.0
	var tile := -1
	if world:
		surf = float(world.get_surface_height(float(wx), float(wz)))
		tile = int(world.get_tile_type(float(wx), float(wz)))
	var walk := surf + layer
	if world and cm:
		walk = float(_ActionTargeting._walkable_top(world, cm, float(wx) + 0.5, float(wz) + 0.5))
	var hdelta: float = _TerrainEdits.get_height_delta(wx, wz)
	var build_tile: int = _TerrainEdits.get_build_tile(wx, wz)
	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	var override_tile: int = _FeatureRegistry.get_tile_override(wx, wz)
	var channel: Dictionary = _ChannelRegistry.get_channel(wx, wz) if _ChannelRegistry.is_channel(wx, wz) else {}
	var crystal = tree.get_first_node_in_group("crystal_manager") if tree else null
	var crystal_depth := 0.0
	var has_crystal := false
	if crystal:
		if crystal.has_method("has_crystal_at"):
			has_crystal = bool(crystal.has_crystal_at(wx, wz))
		if crystal.has_method("get_depth_at"):
			crystal_depth = float(crystal.get_depth_at(wx, wz))
	var bake = _WorldBakeService.get_active()
	var package_ready := false
	var bake_valid := false
	if bake:
		bake_valid = bool(bake.valid)
		if bake.has_method("package_ready"):
			package_ready = bool(bake.package_ready(chunk))
	var streamed := false
	var view_path := ""
	var mesh_aabb := AABB()
	if cm and "chunks" in cm and cm.chunks.has(chunk):
		streamed = true
		var view = cm.chunks[chunk]
		if view is Node:
			view_path = str(view.get_path()) if view.is_inside_tree() else view.name
			if view is Node3D:
				mesh_aabb = _node_aabb(view)
	var chunk_lifecycle := "missing"
	if cm and cm.has_method("get_chunk_lifecycle"):
		chunk_lifecycle = str(cm.get_chunk_lifecycle(chunk))
	elif streamed:
		chunk_lifecycle = "resident"
	var origin := "generated"
	if package_ready and bake_valid:
		origin = "baked"
	elif package_ready:
		origin = "package"
	if streamed:
		origin = origin + "+streamed"
	if hdelta != 0.0 or build_tile >= 0 or not feat.is_empty():
		origin = origin + "+live"
	var column_source := origin
	var build_id := str(feat.get("build_id", ""))
	var plant_id := str(feat.get("plant_id", ""))
	var kind := int(feat.get("kind", 0))
	var visual_id := build_id if not build_id.is_empty() else (plant_id if not plant_id.is_empty() else str(tile))
	var yaw := 0.0
	if feat.has("yaw"):
		yaw = float(feat.yaw)
	elif feat.has("dir"):
		var d: Vector2i = feat.dir if feat.dir is Vector2i else Vector2i.ZERO
		yaw = atan2(float(d.y), float(d.x))
	var entity_path := ""
	var entity_kind := ""
	if tree:
		for n in tree.get_nodes_in_group("world_entity"):
			if n is Node3D:
				var col := _WorldVisualCoords.column_from_node(n)
				if floori(col.x) == wx and floori(col.y) == wz:
					entity_path = str(n.get_path()) if n.is_inside_tree() else n.name
					entity_kind = str(n.get("entity_kind"))
					break
	var world_pos: Vector3 = _WorldVisualCoords.cell_center(wx, walk, wz)
	var col_aabb: AABB = _WorldVisualCoords.cell_aabb(wx, surf, wz, walk)
	var has_ramp := false
	var ramp_entry: Dictionary = {}
	if cm and cm.has_method("get_ramp_entry_at_world"):
		ramp_entry = cm.get_ramp_entry_at_world(float(wx) + 0.5, float(wz) + 0.5)
		has_ramp = not ramp_entry.is_empty()
	var structure_path := ""
	var visual_yaw := yaw
	var structure_aabb := AABB()
	var structure_count := 0
	if tree:
		var feat_layer = tree.get_first_node_in_group("feature_visual_layer")
		if feat_layer and feat_layer.has_method("get_anchor_at"):
			var anchor = feat_layer.get_anchor_at(wx, wz)
			if anchor is Node and (anchor as Node).is_inside_tree():
				structure_path = str((anchor as Node).get_path())
				if "yaw" in anchor:
					visual_yaw = float(anchor.yaw)
					yaw = visual_yaw
				if anchor is Node3D:
					structure_aabb = _node_aabb(anchor)
				structure_count = 1
	if has_ramp and yaw == 0.0:
		var rd: Vector2i = ramp_entry.get("dir", Vector2i.ZERO)
		if rd != Vector2i.ZERO:
			yaw = atan2(float(rd.y), float(rd.x))
			visual_yaw = yaw
	var cover: Dictionary = _column_mesh_cover(cm, chunk, wx, wz)
	var rendered: AABB = structure_aabb if structure_count > 0 else col_aabb
	var layers: int = int(round(hdelta / maxf(layer, 0.001)))
	var is_passage := bool(feat.get("is_passage", false)) or build_id == "gate"
	var collision_exists := not is_passage
	var collision_kind := "none"
	if is_passage:
		collision_kind = "passage"
	elif streamed or world != null:
		collision_kind = "heightfield_probe"
	var interactable := false
	if world:
		interactable = _ActionTargeting._can_dig_column(world, cm, wx, wz) \
			or _ActionTargeting._can_build_column(world, cm, wx, wz)
	if not feat.is_empty() or not entity_path.is_empty():
		interactable = true
	var discrepancies: PackedStringArray = _collect_discrepancies({
		"wx": wx, "wz": wz, "surf": surf, "walk": walk, "layer": layer,
		"hdelta": hdelta, "streamed": streamed, "cover": cover,
		"build_id": build_id, "visual_id": visual_id,
		"structure_path": structure_path, "structure_count": structure_count,
		"feat": feat, "has_ramp": has_ramp, "is_passage": is_passage,
		"chunk_ramp_count": _chunk_ramp_instance_count(cm, chunk),
		"yaw": yaw, "visual_yaw": visual_yaw,
		"rendered": rendered, "collision": col_aabb,
	})
	return {
		"ok": true,
		"wx": wx,
		"wz": wz,
		"gameplay_coord": [wx, wz],
		"visual_coord": [world_pos.x, world_pos.y, world_pos.z],
		"world_pos": world_pos,
		"chunk": [cx, cz],
		"owning_chunk": "%d,%d" % [cx, cz],
		"tile": tile,
		"voxel_id": tile,
		"visual_id": visual_id,
		"override_tile": override_tile,
		"build_tile": build_tile,
		"build_id": build_id,
		"plant_id": plant_id,
		"feature_kind": kind,
		"feature": feat.duplicate(true) if not feat.is_empty() else {},
		"surface_height": surf,
		"walkable_height": walk,
		"height_delta": hdelta,
		"layer_height": layer,
		"collision_bounds": _aabb_dict(col_aabb),
		"rendered_aabb": _aabb_dict(rendered),
		"mesh_bounds": _aabb_dict(rendered),
		"chunk_mesh_bounds": _aabb_dict(mesh_aabb),
		"orientation_yaw": yaw,
		"visual_yaw": visual_yaw,
		"terrain_layer": layers,
		"column_mesh_covered": bool(cover.get("covered", false)),
		"column_face_codes": cover.get("faces", []),
		"chunk_ramp_count": _chunk_ramp_instance_count(cm, chunk),
		"collision_exists": collision_exists,
		"collision_kind": collision_kind,
		"interactable": interactable,
		"structure_count": structure_count,
		"discrepancies": discrepancies,
		"material": _material_hint(tile, build_id),
		"chunk_view_path": view_path,
		"entity_path": entity_path,
		"entity_kind": entity_kind,
		"structure_path": structure_path,
		"node_path": structure_path if not structure_path.is_empty() else (entity_path if not entity_path.is_empty() else view_path),
		"has_ramp": has_ramp,
		"ramp": ramp_entry.duplicate(true) if not ramp_entry.is_empty() else {},
		"water_level": float(channel.get("water_level", 0.0)) if not channel.is_empty() else 0.0,
		"flow_dir": channel.get("flow_dir", Vector2i.ZERO),
		"is_water": not channel.is_empty() or tile in [_VoxelTypes.OCEAN, _VoxelTypes.OCEAN2, _VoxelTypes.OCEAN3],
		"has_crystal": has_crystal,
		"crystal_depth": crystal_depth,
		"origin": origin,
		"package_ready": package_ready,
		"bake_valid": bake_valid,
		"column_source": column_source,
		"chunk_lifecycle": chunk_lifecycle,
		"streamed": streamed,
		"mesh_current": streamed and bool(cover.get("covered", false)),
		"collision_current": collision_exists,
		"neighbors": _neighbor_summary(cm, world, wx, wz, layer),
		"water_sim": _water_sim(tree),
	}


static func _column_mesh_cover(cm, chunk: Vector2i, wx: int, wz: int) -> Dictionary:
	var out := {"covered": false, "faces": []}
	if cm == null or not ("chunks" in cm) or not cm.chunks.has(chunk):
		return out
	var view = cm.chunks[chunk]
	if view == null or not ("mesh_data" in view):
		return out
	var quads: Array = view.mesh_data.get("quads", [])
	var lx: int = wx - chunk.x * _ChunkData.SIZE
	var lz: int = wz - chunk.y * _ChunkData.SIZE
	var faces: Array = []
	for q_v in quads:
		var q: Dictionary = q_v
		var qx := float(q.get("x", 0.0))
		var qz := float(q.get("z", 0.0))
		var dx := float(q.get("dim_x", 1.0))
		var dz := float(q.get("dim_z", 1.0))
		var fc: int = int(q.get("face_code", 0))
		var in_box := (
			float(lx) + 0.5 >= qx and float(lx) + 0.5 < qx + dx
			and float(lz) + 0.5 >= qz and float(lz) + 0.5 < qz + dz
		)
		if fc >= _WorldVisualCoords.FACE_RAMP:
			# Greedy ramp quads span a rectangle; only the approach and landing
			# columns own the FACE_RAMP, not every cell inside the merged box.
			var rdx := int(q.get("ramp_dir_x", 0))
			var rdz := int(q.get("ramp_dir_z", 0))
			var is_approach := is_equal_approx(float(lx), qx) and is_equal_approx(float(lz), qz)
			var is_landing := (rdx != 0 or rdz != 0) \
				and is_equal_approx(float(lx), qx + float(rdx)) \
				and is_equal_approx(float(lz), qz + float(rdz))
			if not is_approach and not is_landing:
				continue
		elif not in_box:
			continue
		faces.append(fc)
		if fc == _WorldVisualCoords.FACE_TOP or fc >= _WorldVisualCoords.FACE_RAMP:
			out["covered"] = true
	out["faces"] = faces
	return out


static func _chunk_ramp_instance_count(cm, chunk: Vector2i) -> int:
	if cm == null or not ("chunks" in cm) or not cm.chunks.has(chunk):
		return 0
	var view = cm.chunks[chunk]
	if view == null or not ("mesh_data" in view):
		return 0
	var md: Dictionary = view.mesh_data
	return int(md.get("ramp_count", 0)) + int(md.get("corner_count", 0)) + int(md.get("diagonal_count", 0))


static func _neighbor_summary(cm, world, wx: int, wz: int, layer: float) -> Dictionary:
	var out := {}
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = wx + d.x
		var nz: int = wz + d.y
		var chunk := Vector2i(int(floor(float(nx) / float(_ChunkData.SIZE))), int(floor(float(nz) / float(_ChunkData.SIZE))))
		var surf := 0.0
		if world:
			surf = float(world.get_surface_height(float(nx), float(nz)))
		var cover: Dictionary = _column_mesh_cover(cm, chunk, nx, nz)
		var label := "e" if d.x > 0 else ("w" if d.x < 0 else ("s" if d.y > 0 else "n"))
		out[label] = {
			"cell": [nx, nz],
			"surface": surf,
			"walk_guess": surf + layer,
			"covered": bool(cover.get("covered", false)),
			"faces": cover.get("faces", []),
		}
	return out


static func _water_sim(tree: SceneTree) -> Dictionary:
	if tree == null:
		return {}
	var fluid = tree.get_first_node_in_group("voxel_fluid_service")
	if fluid == null or not fluid.has_method("get_sim_diagnostics"):
		return {}
	var d: Dictionary = fluid.get_sim_diagnostics()
	return {
		"sleeping": bool(d.get("sleeping", false)),
		"last_tick_us": int(d.get("last_tick_us", 0)),
		"dirty": int(d.get("dirty_cells", 0)),
		"subset": int(d.get("subset_cells", 0)),
		"phase_us": d.get("phase_us", {}),
	}


static func _collect_discrepancies(p: Dictionary) -> PackedStringArray:
	var d: PackedStringArray = PackedStringArray()
	var layer: float = float(p.layer)
	var walk: float = float(p.walk)
	var surf: float = float(p.surf)
	var hdelta: float = float(p.hdelta)
	if bool(p.streamed) and not bool((p.cover as Dictionary).get("covered", false)):
		d.append("MESH_HOLE: streamed column has no top/ramp quad")
	if absf(walk - (surf + layer)) > layer * 0.35 and not bool(p.has_ramp) and absf(hdelta) < 0.01:
		d.append("HEIGHT: walkable %.2f vs surface+layer %.2f" % [walk, surf + layer])
	if str(p.build_id) != "" and str(p.visual_id) != str(p.build_id):
		d.append("ID: build_id %s != visual_id %s" % [str(p.build_id), str(p.visual_id)])
	if str(p.build_id) != "" and int(p.structure_count) != 1:
		d.append("VISUAL_COUNT: build %s has %d WorldObject(s)" % [str(p.build_id), int(p.structure_count)])
	if str(p.build_id) != "" and str(p.structure_path) == "":
		d.append("NODE: feature has no WorldObject path")
	if absf(float(p.yaw) - float(p.visual_yaw)) > 0.05:
		d.append("YAW: gameplay %.2f vs visual %.2f" % [float(p.yaw), float(p.visual_yaw)])
	if bool(p.is_passage) and hdelta > layer * 0.25:
		d.append("GATE: passage cell still raised Δh=%.2f" % hdelta)
	if bool(p.has_ramp):
		var faces_v = (p.cover as Dictionary).get("faces", [])
		var has_ramp_face := false
		if faces_v is Array or faces_v is PackedInt32Array:
			for fc in faces_v:
				if int(fc) >= _WorldVisualCoords.FACE_RAMP:
					has_ramp_face = true
					break
		if not has_ramp_face:
			d.append("RAMP_VISUAL: ramp_map set but column mesh has no FACE_RAMP quad")
	return d


static func _aabb_dict(a: AABB) -> Dictionary:
	return {
		"pos": [a.position.x, a.position.y, a.position.z],
		"size": [a.size.x, a.size.y, a.size.z],
	}


static func _node_aabb(n: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		if cur is VisualInstance3D:
			var vi := cur as VisualInstance3D
			var local: AABB = vi.get_aabb()
			var xf: Transform3D = vi.global_transform
			var world_a := xf * local
			if first:
				acc = world_a
				first = false
			else:
				acc = acc.merge(world_a)
	return acc


static func _material_hint(tile: int, build_id: String) -> String:
	if not build_id.is_empty():
		_BuildingRegistry.ensure_builtins()
		var def = _BuildingRegistry.get_def(StringName(build_id))
		if def:
			return "%s / tile %d" % [def.display_name, tile]
	return "tile_%d" % tile
