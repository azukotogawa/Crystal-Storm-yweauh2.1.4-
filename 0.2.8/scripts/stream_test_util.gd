extends RefCounted
## Shared helpers for the stream unload / wave-LOD / reversal tests.


static func boot(tree: SceneTree) -> Node:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var game: Node = packed.instantiate()
	tree.root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while compose and not bool(compose.get("_boot_done")) and frames < 3600:
		await tree.process_frame
		frames += 1
	var cm = compose.registry.resolve(&"chunk_manager") if compose and compose.registry else null
	if cm == null:
		cm = tree.get_first_node_in_group("chunk_manager")
	return cm


static func orphan_count(cm: Node) -> int:
	var o = cm.get("_orphan_tasks")
	return (o as Dictionary).size() if o is Dictionary else 0


static func busy(cm: Node) -> bool:
	var rp = cm.get("_rebuild_pending")
	return (
		not cm.pending.is_empty()
		or not cm._chunk_tasks.is_empty()
		or not cm._mesh_completion_queue.is_empty()
		or not cm._stream_load_pending.is_empty()
		or not cm._stream_unload_pending.is_empty()
		or (rp is Dictionary and not (rp as Dictionary).is_empty())
		or orphan_count(cm) > 0
		or ChunkView.pending_buffer_upload_count() > 0
		or bool(cm.get("_rebuild_flush_needed"))
	)


static func settle(tree: SceneTree, cm: Node, max_frames: int = 1800) -> int:
	var f := 0
	var quiet := 0
	while f < max_frames:
		await tree.process_frame
		f += 1
		if busy(cm):
			quiet = 0
		else:
			quiet += 1
			if quiet >= 5:
				return f
	print("SETTLE_TIMEOUT busy=%s" % busy_desc(cm))
	return -1


static func busy_desc(cm: Node) -> String:
	var rp = cm.get("_rebuild_pending")
	return "pending=%s tasks=%s meshq=%d load=%s unload=%s rebuild=%s orphans=%d uploads=%d flush=%s" % [
		str(cm.pending.keys()), str(cm._chunk_tasks.keys()), cm._mesh_completion_queue.size(),
		str(cm._stream_load_pending.keys()) if cm._stream_load_pending is Dictionary else str(cm._stream_load_pending),
		str(cm._stream_unload_pending), str((rp as Dictionary).keys()) if rp is Dictionary else "-",
		orphan_count(cm), ChunkView.pending_buffer_upload_count(), str(cm.get("_rebuild_flush_needed"))]


static func needed_set(cm: Node, c: Vector2i) -> Dictionary:
	var out := {}
	var r: int = int(cm.RENDER_DISTANCE)
	for z in range(c.y - r, c.y + r + 2):
		for x in range(c.x - r, c.x + r + 2):
			var k := Vector2i(x, z)
			if cm._WorldBakeService_is_outside(k):
				continue
			out[k] = true
	if cm.has_method("_start_threat_chunk_coords"):
		for e in cm._start_threat_chunk_coords():
			if not cm._WorldBakeService_is_outside(e):
				out[e] = true
	return out


## Stable signature of what a chunk shows and what queries read from it.
static func chunk_sig(cm: Node, key: Vector2i) -> String:
	if not cm.chunks.has(key):
		return "missing"
	var view = cm.chunks[key]
	if not is_instance_valid(view) or view.chunk_data == null:
		return "invalid"
	var md: Dictionary = view.mesh_data
	var parts: PackedStringArray = []
	var mkeys: Array = md.keys()
	mkeys.sort()
	for k in mkeys:
		if str(k).ends_with("_us") or str(k).ends_with("_ms"):
			continue
		parts.append("%s=%d" % [str(k), _value_hash(md[k])])
	var d = view.chunk_data
	parts.append("ramp=%d" % hash(var_to_bytes(d.ramp_map)))
	parts.append("surf=%d" % hash(var_to_bytes(d.surface_map)))
	return ";".join(parts)


static func snapshot_sigs(cm: Node) -> Dictionary:
	var out := {}
	for k in cm.chunks.keys():
		out[k] = chunk_sig(cm, k)
	return out


## Every chunks entry is a live view parented to cm for that coord, and cm has no
## other ChunkView children (no dangling views).
static func view_problems(cm: Node) -> PackedStringArray:
	var bad: PackedStringArray = []
	var live := {}
	for k in cm.chunks.keys():
		var v = cm.chunks[k]
		if not is_instance_valid(v):
			bad.append("freed view at %s" % str(k))
			continue
		live[v.get_instance_id()] = true
		if v.get_parent() != cm:
			bad.append("view %s not parented to manager" % str(k))
		if v.chunk_data == null:
			bad.append("view %s has no chunk_data" % str(k))
		elif Vector2i(v.chunk_data.position) != k:
			bad.append("view %s holds data for %s" % [str(k), str(v.chunk_data.position)])
		if (v.mesh_data as Dictionary).is_empty():
			bad.append("view %s has no mesh" % str(k))
	for ch in cm.get_children():
		if ch is ChunkView and not live.has(ch.get_instance_id()):
			bad.append("dangling ChunkView %s in tree" % ch.name)
	return bad


## Occupy every pool thread so chunk tasks queue behind these. sleeper is a
## Callable that blocks its thread (for example OS.delay_msec bound by the caller).
static func saturate_pool(sleeper: Callable) -> Array:
	var ids: Array = []
	for _i in OS.get_processor_count() + 2:
		ids.append(WorkerThreadPool.add_task(sleeper, true))
	return ids


static func wait_all(ids: Array) -> void:
	for tid in ids:
		WorkerThreadPool.wait_for_task_completion(tid)


static func shutdown(tree: SceneTree, cm: Node) -> void:
	var compose = tree.root.find_child("CompositionRoot", true, false)
	if compose and compose.has_method("shutdown"):
		compose.shutdown()
	await tree.process_frame
	if is_instance_valid(cm) and cm.has_method("release_all_chunks_for_teardown"):
		cm.release_all_chunks_for_teardown()


static func set_player_chunk(cm: Node, c: Vector2i) -> void:
	var p: Node3D = cm.player
	var s := float(ChunkData.SIZE)
	var pos := p.global_position
	pos.x = (float(c.x) + 0.5) * s
	pos.z = (float(c.y) + 0.5) * s
	p.global_position = pos
	if p is CharacterBody3D:
		(p as CharacterBody3D).velocity = Vector3.ZERO


static func sig_diff(a: String, b: String) -> String:
	var pa := a.split(";")
	var pb := b.split(";")
	var da := {}
	for p in pa:
		da[p.get_slice("=", 0)] = p
	var out: PackedStringArray = []
	for p in pb:
		var k := p.get_slice("=", 0)
		if not da.has(k):
			out.append("+" + k)
		elif da[k] != p:
			out.append("~" + k)
		da.erase(k)
	for k in da.keys():
		out.append("-" + str(k))
	return ",".join(out)


## Hash by content: a Mesh is a fresh object on every build, so hash its surface
## arrays rather than the object reference.
static func _value_hash(v) -> int:
	if v is Mesh:
		var m: Mesh = v
		var acc := PackedStringArray()
		for s in m.get_surface_count():
			acc.append(str(hash(var_to_bytes(m.surface_get_arrays(s)))))
		return hash(",".join(acc))
	if v is Object:
		return 0 if v == null else 1
	return hash(var_to_bytes(v))
