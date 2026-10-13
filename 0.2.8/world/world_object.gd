class_name WorldObject
extends Node3D
## Authored structure instance. Explicit layers:
##   gameplay (cell, build_id, yaw) → visual mesh → debug collision AABB → this Node.
## Terrain voxels stay MultiMesh; do not instance this per voxel.

const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")
const _StructureOrientation = preload("res://helpers/structure_orientation.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")
const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")

var wx: int = 0
var wz: int = 0
var visual_id: String = ""
var yaw: float = 0.0
var gameplay: Dictionary = {}

var _mesh: MeshInstance3D
var _area: Area3D
var _shape: CollisionShape3D


func _ready() -> void:
	add_to_group("world_object")
	_ensure_children()


func _ensure_children() -> void:
	if _mesh == null:
		_mesh = get_node_or_null("Mesh") as MeshInstance3D
		if _mesh == null:
			_mesh = MeshInstance3D.new()
			_mesh.name = "Mesh"
			add_child(_mesh)
	if _area == null:
		_area = get_node_or_null("GameplayBounds") as Area3D
		if _area == null:
			_area = Area3D.new()
			_area.name = "GameplayBounds"
			_area.monitorable = true
			_area.monitoring = false
			_area.collision_layer = 0
			_area.collision_mask = 0
			add_child(_area)
	if _shape == null:
		_shape = _area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if _shape == null:
			_shape = CollisionShape3D.new()
			_shape.name = "CollisionShape3D"
			_area.add_child(_shape)


func bind(
	p_wx: int,
	p_wz: int,
	p_visual_id: String,
	feat: Dictionary,
	world,
	chunk_manager,
	crystal,
	registry,
	size: Vector3,
	height_offset: float
) -> void:
	_ensure_children()
	wx = p_wx
	wz = p_wz
	visual_id = p_visual_id
	gameplay = feat.duplicate(true)
	yaw = float(feat.get("yaw", _StructureOrientation.yaw_for(wx, wz, visual_id)))
	name = "Building_%s_%d_%d" % [visual_id, wx, wz]
	set_meta("building_visual_id", visual_id)
	set_meta("world_cell", Vector2i(wx, wz))
	set_meta("orientation_yaw", yaw)
	if _mesh:
		_mesh.set_meta("building_visual_id", visual_id)
	var col_x := float(wx) + 0.5
	var col_z := float(wz) + 0.5
	var y := height_offset
	if registry and registry.has_method("anchor_sprite_y"):
		y = float(registry.anchor_sprite_y(world, chunk_manager, crystal, col_x, col_z, height_offset))
	else:
		var lift: float = _GameVisualRegistry.SURFACE_LIFT
		y = _EntityNavigation.walkable_y_light(world, chunk_manager, crystal, col_x, col_z) + height_offset + lift
	position = _WorldVisualCoords.column_to_world_pos(col_x, y, col_z)
	rotation.y = 0.0
	if _mesh:
		_mesh.rotation.y = yaw
		if registry and registry.has_method("configure_building_mesh"):
			var tex: Texture2D = null
			if registry.has_method("get_billboard_texture"):
				tex = registry.get_billboard_texture(visual_id)
			elif registry.has_method("get_building_texture"):
				tex = registry.get_building_texture(StringName(visual_id))
			registry.configure_building_mesh(_mesh, tex, size, Color.WHITE, visual_id)
	_bind_gameplay_bounds()


func _bind_gameplay_bounds() -> void:
	if _shape == null:
		return
	var vs: float = _WorldSettings.get_active().voxel_scale
	var layer: float = _WorldSettings.get_active().layer_height()
	var box := BoxShape3D.new()
	# Bounds are in this node's local space (origin at walkable surface).
	# Walls/bridges occupy the raised column; gates are a passage (thin marker only).
	match visual_id:
		"gate":
			box.size = Vector3(vs, layer * 0.08, vs * 0.2)
			_shape.position = Vector3(0.0, layer * 0.04, 0.0)
		"bridge":
			box.size = Vector3(vs, layer * 0.2, vs)
			_shape.position = Vector3(0.0, layer * 0.1, 0.0)
		_:
			box.size = Vector3(vs, layer, vs)
			_shape.position = Vector3(0.0, layer * 0.5, 0.0)
	_shape.shape = box
	if _area:
		_area.rotation.y = yaw


func gameplay_aabb() -> AABB:
	if _shape == null or _shape.shape == null:
		return AABB()
	if not ("size" in _shape.shape):
		return AABB()
	var s: Vector3 = _shape.shape.size
	var local := AABB(-s * 0.5 + _shape.position, s)
	return _shape.global_transform * local


func inspect_dict() -> Dictionary:
	return {
		"wx": wx,
		"wz": wz,
		"visual_id": visual_id,
		"yaw": yaw,
		"node_path": str(get_path()) if is_inside_tree() else name,
		"gameplay": gameplay.duplicate(true),
		"uses_authored_mesh": bool(_mesh.get_meta("uses_authored_mesh", false)) if _mesh else false,
	}
