class_name TerrainEdits
extends RefCounted

const _WorldBorder = preload("res://helpers/world_border.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldState = preload("res://world/world_state.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")

const DROP_CAP_PER_SWING := 4


static func _ws():
	return _WorldState.get_active()


static func reset() -> void:
	_ws().reset_terrain()


static func get_height_delta(wx: int, wz: int) -> float:
	var layers: int = int(_ws().height_delta.get(Vector2i(wx, wz), 0))
	return float(layers) * _WorldSettings.get_active().layer_height()


static func get_build_tile(wx: int, wz: int) -> int:
	return int(_ws().build_tile.get(Vector2i(wx, wz), -1))


static func can_edit(wx: int, wz: int) -> bool:
	return _WorldBorder.is_playable(float(wx), float(wz))


static func dig(wx: int, wz: int, amount: int = 1) -> bool:
	if not can_edit(wx, wz):
		return false
	var ws = _ws()
	var key := Vector2i(wx, wz)
	var next: int = int(ws.height_delta.get(key, 0)) - amount
	if next < -6:
		return false
	ws.height_delta[key] = next
	if next == 0 and not ws.build_tile.has(key):
		ws.height_delta.erase(key)
	ws.bump(_WorldState.DOMAIN_TERRAIN)
	return true


static func surface_block_y(world, wx: int, wz: int) -> int:
	if world == null or not world.has_method("get_surface_height"):
		return 0
	var layer: float = _WorldSettings.get_active().layer_height()
	var h: float = float(world.get_surface_height(float(wx), float(wz)))
	return int(round(h / maxf(layer, 0.001)))


static func chunk_for_column(wx: int, wz: int) -> Vector2i:
	var size := _ChunkData.SIZE
	return Vector2i(
		int(floor(float(wx) / float(size))),
		int(floor(float(wz) / float(size)))
	)


static func dig_cells(cells: Array, editor: Object = null) -> Dictionary:
	var world = null
	if editor != null and "world" in editor:
		world = editor.world
	var pending: Array[Vector3i] = []
	var seen := {}
	for raw in cells:
		if not (raw is Vector3i):
			continue
		var cell: Vector3i = raw
		if seen.has(cell):
			continue
		seen[cell] = true
		pending.append(cell)
	pending.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return a.y > b.y
	)
	var removed: Array[Vector3i] = []
	var dug_cells: Array[Vector3i] = []
	var columns := {}
	var dug_count := 0
	var drop_count := 0
	var drop_left := DROP_CAP_PER_SWING
	var ws = _ws()
	ws.begin_batch()
	for cell in pending:
		var why := _dig_listed_cell(cell, world, editor)
		if why == "air":
			removed.append(cell)
			continue
		if why != "dug":
			continue
		removed.append(cell)
		dug_cells.append(cell)
		dug_count += 1
		columns[Vector2i(cell.x, cell.z)] = true
		if drop_left > 0 and editor != null and editor.has_method("grant_break_loot"):
			if bool(editor.grant_break_loot(cell.x, cell.z)):
				drop_count += 1
				drop_left -= 1
	if editor != null and editor.has_method("settle_break_columns") and not columns.is_empty():
		var extra: Array = editor.settle_break_columns(columns.keys())
		for col_v in extra:
			if col_v is Vector2i:
				columns[col_v] = true
	ws.end_batch()
	var by_chunk := {}
	for col_v in columns.keys():
		var col: Vector2i = col_v
		var key := chunk_for_column(col.x, col.y)
		if not by_chunk.has(key):
			by_chunk[key] = []
		(by_chunk[key] as Array).append(col)
	var chunk_keys: Array = by_chunk.keys()
	var remesh := 0
	var water := 0
	var crystal := 0
	for key_v in chunk_keys:
		var key: Vector2i = key_v
		var cols: Array = by_chunk[key]
		if editor != null and editor.has_method("remesh_break_chunk"):
			editor.remesh_break_chunk(key, cols)
		remesh += 1
		if editor != null and editor.has_method("update_break_water"):
			editor.update_break_water(key, cols)
		water += 1
		if editor != null and editor.has_method("update_break_crystal"):
			editor.update_break_crystal(key, cols)
		crystal += 1
	if editor != null and editor.has_method("flush_break_chunks") and not chunk_keys.is_empty():
		editor.flush_break_chunks()
	if removed.is_empty() and editor != null and "last_fail_reason" in editor:
		if str(editor.last_fail_reason).is_empty():
			editor.last_fail_reason = "Can't dig here"
	return {
		"removed": removed,
		"dug": dug_cells,
		"dug_count": dug_count,
		"drop_count": drop_count,
		"chunks": chunk_keys,
		"remesh_count": remesh,
		"water_count": water,
		"crystal_count": crystal,
	}


static func place_cells(cells: Array, tile_id: int, editor: Object = null, build_id: StringName = &"") -> Dictionary:
	var world = _place_world(editor)
	var accepted := _blueprint_stack(cells, world)
	if accepted.is_empty():
		if not cells.is_empty():
			_place_fail(editor, "Can't place here")
		return _empty_place()
	var ws = _ws()
	ws.begin_batch()
	var placed: Array[Vector3i] = []
	var columns := {}
	for cell in accepted:
		if not build_wall(cell.x, cell.z, tile_id):
			for done in placed:
				unstack_build(done.x, done.z)
			ws.end_batch()
			_place_fail(editor, "Stack full")
			return _empty_place()
		placed.append(cell)
		columns[Vector2i(cell.x, cell.z)] = true
	if build_id != &"" and editor != null and editor.has_method("stamp_blueprint_column"):
		for col_v in columns.keys():
			editor.stamp_blueprint_column(col_v, build_id)
	ws.end_batch()
	return _finish_place(placed, columns, editor)


static func _place_world(editor: Object):
	if editor != null and "world" in editor:
		return editor.world
	return null


static func _place_fail(editor: Object, reason: String) -> void:
	if editor != null and "last_fail_reason" in editor and str(editor.last_fail_reason).is_empty():
		editor.last_fail_reason = reason


static func _empty_place() -> Dictionary:
	return {
		"placed": [],
		"placed_count": 0,
		"columns": [],
		"chunks": [],
		"remesh_count": 0,
		"water_count": 0,
		"crystal_count": 0,
	}


static func _blueprint_stack(cells: Array, world) -> Array[Vector3i]:
	var by_col := {}
	var seen := {}
	for raw in cells:
		if not (raw is Vector3i):
			return []
		var cell: Vector3i = raw
		if seen.has(cell):
			continue
		seen[cell] = true
		if not can_edit(cell.x, cell.z):
			return []
		var key := Vector2i(cell.x, cell.z)
		if not by_col.has(key):
			by_col[key] = []
		(by_col[key] as Array).append(cell)
	var ordered: Array[Vector3i] = []
	for key_v in by_col.keys():
		var key: Vector2i = key_v
		var stack: Array = by_col[key]
		stack.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
			return a.y < b.y
		)
		var layers: int = int(_ws().height_delta.get(key, 0))
		if layers + stack.size() > 8:
			return []
		var expect := surface_block_y(world, key.x, key.y) + 1
		for item in stack:
			var stacked: Vector3i = item
			if stacked.y != expect:
				return []
			ordered.append(stacked)
			expect += 1
	return ordered


static func _finish_place(placed: Array[Vector3i], columns: Dictionary, editor: Object) -> Dictionary:
	var by_chunk := {}
	for col_v in columns.keys():
		var col: Vector2i = col_v
		var key := chunk_for_column(col.x, col.y)
		if not by_chunk.has(key):
			by_chunk[key] = []
		(by_chunk[key] as Array).append(col)
	var chunk_keys: Array = by_chunk.keys()
	var remesh := 0
	var water := 0
	var crystal := 0
	for key_v in chunk_keys:
		var key: Vector2i = key_v
		var cols: Array = by_chunk[key]
		if editor != null and editor.has_method("remesh_break_chunk"):
			editor.remesh_break_chunk(key, cols)
		remesh += 1
		if editor != null and editor.has_method("update_break_water"):
			editor.update_break_water(key, cols)
		water += 1
		if editor != null and editor.has_method("update_place_crystal"):
			editor.update_place_crystal(key, cols)
		elif editor != null and editor.has_method("update_break_crystal"):
			editor.update_break_crystal(key, cols)
		crystal += 1
	if editor != null and editor.has_method("flush_break_chunks") and not chunk_keys.is_empty():
		editor.flush_break_chunks()
	return {
		"placed": placed,
		"placed_count": placed.size(),
		"columns": columns.keys(),
		"chunks": chunk_keys,
		"remesh_count": remesh,
		"water_count": water,
		"crystal_count": crystal,
	}


static func clip_breakable_cells(cells: Array, world, editor = null) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var seen := {}
	for raw in cells:
		if not (raw is Vector3i):
			continue
		var cell: Vector3i = raw
		if seen.has(cell):
			continue
		seen[cell] = true
		if _cell_break_status(cell, world, editor) == "ready":
			out.append(cell)
	return out


static func _cell_break_status(cell: Vector3i, world, editor) -> String:
	if not can_edit(cell.x, cell.z):
		return "skip"
	if editor != null and editor.has_method("break_cell_blocked"):
		var block := str(editor.break_cell_blocked(cell.x, cell.z))
		if not block.is_empty():
			return block
	var top := surface_block_y(world, cell.x, cell.z)
	if cell.y > top:
		return "air"
	if cell.y < top:
		return "buried"
	if world != null and world.has_method("get_surface_height"):
		var min_h: float = -_WorldSettings.get_active().layer_height() * 4.0
		if float(world.get_surface_height(float(cell.x), float(cell.z))) <= min_h:
			return "floor"
	var next: int = int(_ws().height_delta.get(Vector2i(cell.x, cell.z), 0)) - 1
	if next < -6:
		return "floor"
	return "ready"


static func _dig_listed_cell(cell: Vector3i, world, editor: Object) -> String:
	var status := _cell_break_status(cell, world, editor)
	if status != "ready":
		return status
	if not dig(cell.x, cell.z, 1):
		return "floor"
	if world != null and world.has_method("invalidate_column_cache"):
		world.invalidate_column_cache(cell.x, cell.z)
	return "dug"


static func build_wall(wx: int, wz: int, tile_id: int) -> bool:
	if not can_edit(wx, wz):
		return false
	var ws = _ws()
	var key := Vector2i(wx, wz)
	var next: int = int(ws.height_delta.get(key, 0)) + 1
	if next > 8:
		return false
	ws.height_delta[key] = next
	ws.build_tile[key] = tile_id
	ws.bump(_WorldState.DOMAIN_TERRAIN)
	return true


static func set_build_tile_only(wx: int, wz: int, tile_id: int) -> bool:
	if not can_edit(wx, wz):
		return false
	var ws = _ws()
	var key := Vector2i(wx, wz)
	ws.build_tile[key] = tile_id
	ws.bump(_WorldState.DOMAIN_TERRAIN)
	return true


static func unstack_build(wx: int, wz: int) -> bool:
	if not can_edit(wx, wz):
		return false
	var ws = _ws()
	var key := Vector2i(wx, wz)
	var layers: int = int(ws.height_delta.get(key, 0))
	if layers <= 0 and not ws.build_tile.has(key):
		return false
	var next: int = layers - 1
	if next > 0:
		ws.height_delta[key] = next
	else:
		ws.height_delta.erase(key)
		ws.build_tile.erase(key)
	ws.bump(_WorldState.DOMAIN_TERRAIN)
	return true


static func remove_structure_cells(cells: Array, editor: Object = null) -> Dictionary:
	const _Features = preload("res://world/feature_registry.gd")
	var ws = _ws()
	var removed: Array[Vector3i] = []
	var columns := {}
	ws.begin_batch()
	for raw in cells:
		if not raw is Dictionary:
			continue
		var at := Vector3i(int(raw.get("x", 0)), int(raw.get("y", 0)), int(raw.get("z", 0)))
		var role := str(raw.get("role", "wall"))
		if role == "passage":
			clear_build_tile(at.x, at.z)
		elif not unstack_build(at.x, at.z):
			continue
		removed.append(at)
		columns[Vector2i(at.x, at.z)] = true
	for col_v in columns.keys():
		var col: Vector2i = col_v
		_Features.clear_feature(col.x, col.y)
	ws.end_batch()
	var by_chunk := {}
	for col_v in columns.keys():
		var col: Vector2i = col_v
		var key := chunk_for_column(col.x, col.y)
		if not by_chunk.has(key):
			by_chunk[key] = []
		(by_chunk[key] as Array).append(col)
	var chunk_keys: Array = by_chunk.keys()
	var remesh := 0
	var water := 0
	var crystal := 0
	for key_v in chunk_keys:
		var key: Vector2i = key_v
		var cols: Array = by_chunk[key]
		if editor != null and editor.has_method("remesh_break_chunk"):
			editor.remesh_break_chunk(key, cols)
		remesh += 1
		if editor != null and editor.has_method("update_break_water"):
			editor.update_break_water(key, cols)
		water += 1
		if editor != null and editor.has_method("update_break_crystal"):
			editor.update_break_crystal(key, cols)
		crystal += 1
	if editor != null and editor.has_method("flush_break_chunks") and not chunk_keys.is_empty():
		editor.flush_break_chunks()
	return {
		"removed": removed,
		"removed_count": removed.size(),
		"columns": columns.keys(),
		"chunks": chunk_keys,
		"remesh_count": remesh,
		"water_count": water,
		"crystal_count": crystal,
		"edits": 1 if not removed.is_empty() else 0,
	}


static func clear_build_tile(wx: int, wz: int) -> void:
	if not can_edit(wx, wz):
		return
	var ws = _ws()
	var key := Vector2i(wx, wz)
	ws.build_tile.erase(key)
	if int(ws.height_delta.get(key, 0)) == 0:
		ws.height_delta.erase(key)
	ws.bump(_WorldState.DOMAIN_TERRAIN)


static func edit_count() -> int:
	return _ws().height_delta.size()


static func to_dict() -> Dictionary:
	const _Codec = preload("res://systems/save_codec.gd")
	var ws = _ws()
	return {
		"height_delta": _Codec.encode_vec2i_dict(ws.height_delta),
		"build_tile": _Codec.encode_vec2i_dict(ws.build_tile),
	}


static func load_from_dict(data: Dictionary) -> void:
	const _Codec = preload("res://systems/save_codec.gd")
	var ws = _ws()
	ws.begin_batch()
	ws.height_delta = _Codec.decode_vec2i_dict(data.get("height_delta", {}))
	ws.build_tile = _Codec.decode_vec2i_dict(data.get("build_tile", {}))
	ws.bump(_WorldState.DOMAIN_TERRAIN)
	ws.end_batch()
