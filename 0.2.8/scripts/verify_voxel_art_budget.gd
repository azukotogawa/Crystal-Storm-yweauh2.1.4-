extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _Look = preload("res://helpers/terrain_look.gd")
const _Veg = preload("res://helpers/vegetation_voxel_catalog.gd")
const _Loader = preload("res://helpers/crystal_voxel_loader.gd")
const _Objects = preload("res://helpers/object_voxel_catalog.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")

const _TREE := "res://assets/voxel/vegetation/lod/tree_oak_v0_s2_lod0.json"
const _TREE_FAR := "res://assets/voxel/vegetation/lod/tree_oak_v0_s2_lod1.json"
const _PLANT := "res://assets/voxel/vegetation/lod/bush_v0_s2.json"


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var phase := OS.get_environment("CRYSTALSTORM_ART_BUDGET_PHASE").strip_edges()
	if phase.is_empty():
		phase = "measure"
	_print_model_budgets()
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_ProbeExit.finish_tree(self, 1, "VOXEL ART BUDGET FAIL")
		return
	var game := packed.instantiate()
	root.add_child(game)
	var crystal = null
	var chunks = null
	var player: Node = null
	for _i in 900:
		crystal = get_first_node_in_group("crystal_manager")
		chunks = get_first_node_in_group("chunk_manager")
		player = get_first_node_in_group("player")
		if crystal != null and chunks != null and player != null and crystal._initialized and bool(player.get("world_ready")):
			break
		await process_frame
	if crystal == null or chunks == null:
		_ProbeExit.finish_tree(self, 1, "VOXEL ART BUDGET FAIL")
		return
	for _w in 120:
		await process_frame
	var busy := await _sample("busy", crystal)
	var filled := _fill_tenth(crystal, chunks)
	crystal.expansion_enabled = false
	for _s in 90:
		await process_frame
	var tenth := await _sample("crystal10", crystal)
	print("ART_BUDGET phase=%s flags amplitude=%d lod0=%d edge=%s" % [
		phase, _Look.amplitude_steps(), _Veg.LOD0_COLUMNS, str(_Veg.EDGE_DETAIL),
	])
	print("ART_BUDGET filled_cells=%d sim_after_fill=%d" % [filled, _sim_cells(crystal)])
	print("ART_BUDGET busy frame_ms=%.3f fps=%.1f draw=%d prim=%d sprites=%d boxes=%d meshes=%d multimesh=%d quads=%d coverage=%.6f cells=%d sim=%d" % [
		busy.frame_ms, busy.fps, busy.draw, busy.prim, busy.sprites, busy.boxes, busy.meshes, busy.multimesh, busy.quads, busy.coverage, busy.cells, busy.sim,
	])
	print("ART_BUDGET crystal10 frame_ms=%.3f fps=%.1f draw=%d prim=%d sprites=%d boxes=%d meshes=%d multimesh=%d quads=%d coverage=%.6f cells=%d sim=%d" % [
		tenth.frame_ms, tenth.fps, tenth.draw, tenth.prim, tenth.sprites, tenth.boxes, tenth.meshes, tenth.multimesh, tenth.quads, tenth.coverage, tenth.cells, tenth.sim,
	])
	var over: bool = float(busy.frame_ms) > 16.6 or float(tenth.frame_ms) > 16.6
	print("ART_BUDGET hold60=%s" % str(not over))
	_ProbeExit.finish_tree(self, 0, "VOXEL ART BUDGET OK")


func _print_model_budgets() -> void:
	var oak := _Loader.quad_count(_Loader.mesh_for(_TREE))
	var far := _Loader.quad_count(_Loader.mesh_for(_TREE_FAR))
	var bush := _Loader.quad_count(_Loader.mesh_for(_PLANT))
	print("ART_BUDGET model oak_lod0=%d oak_lod1=%d bush=%d" % [oak, far, bush])
	var worst_obj := 0
	var obj_draws := 0
	for name in _Objects.MODELS:
		var rig: Dictionary = _Loader.rig_for(_Objects.path_for(name))
		var q := int(rig.get("quads", 0))
		worst_obj = maxi(worst_obj, q)
		var parts: Dictionary = rig.get("parts", {})
		var draws := 0
		if _Objects._PARTS.has(name):
			draws = (_Objects._PARTS[name] as Array).size()
		elif rig.get("mesh", null) != null:
			draws = 1
		obj_draws = maxi(obj_draws, draws)
		print("ART_BUDGET object %s quads=%d draws=%d" % [name, q, draws])
	print("ART_BUDGET object_worst_quads=%d object_worst_draws=%d" % [worst_obj, obj_draws])


func _fill_tenth(crystal, chunks) -> int:
	var cells: Array[Vector2i] = []
	for key in chunks.chunks.keys():
		var coord: Vector2i = key
		var x0: int = coord.x * _ChunkData.SIZE
		var z0: int = coord.y * _ChunkData.SIZE
		for lx in _ChunkData.SIZE:
			for lz in _ChunkData.SIZE:
				cells.append(Vector2i(x0 + lx, z0 + lz))
	if cells.is_empty():
		return 0
	var want := maxi(int(cells.size() / 10), 1)
	if not crystal.has_method("_set_depth"):
		return 0
	var placed := 0
	var step := maxi(int(cells.size() / want), 1)
	var i := 0
	while placed < want and i < cells.size():
		crystal._set_depth(cells[i], 1.0, -1)
		placed += 1
		i += step
	return placed


func _sample(label: String, crystal) -> Dictionary:
	var ms := 0.0
	var n := 48
	for _i in n:
		var t := Time.get_ticks_usec()
		await process_frame
		ms += float(Time.get_ticks_usec() - t) / 1000.0
	var counts := _count_scene()
	var frame_ms := ms / float(n)
	var fps := 1000.0 / maxf(frame_ms, 0.001)
	var draw := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if draw <= 0:
		draw = counts.meshes + counts.multimesh + counts.sprites
	var prim := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if prim <= 0:
		prim = counts.quads * 2
	counts["frame_ms"] = frame_ms
	counts["fps"] = fps
	counts["draw"] = draw
	counts["prim"] = prim
	if crystal.has_method("_recalc_stats"):
		crystal._recalc_stats()
	counts["coverage"] = crystal.get_coverage_ratio()
	counts["cells"] = crystal.covered_cells
	counts["sim"] = _sim_cells(crystal)
	counts["label"] = label
	return counts


func _sim_cells(crystal) -> int:
	var sim = crystal.get("_sim")
	if sim != null and sim.has_method("cell_count"):
		return int(sim.cell_count())
	return -1


func _count_scene() -> Dictionary:
	var sprites := 0
	var boxes := 0
	var meshes := 0
	var multimesh := 0
	var quads := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is Sprite3D and (node as Sprite3D).visible:
			sprites += 1
			quads += 1
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).visible:
			multimesh += 1
			var mm := (node as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null:
				var per := _mesh_quads(mm.mesh)
				quads += per * mm.visible_instance_count
		elif node is MeshInstance3D and (node as MeshInstance3D).visible:
			meshes += 1
			var mesh := (node as MeshInstance3D).mesh
			if mesh is BoxMesh:
				boxes += 1
				quads += 6
			else:
				quads += _mesh_quads(mesh)
	return {
		"sprites": sprites,
		"boxes": boxes,
		"meshes": meshes,
		"multimesh": multimesh,
		"quads": quads,
	}


func _mesh_quads(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	if mesh is BoxMesh or mesh is QuadMesh:
		return 6 if mesh is BoxMesh else 1
	if mesh is CapsuleMesh:
		return 16
	var total := 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var idx = arrays[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
			total += (idx as PackedInt32Array).size() / 6
		else:
			var verts = arrays[Mesh.ARRAY_VERTEX]
			if verts is PackedVector3Array:
				total += (verts as PackedVector3Array).size() / 6
	return total
