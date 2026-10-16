class_name DistantLandmarks
extends RefCounted

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
const _Voxels = preload("res://helpers/voxel_types.gd")
const _GroundLook = preload("res://config/crystal_ground_look.gd")

static var _atlas_tex: Texture2D

static var ENABLED: bool = true

const MIN_SPACING := 48
const STRIDE := 4
const KEEP_MOD := 2
const ORIGIN_CLEAR := 56.0
const REGION_MIN := Vector2i(-16, -16)
const REGION_MAX := Vector2i(15, 15)
const READ_VIEW := 16.0
const MIN_HEIGHT := 8.0

const KINDS: Array[String] = ["rock_spire", "ruined_tower", "crystal_glow"]


static func scatter(seed_value: int, chunk_min: Vector2i = REGION_MIN, chunk_max: Vector2i = REGION_MAX) -> Array[Dictionary]:
	return _accept(proposals(seed_value, chunk_min, chunk_max))


static func proposals(seed_value: int, chunk_min: Vector2i = REGION_MIN, chunk_max: Vector2i = REGION_MAX) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var size := ChunkData.SIZE
	for cz in range(chunk_min.y, chunk_max.y + 1):
		for cx in range(chunk_min.x, chunk_max.x + 1):
			if posmod(cx, STRIDE) != 0 or posmod(cz, STRIDE) != 0:
				continue
			var roll := _mix(seed_value, cx, cz, 1)
			if posmod(roll, KEEP_MOD) != 0:
				continue
			var center := Vector2i(
				cx * size + 5 + posmod(_mix(seed_value, cx, cz, 2), 6),
				cz * size + 5 + posmod(_mix(seed_value, cx, cz, 3), 6)
			)
			if Vector2(center).length() < ORIGIN_CLEAR:
				continue
			if not _WorldBorder.is_playable(float(center.x), float(center.y)):
				continue
			var kind := KINDS[posmod(_mix(seed_value, cx, cz, 4), KINDS.size())]
			out.append({
				"center": center,
				"chunk": Vector2i(cx, cz),
				"poi_kind": kind,
				"landmark": true,
			})
	return out


static func place(world) -> int:
	if not ENABLED or world == null:
		return 0
	var open: Array[Dictionary] = []
	for spot in scatter(int(world.world_seed)):
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		if _site_open(world, center):
			open.append(spot)
	return install(open)


static func install(spots: Array) -> int:
	var placed := 0
	for spot_v in spots:
		var spot: Dictionary = spot_v
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		if not _FeatureRegistry.get_feature(center.x, center.y).is_empty():
			continue
		var kind := str(spot.get("poi_kind", ""))
		_FeatureRegistry.register_feature(center.x, center.y, _WorldFeatureTypes.FeatureKind.POI, {
			"center": center,
			"name": display_name(kind),
			"poi": true,
			"poi_kind": kind,
			"landmark": true,
		})
		placed += 1
	return placed


static func display_name(kind: String) -> String:
	match kind:
		"rock_spire":
			return "Rock Spire"
		"ruined_tower":
			return "Ruined Tower"
		"crystal_glow":
			return "Crystal Glow"
		_:
			return "Landmark"


static func build_visual(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "DistantLandmark"
	root.set_meta("landmark_kind", kind)
	for spec in _boxes(kind):
		root.add_child(_box(spec))
	return root


static func model_height(node: Node3D) -> float:
	if node == null:
		return 0.0
	var max_y := 0.0
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh := (child as MeshInstance3D).mesh as BoxMesh
			if mesh:
				max_y = maxf(max_y, child.position.y + mesh.size.y * 0.5)
		elif child is Node3D:
			max_y = maxf(max_y, child.position.y + model_height(child as Node3D))
	return max_y


static func glow_energy(node: Node3D) -> float:
	var best := 0.0
	if node == null:
		return best
	for child in node.get_children():
		if child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override as StandardMaterial3D
			if mat != null and mat.emission_enabled:
				best = maxf(best, mat.emission_energy_multiplier)
	return best


static func _boxes(kind: String) -> Array:
	var stone := Color(0.52, 0.50, 0.46)
	var rubble := Color(0.40, 0.38, 0.34)
	var purple := Color(0.58, 0.22, 0.95)
	var core := Color(0.86, 0.62, 1.0)
	match kind:
		"ruined_tower":
			return [
				{"center": Vector3(0, 0.45, 0), "size": Vector3(3.4, 0.9, 3.4), "color": rubble, "glow": false},
				{"center": Vector3(0, 6.2, 0), "size": Vector3(1.5, 10.6, 1.5), "color": stone, "glow": false},
				{"center": Vector3(-0.7, 12.2, 0.2), "size": Vector3(0.7, 1.6, 0.7), "color": stone.darkened(0.1), "glow": false},
				{"center": Vector3(0.75, 11.6, -0.3), "size": Vector3(0.65, 0.9, 0.65), "color": stone.lightened(0.05), "glow": false},
			]
		"crystal_glow":
			return [
				{"center": Vector3(0, 4.6, 0), "size": Vector3(1.15, 9.2, 1.15), "color": Color(0.42, 0.08, 0.72), "glow": true, "energy": 1.15},
				{"center": Vector3(0.35, 8.4, 0.2), "size": Vector3(0.45, 3.2, 0.45), "color": core, "glow": true, "energy": 3.4},
				{"center": Vector3(-0.4, 2.2, 0.3), "size": Vector3(0.7, 1.6, 0.7), "color": purple, "glow": true, "energy": 2.2},
			]
		_:
			return [
				{"center": Vector3(0, 1.2, 0), "size": Vector3(2.6, 2.4, 2.6), "color": stone, "glow": false},
				{"center": Vector3(0, 4.4, 0), "size": Vector3(1.7, 4.0, 1.7), "color": stone.lightened(0.06), "glow": false},
				{"center": Vector3(0.15, 8.2, 0), "size": Vector3(1.05, 3.6, 1.05), "color": stone.darkened(0.08), "glow": false},
				{"center": Vector3(0.2, 11.1, 0), "size": Vector3(0.55, 2.2, 0.55), "color": stone.lightened(0.12), "glow": false},
			]


static func _box(spec: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = spec.get("size", Vector3.ONE)
	mi.mesh = box
	mi.position = spec.get("center", Vector3.ZERO)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat := StandardMaterial3D.new()
	var color: Color = spec.get("color", Color.WHITE)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.roughness = 0.9
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var look := _GroundLook.load_active()
	var glow := bool(spec.get("glow", false))
	var cell := _cell_texture(
		look.crystal_col if glow else look.stone_col,
		look.crystal_row if glow else look.stone_row
	)
	if cell != null:
		mat.albedo_texture = cell
		mat.albedo_color = Color.WHITE
	else:
		mat.albedo_color = color
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = float(spec.get("energy", 2.8))
	mi.material_override = mat
	return mi


static func _atlas() -> Texture2D:
	if _atlas_tex == null:
		_atlas_tex = load(_GroundLook.load_active().atlas_path) as Texture2D
	return _atlas_tex


static func _cell_texture(col: int, row: int) -> Texture2D:
	var base := _atlas()
	if base == null:
		return null
	var look := _GroundLook.load_active()
	var cols := maxi(look.atlas_columns, 1)
	var rows := maxi(look.atlas_rows, 1)
	var cell_w := float(base.get_width()) / float(cols)
	var cell_h := float(base.get_height()) / float(rows)
	var atlas := AtlasTexture.new()
	atlas.atlas = base
	atlas.region = Rect2(float(col) * cell_w, float(row) * cell_h, cell_w, cell_h)
	return atlas


static func _accept(proposed: Array[Dictionary]) -> Array[Dictionary]:
	var accepted: Array[Dictionary] = []
	for spot in proposed:
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		var crowded := false
		for prev in accepted:
			var other: Vector2i = prev.get("center", Vector2i.ZERO)
			if Vector2(center).distance_to(Vector2(other)) < float(MIN_SPACING):
				crowded = true
				break
		if not crowded:
			accepted.append(spot)
	return accepted


static func _site_open(world, center: Vector2i) -> bool:
	if not _FeatureRegistry.get_feature(center.x, center.y).is_empty():
		return false
	if world == null or not world.has_method("get_tile_type"):
		return false
	var tile := int(world.get_tile_type(float(center.x), float(center.y)))
	if tile == _Voxels.RIVER or tile == _Voxels.WATER or tile == _Voxels.OCEAN or tile == _Voxels.OCEAN2 or tile == _Voxels.OCEAN3:
		return false
	if world.has_method("get_biome"):
		var biome: Dictionary = world.get_biome(float(center.x), 0.0, float(center.y))
		if str(biome.get("name", "")) in ["ocean", "border_mountain", "marsh"]:
			return false
	return true


static func _mix(seed_value: int, cx: int, cz: int, salt: int) -> int:
	var n: int = int(seed_value) * 668265263 + int(cx) * 374761393 + int(cz) * 2246822519 + int(salt) * 3266489917
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	if n < 0:
		n = -n
	if n < 0:
		n = 0
	return n
