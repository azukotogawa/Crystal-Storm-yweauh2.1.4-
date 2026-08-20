class_name SpatialQueryService
extends Node
## Scene-facing Spatial Query Layer owner. Wires chunk/entity/WorldState updates.
## Discovery only — no combat damage, AI decisions, or simulation rules.

const _SpatialQueryLayer = preload("res://systems/spatial_query_layer.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldState = preload("res://world/world_state.gd")

static var _active = null

## SpatialQueryLayer instance (typed as Variant to avoid class_name load-order issues).
var layer = null
var _chunk_manager = null
var _entity_manager = null
var _crystal_manager = null
var _world_state = null
var _bound_chunk_signals: bool = false
var _tracked_nodes: Dictionary = {}  # instance_id -> spatial handle id
## Stream wake counters (measurement).
var _stream_ready_n: int = 0
var _stream_ready_us: int = 0
var _stream_ready_max_us: int = 0
## Coalesce full static reindex to once per frame (dig/build used to reindex all chunks per edit).
var _static_reindex_pending: bool = false
var _static_reindex_domains: int = 0


func _init() -> void:
	if layer == null:
		layer = _SpatialQueryLayer.new()


static func get_active():
	return _active


static func get_layer():
	if _active and _active.layer:
		return _active.layer
	return null


func _enter_tree() -> void:
	_active = self
	add_to_group("spatial_query_service")
	if layer == null:
		layer = _SpatialQueryLayer.new()


func _exit_tree() -> void:
	if _active == self:
		_active = null


func get_diagnostics() -> Dictionary:
	var d: Dictionary = layer.diagnostics() if layer else {}
	d["service"] = "spatial_query_service"
	d["tracked_nodes"] = _tracked_nodes.size()
	d["chunk_manager_bound"] = _chunk_manager != null
	return d


func bind_chunk_manager(cm) -> void:
	if cm == null:
		return
	if _chunk_manager == cm and _bound_chunk_signals:
		return
	_unbind_chunk_signals()
	_chunk_manager = cm
	if cm.has_signal("chunk_ready") and not cm.chunk_ready.is_connected(_on_chunk_ready):
		cm.chunk_ready.connect(_on_chunk_ready)
	if cm.has_signal("chunk_unloaded") and not cm.chunk_unloaded.is_connected(_on_chunk_unloaded):
		cm.chunk_unloaded.connect(_on_chunk_unloaded)
	_bound_chunk_signals = true
	# Index already-resident chunks
	if "chunks" in cm:
		for coord in cm.chunks.keys():
			_on_chunk_ready(coord, null)


func _unbind_chunk_signals() -> void:
	if _chunk_manager == null:
		return
	if _chunk_manager.has_signal("chunk_ready") and _chunk_manager.chunk_ready.is_connected(_on_chunk_ready):
		_chunk_manager.chunk_ready.disconnect(_on_chunk_ready)
	if _chunk_manager.has_signal("chunk_unloaded") and _chunk_manager.chunk_unloaded.is_connected(_on_chunk_unloaded):
		_chunk_manager.chunk_unloaded.disconnect(_on_chunk_unloaded)
	_bound_chunk_signals = false


func bind_entity_manager(em) -> void:
	_entity_manager = em
	if em == null:
		return
	if em.has_signal("entity_spawned") and not em.entity_spawned.is_connected(_on_entity_spawned):
		em.entity_spawned.connect(_on_entity_spawned)
	if em.has_signal("entity_despawned") and not em.entity_despawned.is_connected(_on_entity_despawned):
		em.entity_despawned.connect(_on_entity_despawned)
	# Index current entities
	if "_entities" in em:
		for ent in em._entities:
			if is_instance_valid(ent):
				_register_node(ent, _SpatialQueryLayer.CAT_ENTITY, true)


func bind_crystal_manager(cm) -> void:
	_crystal_manager = cm
	_reindex_crystal_spawns()


func bind_world_state(ws) -> void:
	_world_state = ws
	if ws == null:
		return
	if ws.has_signal("changed") and not ws.changed.is_connected(_on_world_state_changed):
		ws.changed.connect(_on_world_state_changed)


## Trace counter (measurement only).
var _trace_ws_changed_count: int = 0
var _trace_ws_changed_enabled: bool = false
var _trace_ws_reindex_chunks: int = 0


func reset_trace_counters() -> void:
	_trace_ws_changed_count = 0
	_trace_ws_reindex_chunks = 0
	_trace_ws_changed_enabled = true


func stop_trace_counters() -> void:
	_trace_ws_changed_enabled = false


func get_trace_ws_changed_count() -> int:
	return _trace_ws_changed_count


func get_trace_ws_reindex_chunks() -> int:
	return _trace_ws_reindex_chunks


func _on_world_state_changed(domain: int, _revision: int) -> void:
	# Domain-level invalidation: drop static feature markers; consumers re-query WorldState/features.
	# We reindex loaded-chunk statics only (incremental to loaded set).
	if layer == null:
		return
	if _trace_ws_changed_enabled:
		_trace_ws_changed_count += 1
	# Height digs/builds (DOMAIN_TERRAIN only) do not move structure/town static markers.
	# Reindexing every loaded chunk here was the dominant dig/build hitch (~7–15ms).
	var feature_bits: int = _WorldState.DOMAIN_FEATURE | _WorldState.DOMAIN_FEATURE_TILE
	if (domain & feature_bits) == 0:
		return
	# Coalesce many feature edits in one frame into a single reindex pass.
	_static_reindex_domains |= domain
	if _static_reindex_pending:
		return
	_static_reindex_pending = true
	call_deferred("_flush_static_reindex")


func _flush_static_reindex() -> void:
	_static_reindex_pending = false
	if layer == null:
		return
	var loaded: Array = layer.iter_loaded_chunks()
	if _trace_ws_changed_enabled:
		_trace_ws_reindex_chunks += loaded.size()
	for coord_v in loaded:
		_remove_static_in_chunk(coord_v)
		_index_static_features_in_chunk(coord_v)
	_static_reindex_domains = 0


func reset_stream_wake_trace() -> void:
	_stream_ready_n = 0
	_stream_ready_us = 0
	_stream_ready_max_us = 0


func get_stream_wake_trace() -> Dictionary:
	return {
		"chunk_ready_n": _stream_ready_n,
		"chunk_ready_us": _stream_ready_us,
		"chunk_ready_max_us": _stream_ready_max_us,
		"deferred": false,
		"work": "immediate index terrain marker + static features in chunk",
	}


func _on_chunk_ready(coord: Vector2i, _data = null) -> void:
	if layer == null:
		return
	var t0 := Time.get_ticks_usec()
	layer.mark_chunk_loaded(coord)
	# Terrain chunk marker (discovery of loaded terrain extent)
	var cs := float(layer.chunk_size)
	var center := Vector3((float(coord.x) + 0.5) * cs, 0.0, (float(coord.y) + 0.5) * cs)
	# Avoid duplicate terrain markers: remove existing terrain in this chunk first
	_remove_category_in_chunk(coord, _SpatialQueryLayer.CAT_TERRAIN)
	layer.insert(
		_SpatialQueryLayer.CAT_TERRAIN,
		center,
		cs * 0.5,
		{"chunk": coord, "kind": "chunk"},
		false,
		"terrain:%d:%d" % [coord.x, coord.y],
		coord
	)
	_index_static_features_in_chunk(coord)
	var dt := Time.get_ticks_usec() - t0
	_stream_ready_n += 1
	_stream_ready_us += dt
	_stream_ready_max_us = maxi(_stream_ready_max_us, dt)


func _on_chunk_unloaded(coord: Vector2i) -> void:
	if layer == null:
		return
	# Remove statics tied to chunk; dynamics may be despawned by EntityManager separately.
	_remove_static_in_chunk(coord)
	_remove_category_in_chunk(coord, _SpatialQueryLayer.CAT_TERRAIN)
	layer.mark_chunk_unloaded(coord, false)


func _remove_static_in_chunk(coord: Vector2i) -> void:
	if layer == null:
		return
	var hits: Array = layer.iter_chunk_neighborhood(coord, 0, _SpatialQueryLayer.CAT_ALL)
	for h in hits:
		if not bool(h.get("dynamic", true)):
			var cat: int = int(h.get("category", 0))
			if cat == _SpatialQueryLayer.CAT_TERRAIN:
				continue  # handled separately
			layer.remove(int(h.id))


func _remove_category_in_chunk(coord: Vector2i, category: int) -> void:
	if layer == null:
		return
	var hits: Array = layer.iter_chunk_neighborhood(coord, 0, category)
	for h in hits:
		if int(h.category) == category:
			layer.remove(int(h.id))


func _index_static_features_in_chunk(coord: Vector2i) -> void:
	if layer == null:
		return
	var spawns: Array = _FeatureRegistry.get_spawns_in_chunk(coord, layer.chunk_size)
	for spawn in spawns:
		if not spawn is Dictionary:
			continue
		var pos: Vector2i = spawn.get("world_pos", Vector2i.ZERO)
		var kind: int = int(spawn.get("kind", 0))
		var cat := _SpatialQueryLayer.CAT_STRUCTURE
		var key := "feat:%d:%d" % [pos.x, pos.y]
		if kind == _WorldFeatureTypes.FeatureKind.TOWN:
			cat = _SpatialQueryLayer.CAT_TOWN
			key = "town:%d:%d" % [pos.x, pos.y]
		elif kind == _WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN:
			# Spawns are placement data; live entities register separately.
			continue
		var world_pos := Vector3(float(pos.x) + 0.5, 0.0, float(pos.y) + 0.5)
		layer.insert(cat, world_pos, 0.5, spawn, false, key, coord)


func _reindex_crystal_spawns() -> void:
	if layer == null or _crystal_manager == null:
		return
	# Drop existing crystal category statics and re-add active spawns (category iter, not huge radius).
	var existing: Array = layer.iter_category(_SpatialQueryLayer.CAT_CRYSTAL)
	for h in existing:
		if not bool(h.get("dynamic", true)):
			layer.remove(int(h.id))
	if not _crystal_manager.has_method("get_active_spawns"):
		return
	var spawns: Array = _crystal_manager.get_active_spawns()
	for spawn in spawns:
		if spawn == null:
			continue
		var wx := 0
		var wz := 0
		if "world_pos" in spawn:
			var wp = spawn.world_pos
			if wp is Vector2i:
				wx = wp.x
				wz = wp.y
			elif wp is Vector2:
				wx = int(wp.x)
				wz = int(wp.y)
		elif "position" in spawn:
			var p = spawn.position
			if p is Vector2i:
				wx = p.x
				wz = p.y
		var pos := Vector3(float(wx) + 0.5, 0.0, float(wz) + 0.5)
		var key := "crystal_spawn:%d:%d" % [wx, wz]
		layer.insert(_SpatialQueryLayer.CAT_CRYSTAL, pos, 1.0, spawn, false, key)


func _on_entity_spawned(entity: Node3D) -> void:
	_register_node(entity, _SpatialQueryLayer.CAT_ENTITY, true)


func _on_entity_despawned(entity: Node3D) -> void:
	_unregister_node(entity)


## Public registration for crystal enemies, projectiles, etc.
func register_combatant(node: Node3D, category: int = -1) -> int:
	var cat := category
	if cat < 0:
		if node.is_in_group("crystal_enemy"):
			cat = _SpatialQueryLayer.CAT_AI
		else:
			cat = _SpatialQueryLayer.CAT_ENTITY
	return _register_node(node, cat, true)


func unregister_combatant(node: Node3D) -> void:
	_unregister_node(node)


func notify_moved(node: Node3D) -> void:
	if layer == null or node == null or not is_instance_valid(node):
		return
	var iid: int = node.get_instance_id()
	if not _tracked_nodes.has(iid):
		return
	var id: int = int(_tracked_nodes[iid])
	var pos := _node_pos(node)
	var rad := _node_radius(node)
	layer.move(id, pos, rad)


func _register_node(node: Node3D, category: int, dynamic: bool) -> int:
	if layer == null or node == null or not is_instance_valid(node):
		return -1
	var iid: int = node.get_instance_id()
	if _tracked_nodes.has(iid):
		notify_moved(node)
		return int(_tracked_nodes[iid])
	var pos := _node_pos(node)
	var rad := _node_radius(node)
	var key := "node:%d" % iid
	var id: int = layer.insert(category, pos, rad, node, dynamic, key)
	_tracked_nodes[iid] = id
	if node is Node and not node.tree_exiting.is_connected(_on_tracked_tree_exiting):
		node.tree_exiting.connect(_on_tracked_tree_exiting.bind(node), CONNECT_ONE_SHOT)
	return id


func _on_tracked_tree_exiting(node: Node3D) -> void:
	_unregister_node(node)


func _unregister_node(node: Node3D) -> void:
	if node == null:
		return
	var iid: int = node.get_instance_id()
	if not _tracked_nodes.has(iid):
		# Still try payload lookup
		if layer:
			layer.remove_by_payload(node)
		return
	var id: int = int(_tracked_nodes[iid])
	_tracked_nodes.erase(iid)
	if layer:
		layer.remove(id)


func _node_pos(node: Node3D) -> Vector3:
	if node.has_method("get_combat_center") and node.is_inside_tree():
		return node.get_combat_center()
	if node.is_inside_tree() and "global_position" in node:
		return node.global_position
	if "position" in node:
		return node.position
	return Vector3.ZERO


func _node_radius(node: Node3D) -> float:
	if node.has_method("get_combat_radius"):
		return float(node.get_combat_radius())
	return 0.35


## Rebuild after save/load: clear dynamics/statics and re-bind current world.
func rebuild_from_runtime() -> void:
	if layer == null:
		layer = _SpatialQueryLayer.new()
	else:
		layer.clear()
	_tracked_nodes.clear()
	if _chunk_manager and "chunks" in _chunk_manager:
		for coord in _chunk_manager.chunks.keys():
			_on_chunk_ready(coord, null)
	if _entity_manager and "_entities" in _entity_manager:
		for ent in _entity_manager._entities:
			if is_instance_valid(ent):
				_register_node(ent, _SpatialQueryLayer.CAT_ENTITY, true)
	# Crystal enemies in scene
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("crystal_enemy"):
			if node is Node3D:
				_register_node(node as Node3D, _SpatialQueryLayer.CAT_AI, true)
	_reindex_crystal_spawns()


# ── Typed query façades (delegate to layer) ──────────────────────────────


func query_radius(center: Vector3, radius: float, categories: int = _SpatialQueryLayer.CAT_ALL, max_results: int = -1) -> Array:
	return layer.query_radius(center, radius, categories, max_results) if layer else []


func query_aabb(min_pos: Vector3, max_pos: Vector3, categories: int = _SpatialQueryLayer.CAT_ALL, max_results: int = -1) -> Array:
	return layer.query_aabb(min_pos, max_pos, categories, max_results) if layer else []


func query_nearest(center: Vector3, categories: int = _SpatialQueryLayer.CAT_ALL, max_count: int = 1, max_radius: float = INF) -> Array:
	return layer.query_nearest(center, categories, max_count, max_radius) if layer else []


func query_ray(origin: Vector3, direction: Vector3, max_distance: float, categories: int = _SpatialQueryLayer.CAT_ALL, y_tolerance: float = INF, max_results: int = -1) -> Array:
	return layer.query_ray(origin, direction, max_distance, categories, y_tolerance, max_results) if layer else []


func iter_region(min_cell: Vector2i, max_cell: Vector2i, categories: int = _SpatialQueryLayer.CAT_ALL) -> Array:
	return layer.iter_region(min_cell, max_cell, categories) if layer else []


func iter_chunk_neighborhood(center_chunk: Vector2i, ring: int = 1, categories: int = _SpatialQueryLayer.CAT_ALL) -> Array:
	return layer.iter_chunk_neighborhood(center_chunk, ring, categories) if layer else []


## Combat discovery: entities + AI within radius (no gameplay filtering beyond category).
func query_combat_candidates(center: Vector3, radius: float) -> Array:
	var mask: int = _SpatialQueryLayer.CAT_ENTITY | _SpatialQueryLayer.CAT_AI
	return query_radius(center, radius, mask)
