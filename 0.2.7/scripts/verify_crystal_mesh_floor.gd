extends SceneTree
## Prove crystal presentation uses updated floor after dig (MultiMesh path).
## Asserts _make_render_cell.terrain_y (feeds MultiMesh) and MultiMesh instance Y when available.


const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _CrystalManager = preload("res://crystal/crystal_manager.gd")
const _CrystalCell = preload("res://crystal/crystal_cell.gd")
const _CrystalChunkLayer = preload("res://crystal/crystal_chunk_layer.gd")


var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	_TerrainEdits.reset()

	var root3d := Node3D.new()
	root.add_child(root3d)

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 5
	world.add_to_group("world")
	root3d.add_child(world)

	var cm := _ChunkManager.new()
	cm.add_to_group("chunk_manager")
	cm.set_process(false)
	root3d.add_child(cm)
	var view := ChunkView.new()
	view.chunk_data = ChunkData.new(Vector2i(0, 0), world)
	cm.chunks[Vector2i(0, 0)] = view

	var editor := _TerrainEditor.new()
	editor.add_to_group("terrain_editor")
	root3d.add_child(editor)
	editor.world = world
	editor.bind_chunk_manager(cm)

	var crystal: CrystalManager = _CrystalManager.new()
	crystal.name = "CrystalManager"
	root3d.add_child(crystal)
	crystal.world = world
	crystal.chunk_manager = cm
	await process_frame
	if crystal.has_method("ensure_ready"):
		await crystal.ensure_ready()
	for _i in 15:
		await process_frame
		if crystal._presentation != null and crystal._sim != null and crystal._presentation.layer_root != null:
			break

	if crystal._presentation == null or crystal._sim == null:
		_fail("crystal presentation/sim not ready")
		quit(1)
		return

	# Ensure presentation has layer root + floor callback (production wiring).
	if crystal._presentation.layer_root == null and crystal._layer_root != null:
		crystal._presentation.layer_root = crystal._layer_root
	if crystal._presentation.crystal_floor_at.is_null():
		crystal._presentation.crystal_floor_at = Callable(crystal, "_crystal_floor_at")
	if crystal._presentation.fluid == null:
		crystal._presentation.fluid = crystal._sim

	var pos := Vector2i(3, 3)
	var layer_h: float = _WorldSettings.get_active().layer_height()
	var depth: float = maxf(0.6, layer_h * 0.35)
	crystal._sim.depth[pos] = depth
	crystal._presentation.rebuild_cell_index()

	# Presentation render cell is the exact input to MultiMesh transforms.
	var cell0: _CrystalCell = crystal._presentation._make_render_cell(pos, depth, -1)
	var ty0: float = cell0.terrain_y
	print("render_cell terrain_y before dig=%.3f floor=%.3f" % [ty0, crystal._crystal_floor_at(pos)])

	# Build MultiMesh explicitly from that cell
	var coord := Vector2i(
		floori(float(pos.x) / float(ChunkData.SIZE)),
		floori(float(pos.y) / float(ChunkData.SIZE))
	)
	var layer: _CrystalChunkLayer = crystal._presentation._chunk_layers.get(coord)
	if layer == null:
		layer = _CrystalChunkLayer.new()
		layer.name = "CrystalChunk_%d_%d" % [coord.x, coord.y]
		if crystal._presentation.layer_root:
			crystal._presentation.layer_root.add_child(layer)
		else:
			crystal.add_child(layer)
		layer.setup(coord, crystal._crystal_material)
		crystal._presentation._chunk_layers[coord] = layer
	layer.rebuild([cell0], 3)
	await process_frame
	var applied0: float = layer.get_applied_terrain_y(pos)
	print("applied_terrain_y before dig=%.3f has_cell=%s" % [applied0, layer.has_cell(pos)])

	if not editor.try_dig(Vector3(float(pos.x) + 0.5, 0, float(pos.y) + 0.5)):
		_fail("dig failed: %s" % editor.last_fail_reason)
	# Production handler (marks dirty + full rebuild request)
	crystal._on_player_terrain_edited(pos.x, pos.y, &"dig")

	var cell1: _CrystalCell = crystal._presentation._make_render_cell(pos, depth, -1)
	var ty1: float = cell1.terrain_y
	print("render_cell terrain_y after dig=%.3f floor=%.3f" % [ty1, crystal._crystal_floor_at(pos)])

	if ty1 >= ty0 - 0.05:
		_fail("presentation render-cell terrain_y did not drop (%.3f→%.3f)" % [ty0, ty1])
	else:
		print("OK presentation render-cell terrain_y dropped %.3f→%.3f" % [ty0, ty1])

	# Rebuild MultiMesh with updated cell (same path as chunk rebuild after dirty)
	layer.rebuild([cell1], 3)
	await process_frame
	var applied1: float = layer.get_applied_terrain_y(pos)
	print("applied_terrain_y after dig=%.3f has_cell=%s" % [applied1, layer.has_cell(pos)])

	if not layer.has_cell(pos):
		_fail("MultiMesh layer missing cell after rebuild")
	elif applied1 < -9000.0 or applied0 < -9000.0:
		_fail("applied terrain_y not recorded on MultiMesh path")
	elif applied1 >= applied0 - 0.05:
		_fail("MultiMesh path applied_terrain_y did not drop (%.3f→%.3f)" % [applied0, applied1])
	else:
		print("OK MultiMesh path applied_terrain_y dropped %.3f→%.3f" % [applied0, applied1])

	if _failed == 0:
		print("All crystal mesh floor tests OK")
		quit(0)
	else:
		push_error("verify_crystal_mesh_floor: %d failure(s)" % _failed)
		quit(1)
