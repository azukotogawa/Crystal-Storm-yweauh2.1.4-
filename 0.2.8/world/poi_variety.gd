class_name PoiVariety
extends RefCounted

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
const _Blueprints = preload("res://helpers/structure_blueprints.gd")
const _Props = preload("res://helpers/voxel_prop_builder.gd")
const _VisualRegistry = preload("res://systems/game_visual_registry.gd")
const _Coords = preload("res://helpers/world_visual_coords.gd")
const _Relics = preload("res://relics/relic_registry.gd")
const _Voxels = preload("res://helpers/voxel_types.gd")

static var ENABLED: bool = true

const KINDS: Array[String] = ["cave_mouth", "ruined_watchtower"]
const PER_KIND := 4
const MIN_SEPARATION := 100.0
const MIN_FROM_SPAWN := 96.0
const MAX_FROM_SPAWN := 360.0
const STRIDE := 16
const MAX_STEP := 22.0
const STONE_ALBEDO := "res://assets/structures/stone_wall/stone_wall_albedo.png"
const PILLAR_ALBEDO := "res://assets/structures/ruin_pillar/ruin_pillar_albedo.png"
const STONE_MESH := "res://assets/structures/stone_wall/stone_wall.obj"
const PILLAR_MESH := "res://assets/structures/ruin_pillar/ruin_pillar.obj"
const MOUTH_COLOR := Color(0.09, 0.08, 0.07)
const ENCOUNTER_ID := "watch_sentry"
const LOOT_ID := "cave_chest"

const _ENCOUNTER_OFFSETS: Array[Vector2i] = [
	Vector2i(4, 0), Vector2i(0, 4), Vector2i(-4, 0), Vector2i(0, -4),
]

static var _mask_seed: int = -2147483647
static var _mask: Dictionary = {}


static func owns(poi_kind: String) -> bool:
	return poi_kind in KINDS


static func spawn_for(seed_value: int) -> Vector2i:
	return _WorldBorder.origin_corner_for_seed(seed_value)


static func walk_mask(world) -> Dictionary:
	if world == null:
		return {}
	var seed_value := int(world.world_seed)
	if _mask_seed == seed_value and not _mask.is_empty():
		return _mask
	_mask = _build_mask(world, spawn_for(seed_value))
	_mask_seed = seed_value
	return _mask


static func reachable(world, cell: Vector2i) -> bool:
	if world == null:
		return false
	return bool(walk_mask(world).get(_snap(cell), false))


static func plan(world, respect_features: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null:
		return out
	var seed_value := int(world.world_seed)
	var spawn := spawn_for(seed_value)
	var mask := walk_mask(world)
	var cells: Array[Vector2i] = []
	for key_v in mask.keys():
		var cell: Vector2i = key_v
		var dist := Vector2(cell).distance_to(Vector2(spawn))
		if dist < MIN_FROM_SPAWN or dist > MAX_FROM_SPAWN:
			continue
		cells.append(cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ra := _mix(seed_value, a.x, a.y, 9)
		var rb := _mix(seed_value, b.x, b.y, 9)
		if ra == rb:
			if a.x == b.x:
				return a.y < b.y
			return a.x < b.x
		return ra < rb
	)
	var towns: Array = _FeatureRegistry.get_towns()
	for kind in KINDS:
		var need := PER_KIND
		for phase in 3:
			if need <= 0:
				break
			for cell in cells:
				if need <= 0:
					break
				if _too_close(cell, out):
					continue
				if respect_features and not _FeatureRegistry.get_feature(cell.x, cell.y).is_empty():
					continue
				if _near_town(cell, towns):
					continue
				var biome := _biome_name(world, cell)
				if phase == 0 and not _preferred(kind, biome):
					continue
				if phase == 1 and biome == "marsh":
					continue
				var spot := {
					"center": cell,
					"poi_kind": kind,
					"spawn": spawn,
					"biome": biome,
					"site_index": PER_KIND - need,
				}
				out.append(spot)
				need -= 1
	return out


static func place(world) -> int:
	if not ENABLED or world == null:
		return 0
	_mask_seed = -2147483647
	_mask = {}
	return install(plan(world, true))


static func install(spots: Array) -> int:
	var placed := 0
	for spot_v in spots:
		var spot: Dictionary = spot_v
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		if not _FeatureRegistry.get_feature(center.x, center.y).is_empty():
			continue
		var kind := str(spot.get("poi_kind", ""))
		var payload := {
			"center": center,
			"name": display_name(kind),
			"poi": true,
			"poi_kind": kind,
			"variety": true,
			"spawn": spot.get("spawn", Vector2i.ZERO),
		}
		if kind == "cave_mouth":
			payload["chest"] = _chest(spot)
			payload["loot_entity"] = LOOT_ID
			payload["barricade"] = true
			_FeatureRegistry.register_feature(center.x, center.y, _WorldFeatureTypes.FeatureKind.POI, payload)
			_FeatureRegistry.set_tile_override(center.x, center.y, _Voxels.STONE2, true)
		else:
			payload["encounter"] = ENCOUNTER_ID
			payload["encounter_entity"] = ENCOUNTER_ID
			_FeatureRegistry.register_feature(center.x, center.y, _WorldFeatureTypes.FeatureKind.POI, payload)
			var sentry := _open_encounter_cell(center)
			if sentry != Vector2i(999999, 999999):
				_FeatureRegistry.register_spawn_data(sentry.x, sentry.y, _WorldFeatureTypes.FeatureKind.ENCOUNTER, {
					"encounter": ENCOUNTER_ID,
					"encounter_entity": ENCOUNTER_ID,
					"poi_kind": kind,
					"anchor": center,
					"pack": [Vector2i.ZERO],
				})
		placed += 1
	return placed


static func display_name(poi_kind: String) -> String:
	match poi_kind:
		"cave_mouth":
			return "Cave Mouth"
		"ruined_watchtower":
			return "Ruined Watchtower"
		_:
			return "Point of Interest"


static func layout(poi_kind: String) -> Array[Dictionary]:
	match poi_kind:
		"cave_mouth":
			return _structure_pieces(_Blueprints.STAIRS, "stone_wall", [{"plant": "fern", "offset": Vector2i(0, 1)}])
		"ruined_watchtower":
			return _structure_pieces(_Blueprints.SMALL_TOWER, "ruin_pillar", [])
		_:
			return []


static func build_visual(poi_kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "PoiVariety"
	root.set_meta("poi_kind", poi_kind)
	var scale := _Coords.voxel_scale()
	var registry = _VisualRegistry.new()
	var parts: Array = []
	for piece in layout(poi_kind):
		var off: Vector2i = piece.get("offset", Vector2i.ZERO)
		var shift := Vector3(float(off.x) * scale, 0.0, float(off.y) * scale)
		var structure_id := str(piece.get("structure", ""))
		if structure_id != "":
			for part_v in registry.structure_mesh_parts(structure_id):
				var part: Dictionary = part_v
				parts.append({
					"center": (part.get("center", Vector3.ZERO) as Vector3) + shift,
					"size": part.get("size", Vector3.ONE),
				})
		var plant_id := str(piece.get("plant", ""))
		if plant_id != "":
			var prop := _Props.build_plant(plant_id, 2)
			prop.name = "VoxelProp_%s_%d_%d" % [plant_id, off.x, off.y]
			prop.position = shift
			root.add_child(prop)
	if not parts.is_empty():
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "StructureMesh"
		mesh_inst.mesh = registry.build_structure_array_mesh(parts)
		var tex_path := STONE_ALBEDO if poi_kind == "cave_mouth" else PILLAR_ALBEDO
		mesh_inst.material_override = _textured(tex_path, Color.WHITE)
		root.add_child(mesh_inst)
	registry.free()
	if poi_kind == "cave_mouth":
		var mouth := MeshInstance3D.new()
		mouth.name = "CaveMouth"
		var box := BoxMesh.new()
		box.size = Vector3(1.6, 1.8, 1.2)
		mouth.mesh = box
		mouth.position = Vector3(scale * 2.0, 0.9, 0.0)
		var dark := StandardMaterial3D.new()
		dark.albedo_color = MOUTH_COLOR
		dark.roughness = 1.0
		dark.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mouth.material_override = dark
		root.add_child(mouth)
		var chest := Node3D.new()
		chest.name = "LootChest"
		chest.set_meta("loot_entity", LOOT_ID)
		chest.position = Vector3(scale, 0.4, 0.0)
		root.add_child(chest)
	elif poi_kind == "ruined_watchtower":
		var base := MeshInstance3D.new()
		base.name = "TowerBase"
		var slab := BoxMesh.new()
		slab.size = Vector3(2.2, 0.4, 2.2)
		base.mesh = slab
		base.position = Vector3(0.0, 0.2, 0.0)
		base.material_override = _textured(STONE_ALBEDO, Color.WHITE)
		root.add_child(base)
		var marker := Node3D.new()
		marker.name = "EncounterMarker"
		marker.set_meta("encounter_entity", ENCOUNTER_ID)
		marker.position = Vector3(0.0, 1.2, 0.0)
		root.add_child(marker)
	return root


static func model_height(node: Node3D) -> float:
	if node == null:
		return 0.0
	var max_y := 0.0
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh := (child as MeshInstance3D).mesh
			if mesh != null:
				var top := child.position.y + mesh.get_aabb().position.y + mesh.get_aabb().size.y
				max_y = maxf(max_y, top)
		elif child is Node3D:
			max_y = maxf(max_y, child.position.y + model_height(child as Node3D))
	return max_y


static func node_count(node: Node) -> int:
	if node == null:
		return 0
	var n := 1
	for child in node.get_children():
		n += node_count(child)
	return n


static func _chest(spot: Dictionary) -> Dictionary:
	var pool: Array[StringName] = _Relics.cave_loot_pool()
	var index := int(spot.get("site_index", 0))
	var center: Vector2i = spot.get("center", Vector2i.ZERO)
	var relic: StringName = &""
	if not pool.is_empty():
		relic = pool[posmod(index, pool.size())]
	var h: int = absi(hash(center) + index * 13)
	return {
		"relics": [relic],
		"resources": {
			"stone": 3 + (h % 4),
			"herb": 1 + (int(h / 7) % 2),
		},
	}


static func _open_encounter_cell(center: Vector2i) -> Vector2i:
	for off in _ENCOUNTER_OFFSETS:
		var cell := center + off
		if not _WorldBorder.is_playable(float(cell.x), float(cell.y)):
			continue
		if _FeatureRegistry.get_feature(cell.x, cell.y).is_empty():
			return cell
	return Vector2i(999999, 999999)


static func _textured(path: String, tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_color = tint
	var tex := load(path) as Texture2D
	if tex != null:
		mat.albedo_texture = tex
	return mat


static func _structure_pieces(blueprint_id: StringName, structure_id: String, plants: Array) -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	var bp: Dictionary = _Blueprints.get_blueprint(blueprint_id)
	for cell_v in bp.get("cells", []):
		var cell: Dictionary = cell_v
		if int(cell.get("y", 0)) != 0:
			continue
		pieces.append({
			"structure": structure_id,
			"plant": "",
			"offset": Vector2i(int(cell.get("x", 0)), int(cell.get("z", 0))),
		})
	for plant_v in plants:
		var plant: Dictionary = plant_v
		pieces.append({
			"structure": "",
			"plant": str(plant.get("plant", "")),
			"offset": plant.get("offset", Vector2i.ZERO),
		})
	return pieces


static func _too_close(cell: Vector2i, placed: Array[Dictionary]) -> bool:
	for spot in placed:
		var other: Vector2i = spot.get("center", Vector2i.ZERO)
		if Vector2(cell).distance_to(Vector2(other)) < MIN_SEPARATION:
			return true
	return false


static func _near_town(cell: Vector2i, towns: Array) -> bool:
	for town_v in towns:
		var town: Dictionary = town_v
		var center: Vector2i = town.get("center", Vector2i.ZERO)
		var radius := float(town.get("radius", 12.0)) + 8.0
		if Vector2(cell).distance_to(Vector2(center)) < radius:
			return true
	return false


static func _preferred(kind: String, biome: String) -> bool:
	if kind == "cave_mouth":
		return biome == "forest" or biome == "highland"
	if kind == "ruined_watchtower":
		return biome == "highland" or biome == "plains" or biome == "steppe"
	return false


static func _biome_name(world, cell: Vector2i) -> String:
	if world == null or not world.has_method("get_biome"):
		return ""
	var biome: Dictionary = world.get_biome(float(cell.x), 0.0, float(cell.y))
	return str(biome.get("name", ""))


static func _build_mask(world, spawn: Vector2i) -> Dictionary:
	var reached := {}
	var start := _nearest_walk_start(world, spawn)
	if start == Vector2i(999999, 999999):
		return reached
	var q: Array[Vector2i] = [start]
	var seen := {}
	seen[start] = true
	reached[start] = true
	var head := 0
	var dirs: Array[Vector2i] = [
		Vector2i(STRIDE, 0), Vector2i(-STRIDE, 0), Vector2i(0, STRIDE), Vector2i(0, -STRIDE),
	]
	var spawn_v := Vector2(spawn)
	var limit := MAX_FROM_SPAWN + float(STRIDE)
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		var cur_h := float(world.get_surface_height(float(cur.x), float(cur.y)))
		for d in dirs:
			var nxt: Vector2i = cur + d
			if seen.has(nxt):
				continue
			seen[nxt] = true
			if spawn_v.distance_to(Vector2(nxt)) > limit:
				continue
			if not _step_open(world, nxt, cur_h):
				continue
			reached[nxt] = true
			q.append(nxt)
	return reached


static func _nearest_walk_start(world, spawn: Vector2i) -> Vector2i:
	var origin := _snap(spawn)
	for ring in 8:
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if ring > 0 and absi(dx) != ring and absi(dz) != ring:
					continue
				var cell := origin + Vector2i(dx * STRIDE, dz * STRIDE)
				if _step_open(world, cell, -100000.0):
					return cell
	return Vector2i(999999, 999999)


static func _step_open(world, cell: Vector2i, prev_h: float) -> bool:
	if not _WorldBorder.is_playable(float(cell.x), float(cell.y)):
		return false
	if world == null or not world.has_method("get_tile_type"):
		return false
	var tile := int(world.get_tile_type(float(cell.x), float(cell.y)))
	if tile == _Voxels.OCEAN or tile == _Voxels.OCEAN2 or tile == _Voxels.OCEAN3:
		return false
	if tile == _Voxels.RIVER or tile == _Voxels.WATER:
		return false
	if prev_h > -10000.0 and world.has_method("get_surface_height"):
		var h := float(world.get_surface_height(float(cell.x), float(cell.y)))
		if absf(h - prev_h) > MAX_STEP:
			return false
	return true


static func _snap(cell: Vector2i) -> Vector2i:
	var s := float(STRIDE)
	return Vector2i(int(floor(float(cell.x) / s)) * STRIDE, int(floor(float(cell.y) / s)) * STRIDE)


static func _mix(seed_value: int, cx: int, cz: int, salt: int) -> int:
	var n: int = int(seed_value) * 374761393 + int(cx) * 668265263 + int(cz) * 2146121005 + int(salt) * 1274126177
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	if n < 0:
		n = -n
	if n < 0:
		n = 0
	return n
