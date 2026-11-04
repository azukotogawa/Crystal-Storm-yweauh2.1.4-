extends SceneTree

## Item 12: far chunk views drop their CPU mesh payload (quads, surface arrays,
## surface cache) after upload. Near views keep it for patch rebuilds. A patch or
## a real dig on a dropped view falls back to a full rebuild and must give the
## same mesh as a fresh full rebuild. Prints MEMTEST lines (payload MB before/after).

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _MemCensus = preload("res://scripts/mem_census.gd")

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	# Stream with every payload kept, then release by hand to measure before/after.
	OS.set_environment("CS_MESH_PAYLOAD_KEEP", "-1")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL: %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _payload_mb(cm) -> float:
	var mc = _MemCensus.new()
	var total := 0
	for k in cm.chunks.keys():
		var v = cm.chunks[k]
		if v != null and is_instance_valid(v):
			total += mc.est(v.mesh_data)
	return total / 1048576.0


static func _view_mesh_hash(view: Node) -> String:
	var lc: Node = view.get_node_or_null("LayerContainer")
	if lc == null:
		return "none"
	var parts: PackedStringArray = []
	for c in lc.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is ArrayMesh:
			var am := (c as MeshInstance3D).mesh as ArrayMesh
			for s in am.get_surface_count():
				var arr: Array = am.surface_get_arrays(s)
				parts.append("%s:%d:%d:%d" % [c.name, s, hash(var_to_bytes(arr[Mesh.ARRAY_VERTEX])), hash(var_to_bytes(arr[Mesh.ARRAY_INDEX]))])
		elif c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh != null:
			var mm := (c as MultiMeshInstance3D).multimesh
			parts.append("%s:%d:%d" % [c.name, mm.instance_count, hash(var_to_bytes(mm.buffer))])
	parts.sort()
	return "|".join(parts)


func _settle(cm, max_frames: int) -> void:
	for _i in 3:
		await process_frame
	for _i in max_frames:
		if not cm.mesh_pipeline_busy():
			break
		await process_frame
	for _i in 3:
		await process_frame


func _dig_in(editor, world, coord: Vector2i) -> Vector2i:
	for off in [Vector2i(10, 10), Vector2i(12, 9), Vector2i(8, 13), Vector2i(14, 14), Vector2i(6, 6)]:
		var wx: int = coord.x * ChunkData.SIZE + off.x
		var wz: int = coord.y * ChunkData.SIZE + off.y
		var y: float = world.get_surface_height(float(wx), float(wz))
		if editor.try_dig(Vector3(float(wx) + 0.5, y, float(wz) + 0.5)):
			return Vector2i(wx, wz)
	return Vector2i(-999999, -999999)


## Dig in coord, let the edit rebuild finish, then compare with a forced full rebuild.
func _dig_matches_full(cm, editor, world, coord: Vector2i, label: String) -> void:
	var h_pre := _view_mesh_hash(cm.chunks[coord])
	var cell := _dig_in(editor, world, coord)
	if cell.x == -999999:
		_fail("%s: dig refused in %s (%s)" % [label, str(coord), str(editor.last_fail_reason)])
		return
	for _f in 600:
		await process_frame
		var cv = cm.chunks.get(coord, null)
		if cv != null and _view_mesh_hash(cv) != h_pre and not cm.mesh_pipeline_busy():
			break
	await _settle(cm, 900)
	var v = cm.chunks.get(coord, null)
	if v == null:
		_fail("%s: chunk %s gone after dig" % [label, str(coord)])
		return
	var h_edit := _view_mesh_hash(v)
	var keep: int = cm.mesh_payload_keep_radius
	cm.mesh_payload_keep_radius = -1
	cm._regenerate_chunk_mesh(coord, true)
	await _settle(cm, 900)
	cm.mesh_payload_keep_radius = keep
	var h_full := _view_mesh_hash(cm.chunks[coord])
	if h_edit == h_pre:
		_fail("%s: dig at %s did not change the mesh" % [label, str(cell)])
	elif h_edit != h_full:
		var a := h_edit.split("|")
		var b := h_full.split("|")
		var diff: PackedStringArray = []
		for p in a:
			if not b.has(p):
				diff.append(p.get_slice(":", 0))
		_fail("%s: dig at %s mesh differs from full rebuild (parts %s)" % [label, str(cell), ",".join(diff)])
	else:
		_ok("%s: dig at %s mesh == full rebuild" % [label, str(cell)])


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while compose and not bool(compose.get("_boot_done")) and frames < 3600:
		await process_frame
		frames += 1
	var cm = compose.registry.resolve(&"chunk_manager") if compose and compose.registry else null
	if cm == null:
		cm = get_first_node_in_group("chunk_manager")
	var editor = get_first_node_in_group("terrain_editor")
	var world = cm.world if cm else null
	if cm == null or editor == null or world == null:
		_fail("chunk_manager/terrain_editor/world missing")
		_ProbeExit.finish_tree(self, 1, "mesh payload release FAILED")
		return
	for _w in 600:
		if cm.chunks.size() >= 16:
			break
		await process_frame
	await _settle(cm, 600)
	var center: Vector2i = cm.get_player_chunk_coord()
	_ok("streamed chunks=%d center=%s" % [cm.chunks.size(), str(center)])

	if not ("mesh_payload_keep_radius" in cm) or not cm.has_method("release_far_mesh_payloads"):
		print("MEMTEST payload_mb=%.2f views=%d (no release API)" % [_payload_mb(cm), cm.chunks.size()])
		_fail("ChunkManager has no mesh_payload_keep_radius / release_far_mesh_payloads")
		_ProbeExit.finish_tree(self, 1, "mesh payload release FAILED (%d)" % _failed)
		return

	cm.mesh_payload_keep_radius = -1
	var before_hash := {}
	for k in cm.chunks.keys():
		before_hash[k] = _view_mesh_hash(cm.chunks[k])
	var keep_r := 1
	cm.mesh_payload_keep_radius = keep_r
	var mb0 := _payload_mb(cm)
	# Per-frame cap: at most N releases per frame, farthest (closest to unload) first.
	var released := 0
	if not ("mesh_payload_release_per_frame" in cm):
		_fail("ChunkManager has no mesh_payload_release_per_frame cap")
	else:
		var far_n := 0
		var max_cheb := 0
		for k in cm.chunks.keys():
			var ch: int = maxi(absi(k.x - center.x), absi(k.y - center.y))
			if ch > keep_r and not bool(cm.chunks[k].mesh_data.get("cpu_payload_released", false)):
				far_n += 1
				max_cheb = maxi(max_cheb, ch)
		cm.mesh_payload_release_per_frame = 2
		var got: Array = []
		var n1: int = cm.release_far_mesh_payloads(center)
		for k in cm.chunks.keys():
			if bool(cm.chunks[k].mesh_data.get("cpu_payload_released", false)):
				got.append(k)
		var n2: int = cm.release_far_mesh_payloads(center)
		print("MEMTEST cap=2 far=%d first_call=%d same_frame_second=%d" % [far_n, n1, n2])
		var far_first := true
		for k in got:
			if maxi(absi(k.x - center.x), absi(k.y - center.y)) != max_cheb:
				far_first = false
		if n1 != mini(2, far_n) or n2 != 0:
			_fail("cap not honored: first=%d second=%d far=%d" % [n1, n2, far_n])
		elif not far_first:
			_fail("cap released a nearer chunk before the farthest ring %s" % str(got))
		else:
			_ok("cap 2/frame honored, farthest first (%d of %d)" % [n1, far_n])
		await process_frame
		var drained := n1
		var cap_frames := 0
		while cap_frames < 60:
			var k2: int = cm.release_far_mesh_payloads(center)
			if k2 > 2:
				_fail("frame released %d > cap" % k2)
			drained += k2
			if k2 == 0:
				break
			cap_frames += 1
			await process_frame
		released = drained
		_ok("drained %d releases over %d frames" % [drained, cap_frames + 1])
	var mb1 := _payload_mb(cm)
	print("MEMTEST payload_mb before=%.2f after=%.2f saved=%.2f views=%d released=%d keep_radius=%d" % [mb0, mb1, mb0 - mb1, cm.chunks.size(), released, keep_r])

	var far_list: Array = []
	var near_list: Array = []
	var bad_near := 0
	var bad_far := 0
	for k in cm.chunks.keys():
		var v = cm.chunks[k]
		var cheb: int = maxi(absi(k.x - center.x), absi(k.y - center.y))
		var md: Dictionary = v.mesh_data
		var rel := bool(md.get("cpu_payload_released", false))
		if cheb <= keep_r:
			if rel or (int(md.get("count", 0)) > 0 and (md.get("quads", []) as Array).is_empty()):
				bad_near += 1
			elif int(md.get("count", 0)) > 0 and k != center:
				near_list.append(k)
		else:
			if not rel or not (md.get("quads", []) as Array).is_empty() or md.has("surface_vertices") or md.has("surface_cache"):
				bad_far += 1
			elif int(md.get("count", 0)) > 0:
				far_list.append(k)
		if _view_mesh_hash(v) != before_hash[k]:
			_fail("release changed uploaded mesh for %s" % str(k))
	if bad_near > 0:
		_fail("near views lost payload: %d" % bad_near)
	else:
		_ok("near views keep payload (radius %d)" % keep_r)
	if bad_far > 0:
		_fail("far views kept payload: %d" % bad_far)
	elif released <= 0:
		_fail("nothing released")
	else:
		_ok("far views released=%d, uploaded meshes unchanged" % released)
	if mb1 >= mb0:
		_fail("payload did not shrink (%.2f -> %.2f)" % [mb0, mb1])
	else:
		_ok("payload shrank %.2f -> %.2f MB" % [mb0, mb1])

	if far_list.size() < 2:
		_fail("need 2 released non-empty far chunks, have %d" % far_list.size())
	else:
		var a: Vector2i = far_list[0]
		var reason: String = cm.column_mesh_block_reason(a.x * ChunkData.SIZE + 3, a.y * ChunkData.SIZE + 3)
		if reason != "":
			_fail("released chunk reports block reason %s" % reason)
		else:
			_ok("released chunk counts as meshed")
		# No-op patch on a dropped view -> full rebuild, same mesh as before.
		cm._enqueue_chunk_mesh_work(a, false, [Vector2i(3, 3), Vector2i(4, 3)], true, false)
		await _settle(cm, 900)
		var v2 = cm.chunks.get(a, null)
		if v2 == null:
			_fail("released chunk vanished after patch")
		else:
			if _view_mesh_hash(v2) != before_hash[a]:
				_fail("patch on released chunk changed mesh %s" % str(a))
			else:
				_ok("patch on released chunk -> same mesh %s" % str(a))
			if not bool(v2.mesh_data.get("cpu_payload_released", false)):
				_fail("rebuilt far chunk was not released again")
			else:
				_ok("rebuilt far chunk released again")
		# Real edit after drop.
		await _dig_matches_full(cm, editor, world, far_list[1], "edit_after_drop")
	# Control: same comparison on a near chunk that keeps its payload (patch path).
	if near_list.is_empty():
		_fail("no near chunk for control")
	else:
		await _dig_matches_full(cm, editor, world, near_list[0], "control_near_patch")

	cm.mesh_payload_keep_radius = -1
	var n_off: int = cm.release_far_mesh_payloads(center)
	if n_off != 0:
		_fail("radius -1 still released %d" % n_off)
	else:
		_ok("radius -1 disables release")

	if compose and compose.has_method("shutdown"):
		compose.shutdown()
	await process_frame
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All mesh payload release tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "mesh payload release FAILED (%d)" % _failed)
