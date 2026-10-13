class_name AimIndicator
extends Node3D
## Where the current item is aimed.
## Tools do not draw a second block box: they emit tool_aim_changed for TargetHighlight.
## Melee draws a ground reticle. Ranged draws a line and an end marker.
## Reach for a block never passes ActionTargeting.INTERACTION_RANGE.
## The aim direction uses the camera basis, including pitch.

signal tool_aim_changed(cell: Vector2i, world_pos: Vector3, active: bool)

const _ActionTargeting = preload("res://player/action_targeting.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")

enum Style { NONE = 0, MELEE = 1, RANGED = 2, TOOL = 3 }

var _player: Node3D
var _reticle: MeshInstance3D
var _line: MeshInstance3D
var _end: MeshInstance3D
var _built: bool = false
var _suppressed: bool = false
var _highlight: Node
var _highlight_known: bool = false
var _last_cell_x: int = 999999
var _last_cell_z: int = 999999
var _last_active: bool = false
var _last_signaled: bool = false


func bind_player(player: Node3D) -> void:
	_player = player
	_highlight = null
	_highlight_known = false


func suppress(on: bool) -> void:
	_suppressed = on
	if on:
		_hide_marks()


static func aim_style(item_id: String) -> int:
	var def: Dictionary = _ItemTypes.get_def(item_id)
	if def.is_empty():
		return Style.NONE
	var cat := int(def.get("category", -1))
	var wk := int(def.get("weapon_kind", _ItemTypes.WeaponKind.MELEE))
	if cat == _ItemTypes.Category.TOOL or wk == _ItemTypes.WeaponKind.DIG:
		return Style.TOOL
	if cat == _ItemTypes.Category.MATERIAL:
		return Style.TOOL
	if wk == _ItemTypes.WeaponKind.RANGED or bool(def.get("throwable", false)):
		return Style.RANGED
	if cat == _ItemTypes.Category.WEAPON:
		return Style.MELEE
	return Style.NONE


## Columns. Block and melee marks stay inside INTERACTION_RANGE.
## A ranged shot uses its authored range; that marker is not a block target.
static func reach_columns(item_id: String) -> float:
	var def: Dictionary = _ItemTypes.get_def(item_id)
	var style := aim_style(item_id)
	var item_range := float(def.get("range", 0.0))
	if style == Style.TOOL:
		return _ActionTargeting.INTERACTION_RANGE
	if style == Style.MELEE:
		return minf(maxf(item_range, 0.5), _ActionTargeting.INTERACTION_RANGE)
	if style == Style.RANGED:
		if bool(def.get("throwable", false)):
			return minf(6.0, _ActionTargeting.INTERACTION_RANGE)
		return maxf(item_range, 1.0)
	return 0.0


static func aim_direction(player: Node3D) -> Vector3:
	if player == null:
		return Vector3.FORWARD
	var cam: Camera3D = null
	if "camera" in player:
		cam = player.camera as Camera3D
	if cam == null:
		cam = player.get_node_or_null("Camera3D") as Camera3D
	if cam:
		var aimed := -cam.global_transform.basis.z
		if aimed.length_squared() > 0.0001:
			return aimed.normalized()
	return _ActionTargeting.attack_forward(player)


func tick(item_id: String) -> void:
	_ensure()
	if _suppressed or _player == null or item_id == "":
		_hide_marks()
		_signal_tool(Vector2i.ZERO, Vector3.ZERO, false)
		return
	var style := aim_style(item_id)
	if style == Style.NONE:
		_hide_marks()
		_signal_tool(Vector2i.ZERO, Vector3.ZERO, false)
		return
	var vs: float = _WorldSettings.get_active().voxel_scale
	var reach_c := reach_columns(item_id)
	var reach_w := reach_c * vs
	var origin := _chest()
	var dir := aim_direction(_player)
	var feet_y := _player.global_position.y
	var end := _endpoint(origin, dir, reach_w, feet_y)
	if style == Style.TOOL:
		_hide_marks()
		var cell := _tool_cell(dir, reach_c)
		var active := cell.x < 900000
		var pos := Vector3.ZERO
		if active:
			pos = _WorldVisualCoords.column_to_world_pos(float(cell.x) + 0.5, feet_y, float(cell.y) + 0.5)
		_signal_tool(cell if active else Vector2i.ZERO, pos, active)
		return
	_signal_tool(Vector2i.ZERO, Vector3.ZERO, false)
	var show_ring := style == Style.MELEE
	var show_end := style == Style.RANGED
	_reticle.visible = show_ring
	_line.visible = true
	_end.visible = show_end
	if show_ring:
		_reticle.global_position = end
		_reticle.global_rotation = Vector3.ZERO
		var ring := vs * 0.28
		_reticle.scale = Vector3(ring, ring, ring)
	_line.global_position = origin.lerp(end, 0.5)
	if end.distance_squared_to(origin) > 0.0004:
		_line.look_at(end, Vector3.UP)
	var length := maxf(origin.distance_to(end), 0.05)
	_line.scale = Vector3(vs * 0.035, vs * 0.035, length)
	if show_end:
		_end.global_position = end
		_end.scale = Vector3.ONE * (vs * 0.16)


func _tool_cell(dir: Vector3, reach_c: float) -> Vector2i:
	var origin := _player_column()
	var cell := Vector2i(999999, 999999)
	if not _highlight_known and _player:
		_highlight = _player.get_node_or_null("TargetHighlight")
		_highlight_known = true
	if _highlight and _highlight.has_method("get_action_column"):
		var shared: Vector3 = _highlight.get_action_column()
		if shared != Vector3.ZERO:
			cell = Vector2i(floori(shared.x), floori(shared.z))
	if cell.x > 900000:
		var flat := Vector3(dir.x, 0.0, dir.z)
		if flat.length_squared() < 0.0001:
			flat = Vector3(0.0, 0.0, -1.0)
		else:
			flat = flat.normalized()
		var at := origin + Vector2(flat.x, flat.z) * reach_c
		cell = Vector2i(floori(at.x), floori(at.y))
	return _clamp_cell(origin, cell, _ActionTargeting.INTERACTION_RANGE)


func _player_column() -> Vector2:
	if _player and "voxel_position" in _player:
		var v: Vector3 = _player.voxel_position
		return Vector2(v.x, v.z)
	if _player and _player.has_method("get_voxel_position"):
		var v2: Vector3 = _player.get_voxel_position()
		return Vector2(v2.x, v2.z)
	if _player:
		var ws = _WorldSettings.get_active()
		return Vector2(ws.world_to_column(_player.global_position.x), ws.world_to_column(_player.global_position.z))
	return Vector2.ZERO


func _clamp_cell(origin: Vector2, cell: Vector2i, max_columns: float) -> Vector2i:
	if cell.x > 900000:
		return cell
	var center := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
	var delta := center - origin
	var dist := delta.length()
	if dist <= max_columns + 0.01 or dist < 0.001:
		return cell
	var pulled := origin + delta / dist * max_columns
	var out := Vector2i(floori(pulled.x), floori(pulled.y))
	var out_center := Vector2(float(out.x) + 0.5, float(out.y) + 0.5)
	if out_center.distance_to(origin) <= max_columns + 0.01:
		return out
	var back := origin + delta / dist * maxf(max_columns - 1.0, 0.5)
	return Vector2i(floori(back.x), floori(back.y))


func _signal_tool(cell: Vector2i, world_pos: Vector3, active: bool) -> void:
	if _last_signaled and cell.x == _last_cell_x and cell.y == _last_cell_z and active == _last_active:
		return
	_last_signaled = true
	_last_cell_x = cell.x
	_last_cell_z = cell.y
	_last_active = active
	tool_aim_changed.emit(cell, world_pos, active)


func _chest() -> Vector3:
	var vs: float = _WorldSettings.get_active().voxel_scale
	return _player.global_position + Vector3(0.0, vs * 0.9, 0.0)


func _endpoint(origin: Vector3, dir: Vector3, reach_w: float, feet_y: float) -> Vector3:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if dir.y < -0.08:
		var t: float = (feet_y - origin.y) / dir.y
		if t > 0.05:
			var hit := origin + dir * t
			var horiz := Vector2(hit.x - origin.x, hit.z - origin.z).length()
			if horiz <= reach_w:
				hit.y = feet_y + 0.04
				return hit
	if flat.length_squared() < 0.0001:
		flat = Vector3(0.0, 0.0, -1.0)
	else:
		flat = flat.normalized()
	return Vector3(origin.x, feet_y + 0.04, origin.z) + flat * reach_w


func _hide_marks() -> void:
	if not _built:
		return
	_reticle.visible = false
	_line.visible = false
	_end.visible = false


func _ensure() -> void:
	if _built:
		return
	var vs: float = _WorldSettings.get_active().voxel_scale
	var torus := TorusMesh.new()
	torus.inner_radius = 0.72
	torus.outer_radius = 1.0
	torus.rings = 6
	torus.ring_segments = 12
	_reticle = MeshInstance3D.new()
	_reticle.name = "MeleeReticle"
	_reticle.mesh = torus
	_reticle.material_override = _mat(Color(1.0, 0.78, 0.28, 0.8))
	_reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reticle.visible = false
	add_child(_reticle)
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	_line = MeshInstance3D.new()
	_line.name = "AimLine"
	_line.mesh = box
	_line.material_override = _mat(Color(1.0, 0.9, 0.55, 0.55))
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line.visible = false
	add_child(_line)
	_end = MeshInstance3D.new()
	_end.name = "AimEnd"
	var end_box := BoxMesh.new()
	end_box.size = Vector3(vs * 0.2, vs * 0.2, vs * 0.2)
	_end.mesh = end_box
	_end.material_override = _mat(Color(0.55, 0.8, 1.0, 0.9))
	_end.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_end.visible = false
	add_child(_end)
	_built = true


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.no_depth_test = true
	return mat
