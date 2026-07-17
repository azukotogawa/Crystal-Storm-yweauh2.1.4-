class_name SpatialQueryLayer
extends RefCounted
## Authoritative spatial discovery index. Indexes and returns references only — no gameplay.
## Steady-state queries use a uniform grid (not full linear scans over all instances).

## Typed categories (bit flags for multi-category queries).
const CAT_TERRAIN := 1
const CAT_CRYSTAL := 2
const CAT_FLUID := 4
const CAT_ENTITY := 8
const CAT_STRUCTURE := 16
const CAT_TOWN := 32
const CAT_PROJECTILE := 64
const CAT_AI := 128
const CAT_ALL := 255

const CATEGORY_NAMES := {
	CAT_TERRAIN: "terrain",
	CAT_CRYSTAL: "crystal",
	CAT_FLUID: "fluid",
	CAT_ENTITY: "entity",
	CAT_STRUCTURE: "structure",
	CAT_TOWN: "town",
	CAT_PROJECTILE: "projectile",
	CAT_AI: "ai",
}

## Default grid cell size in world units (XZ). ChunkData.SIZE is 16; half is a good default.
var cell_size: float = 8.0
var chunk_size: int = 16

## Instrumentation (for perf verifies / diagnostics).
var cells_visited: int = 0
var entries_examined: int = 0
var query_count: int = 0

var _next_id: int = 1
var _entries: Dictionary = {}  # id -> Dictionary
var _grid: Dictionary = {}  # Vector2i cell -> Dictionary of id -> true
var _by_category: Dictionary = {}  # category int -> Dictionary of id -> true
var _chunk_objects: Dictionary = {}  # Vector2i chunk -> Dictionary of id -> true
var _loaded_chunks: Dictionary = {}  # Vector2i -> true
var _static_ids: Dictionary = {}  # id -> true
var _dynamic_ids: Dictionary = {}  # id -> true
var _payload_to_id: Dictionary = {}  # instance_id (int) or stable string -> id


func clear() -> void:
	_entries.clear()
	_grid.clear()
	_by_category.clear()
	_chunk_objects.clear()
	_loaded_chunks.clear()
	_static_ids.clear()
	_dynamic_ids.clear()
	_payload_to_id.clear()
	_next_id = 1
	cells_visited = 0
	entries_examined = 0
	query_count = 0


func count() -> int:
	return _entries.size()


func count_category(category: int) -> int:
	var bag: Dictionary = _by_category.get(category, {})
	return bag.size()


## All entries matching category mask (no spatial filter). Prefer over huge-radius queries.
func iter_category(categories: int = CAT_ALL) -> Array:
	var hits: Array = []
	for id_v in _entries.keys():
		var e: Dictionary = _entries[id_v]
		if not _category_match(int(e.category), categories):
			continue
		hits.append(_hit_dict(e, 0.0))
	_sort_hits(hits)
	return hits


func loaded_chunk_count() -> int:
	return _loaded_chunks.size()


func has_handle(id: int) -> bool:
	return _entries.has(id)


func get_entry(id: int) -> Dictionary:
	if not _entries.has(id):
		return {}
	return (_entries[id] as Dictionary).duplicate(true)


## Insert object. payload may be Node, Object, Dictionary, or null.
## stable_key used for deterministic tie-breaking (defaults to str(id)).
func insert(
	category: int,
	pos: Vector3,
	radius: float = 0.35,
	payload = null,
	dynamic: bool = true,
	stable_key: String = "",
	chunk_coord: Vector2i = Vector2i(2147483647, 2147483647)
) -> int:
	var id: int = _next_id
	_next_id += 1
	var cell := _pos_to_cell(pos)
	var chunk := chunk_coord
	if chunk.x == 2147483647:
		chunk = _pos_to_chunk(pos)
	var key := stable_key if not stable_key.is_empty() else ("h%d" % id)
	var entry := {
		"id": id,
		"category": category,
		"pos": pos,
		"radius": radius,
		"cell": cell,
		"chunk": chunk,
		"dynamic": dynamic,
		"stable_key": key,
		"payload": payload,
	}
	_entries[id] = entry
	_grid_add(cell, id)
	_cat_add(category, id)
	_chunk_add(chunk, id)
	if dynamic:
		_dynamic_ids[id] = true
	else:
		_static_ids[id] = true
	_index_payload(payload, id)
	return id


func remove(id: int) -> bool:
	if not _entries.has(id):
		return false
	var e: Dictionary = _entries[id]
	_grid_remove(e.cell, id)
	_cat_remove(int(e.category), id)
	_chunk_remove(e.chunk, id)
	if bool(e.dynamic):
		_dynamic_ids.erase(id)
	else:
		_static_ids.erase(id)
	_unindex_payload(e.get("payload"), id)
	_entries.erase(id)
	return true


func remove_by_payload(payload) -> bool:
	var id: int = find_id_by_payload(payload)
	if id < 0:
		return false
	return remove(id)


func find_id_by_payload(payload) -> int:
	if payload == null:
		return -1
	var key = _payload_key(payload)
	if key == null:
		return -1
	return int(_payload_to_id.get(key, -1))


## Move dynamic (or any) object; only touches old/new grid cells.
func move(id: int, new_pos: Vector3, new_radius: float = -1.0) -> bool:
	if not _entries.has(id):
		return false
	var e: Dictionary = _entries[id]
	var old_cell: Vector2i = e.cell
	var new_cell := _pos_to_cell(new_pos)
	var new_chunk := _pos_to_chunk(new_pos)
	e.pos = new_pos
	if new_radius >= 0.0:
		e.radius = new_radius
	if new_cell != old_cell:
		_grid_remove(old_cell, id)
		_grid_add(new_cell, id)
		e.cell = new_cell
	var old_chunk: Vector2i = e.chunk
	if new_chunk != old_chunk:
		_chunk_remove(old_chunk, id)
		_chunk_add(new_chunk, id)
		e.chunk = new_chunk
	return true


func mark_chunk_loaded(coord: Vector2i) -> void:
	_loaded_chunks[coord] = true


func mark_chunk_unloaded(coord: Vector2i, remove_objects: bool = true) -> void:
	_loaded_chunks.erase(coord)
	if not remove_objects:
		return
	var bag: Dictionary = _chunk_objects.get(coord, {})
	var ids: Array = bag.keys()
	for id_v in ids:
		remove(int(id_v))


func is_chunk_loaded(coord: Vector2i) -> bool:
	return _loaded_chunks.has(coord)


## WorldState / overlay region invalidation — removes static entries whose XZ falls in AABB.
func invalidate_region(min_xz: Vector2, max_xz: Vector2, categories: int = CAT_ALL) -> int:
	var removed := 0
	var to_drop: Array = []
	for id_v in _static_ids.keys():
		var id: int = int(id_v)
		var e: Dictionary = _entries.get(id, {})
		if e.is_empty():
			continue
		if not _category_match(int(e.category), categories):
			continue
		var p: Vector3 = e.pos
		if p.x < min_xz.x or p.x > max_xz.x or p.z < min_xz.y or p.z > max_xz.y:
			continue
		to_drop.append(id)
	for id in to_drop:
		if remove(int(id)):
			removed += 1
	return removed


## Full rebuild helper used by save restore after clear.
func rebuild_begin() -> void:
	clear()


func rebuild_end() -> void:
	pass  # reserved for future compaction


# ── Queries ──────────────────────────────────────────────────────────────


func query_radius(
	center: Vector3,
	radius: float,
	categories: int = CAT_ALL,
	max_results: int = -1
) -> Array:
	query_count += 1
	cells_visited = 0
	entries_examined = 0
	var r2 := radius * radius
	var min_c := _pos_to_cell(center - Vector3(radius, 0, radius))
	var max_c := _pos_to_cell(center + Vector3(radius, 0, radius))
	var hits: Array = []
	for cz in range(min_c.y, max_c.y + 1):
		for cx in range(min_c.x, max_c.x + 1):
			var cell := Vector2i(cx, cz)
			cells_visited += 1
			var bag: Dictionary = _grid.get(cell, {})
			for id_v in bag.keys():
				var e: Dictionary = _entries.get(int(id_v), {})
				if e.is_empty():
					continue
				entries_examined += 1
				if not _category_match(int(e.category), categories):
					continue
				var p: Vector3 = e.pos
				var dx := p.x - center.x
				var dz := p.z - center.z
				var d2 := dx * dx + dz * dz
				var er: float = float(e.radius)
				var limit := radius + er
				if d2 > limit * limit:
					continue
				var dist := sqrt(d2)
				hits.append(_hit_dict(e, dist))
	_sort_hits(hits)
	if max_results >= 0 and hits.size() > max_results:
		hits.resize(max_results)
	return hits


func query_aabb(
	min_pos: Vector3,
	max_pos: Vector3,
	categories: int = CAT_ALL,
	max_results: int = -1
) -> Array:
	query_count += 1
	cells_visited = 0
	entries_examined = 0
	var min_c := _pos_to_cell(min_pos)
	var max_c := _pos_to_cell(max_pos)
	var hits: Array = []
	for cz in range(mini(min_c.y, max_c.y), maxi(min_c.y, max_c.y) + 1):
		for cx in range(mini(min_c.x, max_c.x), maxi(min_c.x, max_c.x) + 1):
			var cell := Vector2i(cx, cz)
			cells_visited += 1
			var bag: Dictionary = _grid.get(cell, {})
			for id_v in bag.keys():
				var e: Dictionary = _entries.get(int(id_v), {})
				if e.is_empty():
					continue
				entries_examined += 1
				if not _category_match(int(e.category), categories):
					continue
				var p: Vector3 = e.pos
				if p.x < min_pos.x or p.x > max_pos.x or p.z < min_pos.z or p.z > max_pos.z:
					continue
				if p.y < min_pos.y or p.y > max_pos.y:
					continue
				var cx_mid := (min_pos.x + max_pos.x) * 0.5
				var cz_mid := (min_pos.z + max_pos.z) * 0.5
				var dist := Vector2(p.x - cx_mid, p.z - cz_mid).length()
				hits.append(_hit_dict(e, dist))
	_sort_hits(hits)
	if max_results >= 0 and hits.size() > max_results:
		hits.resize(max_results)
	return hits


func query_nearest(
	center: Vector3,
	categories: int = CAT_ALL,
	max_count: int = 1,
	max_radius: float = INF
) -> Array:
	if max_count <= 0:
		return []
	# Expanding ring search until enough hits or max_radius.
	query_count += 1
	cells_visited = 0
	entries_examined = 0
	var hits: Array = []
	var center_cell := _pos_to_cell(center)
	var max_ring := 0
	if is_finite(max_radius):
		max_ring = int(ceil(max_radius / cell_size)) + 1
	else:
		max_ring = 64  # safety
	var seen: Dictionary = {}
	for ring in range(0, max_ring + 1):
		var ring_cells := _ring_cells(center_cell, ring)
		for cell in ring_cells:
			cells_visited += 1
			var bag: Dictionary = _grid.get(cell, {})
			for id_v in bag.keys():
				var id: int = int(id_v)
				if seen.has(id):
					continue
				seen[id] = true
				var e: Dictionary = _entries.get(id, {})
				if e.is_empty():
					continue
				entries_examined += 1
				if not _category_match(int(e.category), categories):
					continue
				var p: Vector3 = e.pos
				var dx := p.x - center.x
				var dz := p.z - center.z
				var dist := sqrt(dx * dx + dz * dz)
				if dist > max_radius + float(e.radius):
					continue
				hits.append(_hit_dict(e, dist))
		# After each ring, if we have enough within the covered radius, can stop early
		# once ring*cell_size covers the k-th distance.
		if hits.size() >= max_count and ring > 0:
			_sort_hits(hits)
			var kth: float = float(hits[max_count - 1].distance)
			if float(ring) * cell_size >= kth:
				hits.resize(max_count)
				return hits
	_sort_hits(hits)
	if hits.size() > max_count:
		hits.resize(max_count)
	return hits


## Line / object raycast in XZ (Y tolerance optional). Returns hits sorted by ray parameter t.
func query_ray(
	origin: Vector3,
	direction: Vector3,
	max_distance: float,
	categories: int = CAT_ALL,
	y_tolerance: float = INF,
	max_results: int = -1
) -> Array:
	query_count += 1
	cells_visited = 0
	entries_examined = 0
	var dir := Vector3(direction.x, 0.0, direction.z)
	if dir.length_squared() < 0.0001:
		return []
	dir = dir.normalized()
	# March grid cells along the ray.
	var hits: Array = []
	var seen: Dictionary = {}
	var step := cell_size * 0.5
	var t := 0.0
	while t <= max_distance:
		var p := origin + dir * t
		var cell := _pos_to_cell(p)
		if not seen.has(cell):
			seen[cell] = true
			cells_visited += 1
			var bag: Dictionary = _grid.get(cell, {})
			for id_v in bag.keys():
				var e: Dictionary = _entries.get(int(id_v), {})
				if e.is_empty():
					continue
				entries_examined += 1
				if not _category_match(int(e.category), categories):
					continue
				var ep: Vector3 = e.pos
				if absf(ep.y - origin.y) > y_tolerance and y_tolerance < INF:
					# also check against closest point on ray
					pass
				var to_c := ep - origin
				var tt := to_c.x * dir.x + to_c.z * dir.z
				if tt < 0.0 or tt > max_distance:
					continue
				var closest := origin + dir * tt
				var miss := Vector2(ep.x - closest.x, ep.z - closest.z).length()
				if miss > float(e.radius):
					continue
				if y_tolerance < INF and absf(ep.y - closest.y) > y_tolerance:
					continue
				var h := _hit_dict(e, tt)
				h["t"] = tt
				hits.append(h)
		t += step
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := float(a.get("t", a.distance))
		var tb := float(b.get("t", b.distance))
		if absf(ta - tb) > 0.0001:
			return ta < tb
		return str(a.stable_key) < str(b.stable_key)
	)
	# Dedupe by id
	var unique: Array = []
	var seen_id: Dictionary = {}
	for h in hits:
		var hid: int = int(h.id)
		if seen_id.has(hid):
			continue
		seen_id[hid] = true
		unique.append(h)
	if max_results >= 0 and unique.size() > max_results:
		unique.resize(max_results)
	return unique


## Iterate all entries whose grid cell is in [min_cell, max_cell] inclusive.
func iter_region(min_cell: Vector2i, max_cell: Vector2i, categories: int = CAT_ALL) -> Array:
	query_count += 1
	cells_visited = 0
	entries_examined = 0
	var hits: Array = []
	for cz in range(mini(min_cell.y, max_cell.y), maxi(min_cell.y, max_cell.y) + 1):
		for cx in range(mini(min_cell.x, max_cell.x), maxi(min_cell.x, max_cell.x) + 1):
			var cell := Vector2i(cx, cz)
			cells_visited += 1
			var bag: Dictionary = _grid.get(cell, {})
			for id_v in bag.keys():
				var e: Dictionary = _entries.get(int(id_v), {})
				if e.is_empty():
					continue
				entries_examined += 1
				if not _category_match(int(e.category), categories):
					continue
				hits.append(_hit_dict(e, 0.0))
	_sort_hits(hits)
	return hits


## Objects in chunks within Chebyshev neighborhood ring of center chunk (incl. center).
func iter_chunk_neighborhood(center_chunk: Vector2i, ring: int = 1, categories: int = CAT_ALL) -> Array:
	query_count += 1
	var hits: Array = []
	for dz in range(-ring, ring + 1):
		for dx in range(-ring, ring + 1):
			var coord := Vector2i(center_chunk.x + dx, center_chunk.y + dz)
			var bag: Dictionary = _chunk_objects.get(coord, {})
			for id_v in bag.keys():
				var e: Dictionary = _entries.get(int(id_v), {})
				if e.is_empty():
					continue
				if not _category_match(int(e.category), categories):
					continue
				hits.append(_hit_dict(e, 0.0))
	_sort_hits(hits)
	return hits


func iter_loaded_chunks() -> Array:
	var out: Array = _loaded_chunks.keys()
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	return out


## Intentional O(n) full scan for perf regression baseline only.
func query_radius_linear_scan(center: Vector3, radius: float, categories: int = CAT_ALL) -> Array:
	query_count += 1
	entries_examined = 0
	cells_visited = _entries.size()
	var hits: Array = []
	var limit := radius
	for id_v in _entries.keys():
		var e: Dictionary = _entries[id_v]
		entries_examined += 1
		if not _category_match(int(e.category), categories):
			continue
		var p: Vector3 = e.pos
		var dx := p.x - center.x
		var dz := p.z - center.z
		var dist := sqrt(dx * dx + dz * dz)
		if dist > limit + float(e.radius):
			continue
		hits.append(_hit_dict(e, dist))
	_sort_hits(hits)
	return hits


func diagnostics() -> Dictionary:
	return {
		"entry_count": _entries.size(),
		"grid_cells": _grid.size(),
		"loaded_chunks": _loaded_chunks.size(),
		"static_count": _static_ids.size(),
		"dynamic_count": _dynamic_ids.size(),
		"cell_size": cell_size,
		"chunk_size": chunk_size,
		"last_cells_visited": cells_visited,
		"last_entries_examined": entries_examined,
		"query_count": query_count,
		"categories": {
			"entity": count_category(CAT_ENTITY),
			"ai": count_category(CAT_AI),
			"crystal": count_category(CAT_CRYSTAL),
			"structure": count_category(CAT_STRUCTURE),
			"town": count_category(CAT_TOWN),
			"terrain": count_category(CAT_TERRAIN),
			"fluid": count_category(CAT_FLUID),
			"projectile": count_category(CAT_PROJECTILE),
		},
	}


# ── Internals ────────────────────────────────────────────────────────────


func _pos_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / cell_size), floori(pos.z / cell_size))


func _pos_to_chunk(pos: Vector3) -> Vector2i:
	var cs := float(chunk_size)
	return Vector2i(floori(pos.x / cs), floori(pos.z / cs))


func _category_match(entry_cat: int, mask: int) -> bool:
	if mask == CAT_ALL:
		return true
	return (entry_cat & mask) != 0


func _hit_dict(e: Dictionary, dist: float) -> Dictionary:
	return {
		"id": int(e.id),
		"category": int(e.category),
		"pos": e.pos,
		"radius": float(e.radius),
		"distance": dist,
		"stable_key": str(e.stable_key),
		"payload": e.payload,
		"chunk": e.chunk,
		"cell": e.cell,
		"dynamic": bool(e.dynamic),
	}


func _sort_hits(hits: Array) -> void:
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := float(a.distance)
		var db := float(b.distance)
		if absf(da - db) > 0.0001:
			return da < db
		var ka := str(a.stable_key)
		var kb := str(b.stable_key)
		if ka != kb:
			return ka < kb
		return int(a.id) < int(b.id)
	)


func _ring_cells(center: Vector2i, ring: int) -> Array:
	var out: Array = []
	if ring == 0:
		out.append(center)
		return out
	for dx in range(-ring, ring + 1):
		out.append(Vector2i(center.x + dx, center.y - ring))
		out.append(Vector2i(center.x + dx, center.y + ring))
	for dz in range(-ring + 1, ring):
		out.append(Vector2i(center.x - ring, center.y + dz))
		out.append(Vector2i(center.x + ring, center.y + dz))
	return out


func _grid_add(cell: Vector2i, id: int) -> void:
	if not _grid.has(cell):
		_grid[cell] = {}
	(_grid[cell] as Dictionary)[id] = true


func _grid_remove(cell: Vector2i, id: int) -> void:
	if not _grid.has(cell):
		return
	var bag: Dictionary = _grid[cell]
	bag.erase(id)
	if bag.is_empty():
		_grid.erase(cell)


func _cat_add(category: int, id: int) -> void:
	if not _by_category.has(category):
		_by_category[category] = {}
	(_by_category[category] as Dictionary)[id] = true


func _cat_remove(category: int, id: int) -> void:
	if not _by_category.has(category):
		return
	var bag: Dictionary = _by_category[category]
	bag.erase(id)
	if bag.is_empty():
		_by_category.erase(category)


func _chunk_add(coord: Vector2i, id: int) -> void:
	if not _chunk_objects.has(coord):
		_chunk_objects[coord] = {}
	(_chunk_objects[coord] as Dictionary)[id] = true


func _chunk_remove(coord: Vector2i, id: int) -> void:
	if not _chunk_objects.has(coord):
		return
	var bag: Dictionary = _chunk_objects[coord]
	bag.erase(id)
	if bag.is_empty():
		_chunk_objects.erase(coord)


func _payload_key(payload):
	if payload == null:
		return null
	if payload is Object:
		return (payload as Object).get_instance_id()
	if payload is String or payload is StringName:
		return str(payload)
	if payload is Dictionary and payload.has("id"):
		return "d:%s" % str(payload.id)
	return null


func _index_payload(payload, id: int) -> void:
	var key = _payload_key(payload)
	if key != null:
		_payload_to_id[key] = id


func _unindex_payload(payload, id: int) -> void:
	var key = _payload_key(payload)
	if key != null and int(_payload_to_id.get(key, -1)) == id:
		_payload_to_id.erase(key)
