class_name TargetHighlight
extends Node3D

const _ActionTargeting = preload("res://player/action_targeting.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const BUILD_PREVIEW_RANGE: float = 2.8

var player: Player
var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	player = get_parent() as Player
	world = get_tree().get_first_node_in_group("world")
	chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	_build_mesh()


func _build_mesh() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "TargetBox"
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_mesh.mesh = box
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	_mat.render_priority = 127
	_mat.no_depth_test = true
	_mat.albedo_color = Color(1.0, 0.92, 0.2, 0.55)
	_mesh.material_override = _mat
	_mesh.visible = false
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.sorting_offset = 4.0
	add_child(_mesh)


func _process(_delta: float) -> void:
	if player == null or world == null or _mesh == null:
		return
	if _GameplayInput.blocks_actions():
		_mesh.visible = false
		return
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	var range_v := _active_range()
	var build_preview: bool = (
		Input.is_action_pressed("build_place") or Input.is_action_pressed("interact")
	)
	var info: Dictionary
	if build_preview:
		info = _ActionTargeting.resolve_action(
			player, world, chunk_manager, BUILD_PREVIEW_RANGE, false, &"build"
		)
	else:
		info = _ActionTargeting.resolve_action(player, world, chunk_manager, range_v)
	var mode: StringName = info.get("mode", &"none")
	if mode not in [&"dig", &"build", &"attack"] or not info.get("valid", false):
		_mesh.visible = false
		return
	_mesh.visible = true
	var ws = _WorldSettings.get_active()
	var layer: float = ws.layer_height()
	var scale: float = ws.voxel_scale
	var face_normal: Vector3 = info.get("face_normal", Vector3.UP)
	if face_normal.length_squared() < 0.01:
		face_normal = Vector3.UP
	else:
		face_normal = face_normal.normalized()
	var thin: float = maxf(scale * 0.006, 0.004)
	var pad: float = scale * 1.02
	var height: float = layer * 1.02
	if absf(face_normal.x) > 0.5:
		_mesh.scale = Vector3(thin, height, pad)
	elif absf(face_normal.y) > 0.5:
		_mesh.scale = Vector3(pad, thin, pad)
	else:
		_mesh.scale = Vector3(pad, height, thin)
	var face_pos: Vector3 = info.get("world_pos", Vector3.ZERO)
	_mesh.global_position = face_pos + face_normal * (thin * 0.5 + scale * 0.002)
	match mode:
		&"dig":
			_mat.albedo_color = Color(0.95, 0.55, 0.15, 0.42)
		&"build":
			_mat.albedo_color = Color(0.35, 0.95, 0.45, 0.42)
		&"attack":
			_mat.albedo_color = Color(0.95, 0.25, 0.2, 0.42)
		&"ranged":
			_mat.albedo_color = Color(0.55, 0.75, 1.0, 0.38)
		_:
			_mat.albedo_color = Color(0.35, 0.95, 0.45, 0.38)


func _active_range() -> float:
	if Input.is_action_pressed("build_place") or Input.is_action_pressed("interact"):
		return BUILD_PREVIEW_RANGE
	var weapon := player.get_node_or_null("WeaponController")
	if weapon == null or not weapon.has_method("get_active_item"):
		return 2.0
	var slot = weapon.get_active_item()
	if slot == null:
		return 2.0
	var def := _ItemTypes.get_def(str(slot.id))
	if def.is_empty():
		return 2.0
	if str(slot.id) == "stone":
		return BUILD_PREVIEW_RANGE
	return float(def.get("range", 2.8))