extends SceneTree

const _Probe = preload("res://helpers/probe_capture.gd")
const _Builder = preload("res://helpers/chunk_surface_mesh_builder.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _Types = preload("res://helpers/voxel_types.gd")
const _Quality = preload("res://config/performance_quality_config.gd")
const _Light = preload("res://helpers/scene_lighting.gd")
const _Terrain = preload("res://helpers/terrain_lighting.gd")
const _Mat = preload("res://shaders/ChunkSurfaceMesh.tres")
const _Settings = preload("res://config/world_settings.gd")
const _Border = preload("res://helpers/world_border.gd")
const _Pois = preload("res://world/poi_scatter.gd")
const _Props = preload("res://helpers/voxel_prop_builder.gd")
const _Coords = preload("res://helpers/world_visual_coords.gd")
const _Dress = preload("res://world/route_dressing.gd")
const _Variety = preload("res://config/route_variety_config.gd")

const _SEED := 12349
const _ALONG := 36
const _ACROSS := 18

var _cam: Camera3D
var _host: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("cs-art-08 shot needs a window")
		quit(1)
		return
	var phase := OS.get_environment("CRYSTALSTORM_ART_PHASE").strip_edges()
	if phase.is_empty():
		phase = "before"
	if phase == "before":
		var off := _Variety.new()
		off.enabled = false
		_Dress.set_config(off)
	else:
		_Dress.set_config(null)
	DisplayServer.window_set_title("Crystal Storm cs-art-08")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_Terrain.apply_preset(int(_Quality.Preset.MEDIUM))
	RenderingServer.global_shader_parameter_set("cutaway_enabled", 0.0)
	_stage()
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.apply_seed(_SEED)
	var focus := _paint(world)
	_dress_props(world)
	await _aim(focus)
	await _Probe.capture_step("cs-art-08-%s-long-walk" % phase)
	print("CS ART 08 SHOTS %s" % phase)
	quit(0)


func _stage() -> void:
	_host = Node3D.new()
	_host.name = "Game"
	root.add_child(_host)
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.72, 0.84)
	world_env.environment = env
	_host.add_child(world_env)
	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.light_color = Color(0.72, 0.78, 0.9, 1)
	light.light_energy = 0.58
	var locked := Basis(
		Vector3(0.568432, 0.0, -0.82273),
		Vector3(-0.637673, 0.631876, -0.440574),
		Vector3(0.519864, 0.775069, 0.359179)
	)
	light.transform = Transform3D(locked, Vector3.ZERO)
	_host.add_child(light)
	_Light.apply_host(_host, _Quality.apply_preset(_Quality.Preset.MEDIUM))
	_cam = Camera3D.new()
	_cam.name = "ShotCam"
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 22.0
	_cam.far = 520.0
	_cam.current = true
	root.add_child(_cam)


func _paint(world) -> Vector3:
	var walk := _walk_line()
	var origin: Vector2 = walk["origin"]
	var dir: Vector2 = walk["dir"]
	var side := Vector2(-dir.y, dir.x)
	var heights := {}
	var tiles := {}
	var min_c := Vector2i(999999, 999999)
	var max_c := Vector2i(-999999, -999999)
	for along in _ALONG:
		for across in _ACROSS:
			var at: Vector2 = origin + dir * float(along) + side * float(across - _ACROSS / 2)
			var cell := Vector2i(int(round(at.x)), int(round(at.y)))
			if heights.has(cell):
				continue
			var h := float(world.get_surface_height(float(cell.x), float(cell.y)))
			var tile := int(world.get_tile_type(float(cell.x), float(cell.y)))
			heights[cell] = h
			tiles[cell] = tile
			min_c.x = mini(min_c.x, cell.x)
			min_c.y = mini(min_c.y, cell.y)
			max_c.x = maxi(max_c.x, cell.x)
			max_c.y = maxi(max_c.y, cell.y)
	var layer := float(_Settings.get_active().layer_height())
	var scale := float(_Settings.get_active().voxel_scale)
	var chunk_x0 := int(floor(float(min_c.x) / float(_ChunkData.SIZE)))
	var chunk_z0 := int(floor(float(min_c.y) / float(_ChunkData.SIZE)))
	var chunk_x1 := int(floor(float(max_c.x) / float(_ChunkData.SIZE)))
	var chunk_z1 := int(floor(float(max_c.y) / float(_ChunkData.SIZE)))
	for cz in range(chunk_z0, chunk_z1 + 1):
		for cx in range(chunk_x0, chunk_x1 + 1):
			_mesh_chunk(world, cx, cz, heights, tiles, layer, scale)
	var mid: Vector2 = origin + dir * float(_ALONG) * 0.45
	var mid_cell := Vector2i(int(round(mid.x)), int(round(mid.y)))
	var mid_h := float(heights.get(mid_cell, 0.0))
	return _Coords.column_to_world_pos(float(mid_cell.x) + 0.5, mid_h + layer, float(mid_cell.y) + 0.5)


func _mesh_chunk(world, cx: int, cz: int, heights: Dictionary, tiles: Dictionary, layer: float, scale: float) -> void:
	var data = _ChunkData.new(Vector2i(cx, cz))
	var quads: Array = []
	var base_x := cx * _ChunkData.SIZE
	var base_z := cz * _ChunkData.SIZE
	var any := false
	for lz in _ChunkData.SIZE:
		for lx in _ChunkData.SIZE:
			var cell := Vector2i(base_x + lx, base_z + lz)
			if heights.has(cell):
				any = true
				break
		if any:
			break
	if not any:
		return
	for lz in _ChunkData.SIZE:
		for lx in _ChunkData.SIZE:
			var cell := Vector2i(base_x + lx, base_z + lz)
			var h := float(heights.get(cell, 0.0))
			var tile := int(tiles.get(cell, _Types.GRASSLAND))
			if not heights.has(cell):
				h = float(world.get_surface_height(float(cell.x), float(cell.y)))
				tile = int(world.get_tile_type(float(cell.x), float(cell.y)))
				heights[cell] = h
				tiles[cell] = tile
			data.patch_local_column(lx, lz, h, tile)
			quads.append(_quad(lx, lz, h, 0, 1.0, tile))
			_side(world, quads, heights, cell, Vector2i(-1, 0), lx, lz, h, tile, layer, scale, 3)
			_side(world, quads, heights, cell, Vector2i(1, 0), lx, lz, h, tile, layer, scale, 4)
			_side(world, quads, heights, cell, Vector2i(0, -1), lx, lz, h, tile, layer, scale, 5)
			_side(world, quads, heights, cell, Vector2i(0, 1), lx, lz, h, tile, layer, scale, 6)
	if quads.is_empty():
		return
	var built: Dictionary = _Builder.build_surface_arrays_from_terrain_quads(data, quads)
	var mesh := _Builder.build_array_mesh(built)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Terrain_%d_%d" % [cx, cz]
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := _Mat.duplicate() as ShaderMaterial
	mat.set_shader_parameter("texture_atlas", load("res://assets/tiles/Cube.png"))
	mat.set_shader_parameter("atlas_grid", Vector2(7, 10))
	mi.material_override = mat
	_host.add_child(mi)


func _side(
	world,
	quads: Array,
	heights: Dictionary,
	cell: Vector2i,
	step: Vector2i,
	lx: int,
	lz: int,
	h: float,
	tile: int,
	layer: float,
	scale: float,
	face: int
) -> void:
	var other := cell + step
	if not heights.has(other):
		var sampled := float(world.get_surface_height(float(other.x), float(other.y)))
		heights[other] = sampled
	var low := float(heights[other])
	if h <= low + 0.01:
		return
	var dim := (h - low) / maxf(scale, 0.001)
	quads.append(_quad(lx, lz, low + layer, face, dim, tile))


func _quad(x: int, z: int, y: float, face: int, dim_y: float, tile: int) -> Dictionary:
	return {
		"x": x,
		"z": z,
		"y": y,
		"dim_x": 1.0,
		"dim_y": dim_y,
		"dim_z": 1.0,
		"face_code": face,
		"type": tile if tile >= 0 else _Types.GRASSLAND,
	}


func _dress_props(world) -> void:
	if not _Dress.config().enabled:
		return
	var walk := _walk_line()
	var origin: Vector2 = walk["origin"]
	var dir: Vector2 = walk["dir"]
	var side := Vector2(-dir.y, dir.x)
	var seen := {}
	var placed := {}
	var low := INF
	var high := -INF
	for along in _ALONG:
		for across in _ACROSS:
			var at: Vector2 = origin + dir * float(along) + side * float(across - _ACROSS / 2)
			var h := float(world.get_surface_height(at.x, at.y))
			low = minf(low, h)
			high = maxf(high, h)
			var key := Vector2i(int(floor(at.x / 16.0)), int(floor(at.y / 16.0)))
			if seen.has(key):
				continue
			seen[key] = true
			for spot_v in _Dress.props_for_chunk(int(world.world_seed), key.x, key.y):
				var spot: Dictionary = spot_v
				var cell: Vector2i = spot.get("cell", Vector2i.ZERO)
				if placed.has(cell):
					continue
				var rel := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5) - origin
				var along_d := rel.dot(dir)
				var across_d := rel.dot(side)
				if along_d < -1.0 or along_d > float(_ALONG) + 1.0:
					continue
				if absf(across_d) > float(_ACROSS) * 0.5 + 1.0:
					continue
				placed[cell] = true
				var top := float(world.get_surface_height(float(cell.x), float(cell.y)))
				var layer := float(_Settings.get_active().layer_height())
				var prop := _Props.build_scatter_prop(str(spot.get("kind", "rock")))
				prop.position = _Coords.column_to_world_pos(float(cell.x) + 0.5, top + layer, float(cell.y) + 0.5)
				prop.rotation.y = deg_to_rad(float(int(spot.get("yaw", 0))))
				_host.add_child(prop)
	print("CS ART 08 SPAN height %.1f..%.1f props %d" % [low, high, placed.size()])


func _walk_line() -> Dictionary:
	var corner := Vector2(_Border.origin_corner_for_seed(_SEED))
	var best := corner
	var best_d := INF
	for spot_v in _Pois.scatter(_SEED):
		var spot: Dictionary = spot_v
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		var dist := corner.distance_to(Vector2(center))
		if dist < best_d:
			best_d = dist
			best = Vector2(center)
	var delta := best - corner
	if delta.length() < 1.0:
		delta = Vector2(-1, 1)
	var dir := delta.normalized()
	return {"origin": corner + dir * 140.0, "dir": dir, "goal": best}


func _aim(focus: Vector3) -> void:
	var yaw := deg_to_rad(45.0)
	var hdist := 100.0 * sqrt(2.0)
	var lift := 101.0
	_cam.position = focus + Vector3(sin(yaw) * hdist, lift, cos(yaw) * hdist)
	_cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	for _i in 24:
		await process_frame
