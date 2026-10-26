class_name TargetHighlight
extends Node3D

const _ActionTargeting = preload("res://player/action_targeting.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _LivingForce = preload("res://world/living_force.gd")
const _MarkerLook = preload("res://config/target_marker_look.gd")
const _FACE_NORMALS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

var player: Player
var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager

const DISPLAY_SNAP_SPEED := 64.0
const HOVER_PULSE_HZ := 2.4

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _outline: MeshInstance3D
var _outline_mat: StandardMaterial3D
var _face: MeshInstance3D
var _face_pivot: Node3D
var _face_mat: StandardMaterial3D
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _look

var _stable_cell: Vector2i = Vector2i(999999, 999999)
var _display_pos: Vector3 = Vector3.ZERO
var _display_ready: bool = false
var _hover_t: float = 0.0
var _last_mode: StringName = &"none"
var _last_cell: Vector2i = Vector2i(999999, 999999)
var _place_flash_t: float = 0.0
var _action_column: Vector3 = Vector3.ZERO
var _crystal = null
var _aim_cache_ok: bool = false
var _aim_from_cache: bool = false
var _aim_mouse: Vector2 = Vector2(99999.0, 99999.0)
var _aim_pxz: Vector2 = Vector2(99999.0, 99999.0)
var _aim_yaw: float = 99999.0
var _aim_pitch: float = 99999.0
var _aim_range: float = -1.0
var _aim_build: bool = false
var _aim_item: String = ""
var _aim_edit: float = 99999.0
var _aim_depth: float = 99999.0
var _aim_cell: Vector2i = Vector2i(999999, 999999)
var _aim_hover: Vector3 = Vector3.ZERO
var _aim_stable: Vector3 = Vector3.ZERO
var _aim_info: Dictionary = {}
const BRUSH_MARK_POOL := 12
var _brush_marks: Array[MeshInstance3D] = []
var _brush_key: Vector3i = Vector3i(999999, 999999, -1)
var _brush_shown: bool = false
const STRUCTURE_GHOST_POOL := 24
var _structure_marks: Array[MeshInstance3D] = []
var _structure_mats: Array[StandardMaterial3D] = []
var _structure_edges: Array[StandardMaterial3D] = []
var _brush_outline: MeshInstance3D
var _outline_fill_mat: StandardMaterial3D
var _outline_edge_mat: StandardMaterial3D
var _outline_key: String = ""
var _outline_dirty: bool = true


func _ready() -> void:
	player = get_parent() as Player
	world = get_tree().get_first_node_in_group("world")
	chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	_crystal = get_tree().get_first_node_in_group("crystal_manager")
	process_priority = -20
	_look = _marker_look()
	_build_mesh()
	_build_ghost()
	_build_brush_pool()
	_build_brush_outline()
	_build_structure_pool()


func _build_mesh() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "TargetBox"
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	_mat.render_priority = 127
	_mat.no_depth_test = true
	var look = _marker_look()
	_mat.albedo_color = look.fill_albedo(&"dig", 0.0, 0.0, false)
	_mat.emission_enabled = true
	_mat.emission = look.fill_emission(&"dig", 0.0, false)
	_mat.emission_energy_multiplier = look.fill_energy(&"dig", 0.0, 0.0, false)
	_mesh.material_override = _mat
	_mesh.visible = false
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.sorting_offset = 4.0
	add_child(_mesh)
	_build_outline()
	_build_face_marker()


func _build_outline() -> void:
	_outline = MeshInstance3D.new()
	_outline.name = "TargetOutline"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.5
	var t: float = _marker_look().edge_thickness
	var corners: Array[Vector3] = [
		Vector3(-h, -h, 0.0), Vector3(h, -h, 0.0), Vector3(h, h, 0.0), Vector3(-h, h, 0.0),
	]
	var edges: Array[int] = [0, 1, 1, 2, 2, 3, 3, 0]
	for i in range(0, edges.size(), 2):
		_add_edge(st, corners[edges[i]], corners[edges[i + 1]], t)
	_outline.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 127
	var look = _marker_look()
	mat.albedo_color = look.edge_albedo(&"dig", false)
	mat.emission_enabled = true
	mat.emission = look.edge_emission(&"dig", false)
	mat.emission_energy_multiplier = look.edge_energy(&"dig", false)
	_outline_mat = mat
	_outline.material_override = mat
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_face_pivot = Node3D.new()
	_face_pivot.name = "TargetFacePivot"
	_mesh.add_child(_face_pivot)
	_face_pivot.add_child(_outline)


func _add_edge(st: SurfaceTool, a: Vector3, b: Vector3, thickness: float) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	lo -= Vector3(thickness, thickness, thickness)
	hi += Vector3(thickness, thickness, thickness)
	_add_box(st, lo, hi)


func _add_box(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var p: Array[Vector3] = [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	var quads: Array[int] = [
		0, 1, 2, 3, 5, 4, 7, 6, 4, 0, 3, 7, 1, 5, 6, 2, 3, 2, 6, 7, 4, 5, 1, 0,
	]
	for i in range(0, quads.size(), 4):
		var a: Vector3 = p[quads[i]]
		var b: Vector3 = p[quads[i + 1]]
		var c: Vector3 = p[quads[i + 2]]
		var d: Vector3 = p[quads[i + 3]]
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(d)


func _build_face_marker() -> void:
	_face = MeshInstance3D.new()
	_face.name = "TargetFace"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_face.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 127
	var look = _marker_look()
	mat.albedo_color = look.face_albedo(&"dig", false)
	mat.emission_enabled = true
	mat.emission = look.face_emission(&"dig", false)
	mat.emission_energy_multiplier = look.face_energy(&"dig", false)
	_face_mat = mat
	_face.material_override = mat
	_face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_face_pivot.add_child(_face)
	apply_face_marker(0)


func apply_face_marker(face: int) -> void:
	if _face_pivot == null:
		return
	var lift := 0.502
	match clampi(face, 0, 5):
		0:
			_face_pivot.position = Vector3(0.0, lift, 0.0)
			_face_pivot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		1:
			_face_pivot.position = Vector3(0.0, -lift, 0.0)
			_face_pivot.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		2:
			_face_pivot.position = Vector3(lift, 0.0, 0.0)
			_face_pivot.rotation_degrees = Vector3(0.0, 90.0, 0.0)
		3:
			_face_pivot.position = Vector3(-lift, 0.0, 0.0)
			_face_pivot.rotation_degrees = Vector3(0.0, -90.0, 0.0)
		4:
			_face_pivot.position = Vector3(0.0, 0.0, lift)
			_face_pivot.rotation_degrees = Vector3.ZERO
		5:
			_face_pivot.position = Vector3(0.0, 0.0, -lift)
			_face_pivot.rotation_degrees = Vector3(0.0, 180.0, 0.0)


func _build_ghost() -> void:
	_ghost = MeshInstance3D.new()
	_ghost.name = "PredictBox"
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_ghost.mesh = box
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	_ghost_mat.render_priority = 126
	_ghost_mat.no_depth_test = true
	var look = _marker_look()
	_ghost_mat.emission_enabled = true
	_ghost_mat.albedo_color = look.predict_albedo(&"dig", 0.0)
	_ghost_mat.emission = look.predict_emission(&"dig")
	_ghost_mat.emission_energy_multiplier = look.predict_energy_at(0.0)
	_ghost.material_override = _ghost_mat
	_ghost.visible = false
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.sorting_offset = 3.5
	add_child(_ghost)


func _process(delta: float) -> void:
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("target_highlight")
	if player == null or world == null or _mesh == null:
		_hide_brush_marks()
		if profiler and profiler.has_method("end"):
			profiler.end("target_highlight")
		return
	if _GameplayInput.blocks_actions():
		_mesh.visible = false
		if _ghost:
			_ghost.visible = false
		_hide_brush_marks()
		hide_structure_ghost()
		if profiler and profiler.has_method("end"):
			profiler.end("target_highlight")
		return
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")

	var range_v := _active_range()
	var build_held := _build_preview_held()

	var hover_col: Vector3
	var stable_col: Vector3
	var info: Dictionary
	if _aim_is_static(range_v, build_held):
		_aim_from_cache = true
		hover_col = _aim_hover
		stable_col = _aim_stable
		info = _aim_info
	else:
		_aim_from_cache = false
		hover_col = _ActionTargeting.pick_hover_column(
			player, world, chunk_manager, range_v
		)
		if hover_col == Vector3.ZERO and not _pointer_on_screen():
			hover_col = _ActionTargeting._target_column_forward(player, range_v, world, chunk_manager)
		if _held_is_ranged():
			var aimed := _ActionTargeting.cursor_cell_under_mouse(player, range_v)
			if aimed != Vector3.ZERO:
				hover_col = aimed

		var hover_cell := Vector2i(floori(hover_col.x), floori(hover_col.z)) if hover_col != Vector3.ZERO \
			else Vector2i(999999, 999999)
		_stable_cell = hover_cell
		stable_col = Vector3(float(_stable_cell.x) + 0.5, player.voxel_position.y, float(_stable_cell.y) + 0.5) \
			if _stable_cell.x < 900000 else Vector3.ZERO
		_action_column = stable_col

		var resolve_t0 := Time.get_ticks_usec()
		if stable_col != Vector3.ZERO:
			info = _ActionTargeting.resolve_action(
				player, world, chunk_manager, range_v, false, &"", stable_col
			)
		else:
			info = _ActionTargeting.resolve_action(player, world, chunk_manager, range_v)
		if profiler and profiler.has_method("record_func"):
			profiler.record_func("ActionTargeting::resolve_action", Time.get_ticks_usec() - resolve_t0)
		_remember_aim(range_v, build_held, hover_col, stable_col, info)

	var mode: StringName = info.get("mode", &"none")
	if mode not in [&"dig", &"build", &"attack", &"ranged"] or stable_col == Vector3.ZERO:
		_mesh.visible = false
		if _ghost:
			_ghost.visible = false
		_hide_brush_marks()
		hide_structure_ghost()
		_display_ready = false
		if profiler and profiler.has_method("end"):
			profiler.end("target_highlight")
		return

	_mesh.visible = true
	_hover_t += delta
	if _place_flash_t > 0.0:
		_place_flash_t = maxf(_place_flash_t - delta, 0.0)
	var ws = _WorldSettings.get_active()
	var layer: float = ws.layer_height()
	var scale: float = ws.voxel_scale
	var box_h: float = layer * 1.05
	var pulse: float = 0.5 + 0.5 * sin(_hover_t * TAU * HOVER_PULSE_HZ)
	var place_boost: float = clampf(_place_flash_t / 0.18, 0.0, 1.0)
	var pulse_scale: float = 1.0 + 0.04 * pulse + 0.14 * place_boost
	_mesh.scale = Vector3(scale * 1.06 * pulse_scale, box_h * (1.0 + 0.03 * pulse + 0.12 * place_boost), scale * 1.06 * pulse_scale)

	var target_pos: Vector3 = info.get("world_pos", Vector3.ZERO)
	target_pos.y -= layer * 0.5
	var cell: Vector2i = info.get("cell", _stable_cell)
	if not _display_ready or mode != _last_mode or cell != _last_cell:
		_display_pos = target_pos
		_display_ready = true
	else:
		var k: float = clampf(DISPLAY_SNAP_SPEED * delta, 0.0, 1.0)
		_display_pos = _display_pos.lerp(target_pos, k)
		if _display_pos.distance_to(target_pos) < 0.03:
			_display_pos = target_pos
	_mesh.global_position = _display_pos
	apply_face_marker(_ActionTargeting.last_pick_face)
	_last_mode = mode
	_last_cell = cell

	var blocked: bool = bool(info.get("blocked", false)) or not bool(info.get("valid", false))
	_paint_marker(mode, pulse, place_boost, blocked)

	_update_prediction(info, range_v, layer, scale, pulse)
	_hide_brush_marks()
	_update_brush_outline(mode, cell, layer, scale, pulse, place_boost, blocked)

	if profiler and profiler.has_method("end"):
		profiler.end("target_highlight")


func pulse_place_success() -> void:
	_place_flash_t = 0.18
	_outline_dirty = true


func get_action_column() -> Vector3:
	return _action_column


func _build_preview_held() -> bool:
	if not (Input.is_action_pressed("build_place") or Input.is_action_pressed("interact")):
		return false
	if player == null:
		return false
	var weapon := player.get_node_or_null("WeaponController")
	if weapon == null or not weapon.has_method("get_active_item"):
		return true
	var slot = weapon.get_active_item()
	if slot == null:
		return true
	return not _ItemTypes.has_right_click_ability(str(slot.id))


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouse):
		return
	var vp := get_viewport()
	if vp == null:
		return
	_ActionTargeting.note_event_mouse((event as InputEventMouse).position, vp.get_visible_rect().size)


func _pointer_on_screen() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	return vp.get_visible_rect().grow(2.0).has_point(_pointer())


func _pointer() -> Vector2:
	return _ActionTargeting.pointer_in(get_viewport())


func _aim_is_static(range_v: float, build_held: bool) -> bool:
	if not _aim_cache_ok or player == null:
		return false
	var mouse := _pointer()
	if mouse.distance_squared_to(_aim_mouse) > 1.0:
		return false
	var pxz := Vector2(player.voxel_position.x, player.voxel_position.z)
	if pxz.distance_squared_to(_aim_pxz) > 0.0016:
		return false
	var yaw := 0.0
	var pitch := 0.0
	if player.camera:
		if "yaw_degrees" in player.camera:
			yaw = float(player.camera.yaw_degrees)
		if "pitch_degrees" in player.camera:
			pitch = float(player.camera.pitch_degrees)
	if absf(yaw - _aim_yaw) > 0.15 or absf(pitch - _aim_pitch) > 0.15:
		return false
	if not is_equal_approx(range_v, _aim_range) or build_held != _aim_build:
		return false
	var item_id := _active_item_id()
	if item_id != _aim_item:
		return false
	if not is_equal_approx(_TerrainEdits.get_height_delta(_aim_cell.x, _aim_cell.y), _aim_edit):
		return false
	if _crystal and _crystal.has_method("get_depth_at"):
		if not is_equal_approx(float(_crystal.get_depth_at(_aim_cell.x, _aim_cell.y)), _aim_depth):
			return false
	return true


func _held_is_ranged() -> bool:
	var def := _ItemTypes.get_def(_active_item_id())
	if def.is_empty():
		return false
	return int(def.get("category", -1)) == _ItemTypes.Category.WEAPON \
		and int(def.get("weapon_kind", -1)) == _ItemTypes.WeaponKind.RANGED


func _active_item_id() -> String:
	if player == null:
		return ""
	var weapon := player.get_node_or_null("WeaponController")
	if weapon == null or not weapon.has_method("get_active_item"):
		return ""
	var slot = weapon.get_active_item()
	if slot == null:
		return ""
	return str(slot.id)


func _remember_aim(range_v: float, build_held: bool, hover_col: Vector3, stable_col: Vector3, info: Dictionary) -> void:
	_aim_cache_ok = true
	_aim_mouse = _pointer()
	_aim_pxz = Vector2(player.voxel_position.x, player.voxel_position.z)
	_aim_yaw = 0.0
	_aim_pitch = 0.0
	if player.camera:
		if "yaw_degrees" in player.camera:
			_aim_yaw = float(player.camera.yaw_degrees)
		if "pitch_degrees" in player.camera:
			_aim_pitch = float(player.camera.pitch_degrees)
	_aim_range = range_v
	_aim_build = build_held
	_aim_item = _active_item_id()
	_aim_hover = hover_col
	_aim_stable = stable_col
	_aim_info = info
	_aim_cell = info.get("cell", _stable_cell)
	_aim_edit = _TerrainEdits.get_height_delta(_aim_cell.x, _aim_cell.y)
	_aim_depth = 0.0
	if _crystal and _crystal.has_method("get_depth_at"):
		_aim_depth = float(_crystal.get_depth_at(_aim_cell.x, _aim_cell.y))


func get_brush_footprint() -> Array:
	if _action_column == Vector3.ZERO or world == null:
		return []
	var cell := Vector2i(floori(_action_column.x), floori(_action_column.z))
	return _LivingForce.footprint(cell.x, cell.y, _highlight_brush_radius(), world)


func _highlight_brush_radius() -> int:
	if player == null:
		return 1
	var weapon := player.get_node_or_null("WeaponController")
	if weapon and weapon.has_method("dig_brush_radius"):
		return int(weapon.dig_brush_radius())
	return 1


static func structure_ghost_tint(valid: bool) -> Color:
	return _MarkerLook.load_active().structure_tint(valid)


func _marker_look():
	if _look == null:
		_look = _MarkerLook.load_active()
	return _look


func _paint_marker(mode: StringName, pulse: float, place_boost: float, blocked: bool) -> void:
	var look = _marker_look()
	_mat.albedo_color = look.fill_albedo(mode, pulse, place_boost, blocked)
	_mat.emission = look.fill_emission(mode, place_boost, blocked)
	_mat.emission_energy_multiplier = look.fill_energy(mode, pulse, place_boost, blocked)
	if _outline_mat != null:
		_outline_mat.albedo_color = look.edge_albedo(mode, blocked)
		_outline_mat.emission = look.edge_emission(mode, blocked)
		_outline_mat.emission_energy_multiplier = look.edge_energy(mode, blocked)
	if _face_mat != null:
		_face_mat.albedo_color = look.face_albedo(mode, blocked)
		_face_mat.emission = look.face_emission(mode, blocked)
		_face_mat.emission_energy_multiplier = look.face_energy(mode, blocked)


func _build_structure_pool() -> void:
	for _i in STRUCTURE_GHOST_POOL:
		_add_structure_mark()


func _add_structure_mark() -> void:
	var mark := MeshInstance3D.new()
	mark.name = "StructureGhost%d" % _structure_marks.size()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mark.mesh = box
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mat.render_priority = 126
	mat.no_depth_test = true
	var look = _marker_look()
	mat.emission_enabled = true
	mat.albedo_color = look.structure_tint(true)
	mat.emission = look.structure_glow(true)
	mat.emission_energy_multiplier = look.structure_energy
	mark.material_override = mat
	var edge := MeshInstance3D.new()
	edge.name = "Edge"
	edge.mesh = _outline.mesh if _outline != null else box
	var edge_mat := StandardMaterial3D.new()
	edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_mat.no_depth_test = true
	edge_mat.render_priority = 127
	edge_mat.emission_enabled = true
	edge_mat.albedo_color = look.edge_albedo(&"build", false)
	edge_mat.emission = look.edge_emission(&"build", false)
	edge_mat.emission_energy_multiplier = look.edge_energy(&"build", false)
	edge.material_override = edge_mat
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.add_child(edge)
	mark.visible = false
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.sorting_offset = 3.6
	add_child(mark)
	_structure_marks.append(mark)
	_structure_mats.append(mat)
	_structure_edges.append(edge_mat)


func hide_structure_ghost() -> void:
	for mark in _structure_marks:
		mark.visible = false


func show_structure_ghost(cells: Array) -> void:
	if cells.is_empty():
		hide_structure_ghost()
		return
	while _structure_marks.size() < cells.size():
		_add_structure_mark()
	var ws = _WorldSettings.get_active()
	var layer: float = ws.layer_height()
	var scale: float = ws.voxel_scale
	var box := Vector3(scale * 1.02, layer, scale * 1.02)
	for i in cells.size():
		var cell: Dictionary = cells[i]
		var mark := _structure_marks[i]
		var mat := _structure_mats[i]
		var ok := bool(cell.get("valid", false))
		var look = _marker_look()
		var tint := structure_ghost_tint(ok)
		mat.albedo_color = tint
		mat.emission = look.structure_glow(ok)
		mat.emission_energy_multiplier = look.structure_energy
		var edge_mat := _structure_edges[i]
		edge_mat.albedo_color = look.edge_albedo(&"build", not ok)
		edge_mat.emission = look.edge_emission(&"build", not ok)
		edge_mat.emission_energy_multiplier = look.edge_energy(&"build", not ok)
		mark.global_position = cell.get("position", Vector3.ZERO)
		mark.scale = box
		mark.visible = true
	for i in range(cells.size(), _structure_marks.size()):
		_structure_marks[i].visible = false


func _build_brush_pool() -> void:
	for i in BRUSH_MARK_POOL:
		var mark := MeshInstance3D.new()
		mark.name = "BrushMark%d" % i
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		mark.mesh = box
		mark.material_override = _mat
		mark.visible = false
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mark.sorting_offset = 3.8
		add_child(mark)
		_brush_marks.append(mark)


func _hide_brush_marks() -> void:
	_hide_brush_outline()
	if not _brush_shown:
		return
	_brush_shown = false
	_brush_key = Vector3i(999999, 999999, -1)
	for mark in _brush_marks:
		mark.visible = false


func _weapon():
	if player == null:
		return null
	return player.get_node_or_null("WeaponController")


func _brush_tool_active() -> bool:
	var weapon = _weapon()
	return weapon != null and weapon.has_method("brush_tool_active") and bool(weapon.brush_tool_active())


func _hide_brush_outline() -> void:
	if _brush_outline != null:
		_brush_outline.visible = false
	_outline_key = ""


func _build_brush_outline() -> void:
	_brush_outline = MeshInstance3D.new()
	_brush_outline.name = "BrushOutline"
	_brush_outline.top_level = true
	_brush_outline.visible = false
	_brush_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_brush_outline.sorting_offset = 4.2
	_outline_fill_mat = StandardMaterial3D.new()
	_outline_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_outline_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_fill_mat.no_depth_test = true
	_outline_fill_mat.render_priority = 125
	_outline_fill_mat.emission_enabled = true
	_outline_edge_mat = StandardMaterial3D.new()
	_outline_edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_outline_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_edge_mat.no_depth_test = true
	_outline_edge_mat.render_priority = 126
	_outline_edge_mat.emission_enabled = true
	add_child(_brush_outline)


static func exposed_faces(cells: Array) -> Array:
	var held := {}
	for raw in cells:
		held[raw] = true
	var faces: Array = []
	for raw in cells:
		var cell: Vector3i = raw
		for normal in _FACE_NORMALS:
			if not held.has(cell + normal):
				faces.append({"cell": cell, "normal": normal})
	return faces


static func face_corners(cell: Vector3i, normal: Vector3i) -> Array[Vector3i]:
	var x := cell.x
	var y := cell.y
	var z := cell.z
	if normal.x != 0:
		var fx := x + 1 if normal.x > 0 else x
		return [Vector3i(fx, y, z), Vector3i(fx, y + 1, z), Vector3i(fx, y + 1, z + 1), Vector3i(fx, y, z + 1)]
	if normal.y != 0:
		var fy := y + 1 if normal.y > 0 else y
		return [Vector3i(x, fy, z), Vector3i(x + 1, fy, z), Vector3i(x + 1, fy, z + 1), Vector3i(x, fy, z + 1)]
	var fz := z + 1 if normal.z > 0 else z
	return [Vector3i(x, y, fz), Vector3i(x + 1, y, fz), Vector3i(x + 1, y + 1, fz), Vector3i(x, y + 1, fz)]


static func outline_edges(faces: Array) -> Array:
	var seen := {}
	for raw in faces:
		var face: Dictionary = raw
		var normal: Vector3i = face["normal"]
		var corners := face_corners(face["cell"], normal)
		for i in 4:
			var a: Vector3i = corners[i]
			var b: Vector3i = corners[(i + 1) % 4]
			var key := _edge_key(a, b)
			if not seen.has(key):
				seen[key] = {"a": a, "b": b, "normals": []}
			(seen[key]["normals"] as Array).append(normal)
	var edges: Array = []
	for key in seen:
		var edge: Dictionary = seen[key]
		var normals: Array = edge["normals"]
		if normals.size() == 2 and normals[0] == normals[1]:
			continue
		edges.append(edge)
	return edges


static func _edge_key(a: Vector3i, b: Vector3i) -> String:
	var lo := a
	var hi := b
	if b.x < a.x or (b.x == a.x and (b.y < a.y or (b.y == a.y and b.z < a.z))):
		lo = b
		hi = a
	return "%d,%d,%d|%d,%d,%d" % [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z]


func _lattice_world(point: Vector3i, layer: float) -> Vector3:
	var ws = _WorldSettings.get_active()
	return Vector3(ws.column_to_world(float(point.x)), float(point.y) * layer, ws.column_to_world(float(point.z)))


func _rebuild_brush_outline(cells: Array, layer: float, scale: float) -> void:
	var faces := exposed_faces(cells)
	var fill := SurfaceTool.new()
	fill.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lift: float = scale * 0.012
	for raw in faces:
		var face: Dictionary = raw
		var normal: Vector3i = face["normal"]
		var corners := face_corners(face["cell"], normal)
		var push := Vector3(normal) * lift
		var p: Array[Vector3] = []
		for corner in corners:
			p.append(_lattice_world(corner, layer) + push)
		fill.add_vertex(p[0])
		fill.add_vertex(p[1])
		fill.add_vertex(p[2])
		fill.add_vertex(p[0])
		fill.add_vertex(p[2])
		fill.add_vertex(p[3])
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_TRIANGLES)
	var thickness: float = _marker_look().edge_thickness
	for raw in outline_edges(faces):
		var edge: Dictionary = raw
		_add_edge(lines, _lattice_world(edge["a"], layer), _lattice_world(edge["b"], layer), thickness)
	var mesh: ArrayMesh = fill.commit()
	lines.commit(mesh)
	mesh.surface_set_material(0, _outline_fill_mat)
	mesh.surface_set_material(1, _outline_edge_mat)
	_brush_outline.mesh = mesh


func _outline_cells(mode: StringName, cell: Vector2i) -> Array:
	var weapon = _weapon()
	if weapon == null or not weapon.has_method("brush_shape") or world == null:
		return []
	var place := mode == &"build"
	if mode != &"dig" and not place:
		return []
	if place and (weapon.get_place_id() != "fill" or weapon.active_blueprint_id() != &""):
		return []
	if not place and not _ItemTypes.breaks_blocks(_active_item_id()):
		return []
	var shape := int(weapon.brush_shape())
	if shape == _ItemTypes.BreakShape.SINGLE:
		return []
	var editor = get_tree().get_first_node_in_group("terrain_editor") if is_inside_tree() else null
	if editor == null or not editor.has_method("brush_plan"):
		return []
	var anchor := Vector3i(cell.x, _TerrainEdits.surface_block_y(world, cell.x, cell.y), cell.y)
	return editor.brush_plan(shape, anchor, _break_preview_aim(), place, player, float(weapon.brush_reach()))


func _update_brush_outline(mode: StringName, cell: Vector2i, layer: float, scale: float, pulse: float, place_boost: float, blocked: bool) -> void:
	if _brush_outline == null:
		return
	var weapon = _weapon()
	var shape := int(weapon.brush_shape()) if weapon != null and weapon.has_method("brush_shape") else 0
	var key := "%s|%d|%d,%d|%s|%s" % [String(mode), shape, cell.x, cell.y, _active_item_id(), str(_ItemTypes.aim_cardinal(_break_preview_aim()))]
	if _outline_dirty or key != _outline_key:
		var cells := _outline_cells(mode, cell)
		_outline_key = key
		_outline_dirty = false
		if cells.is_empty():
			_brush_outline.visible = false
			_brush_outline.mesh = null
		else:
			_rebuild_brush_outline(cells, layer, scale)
			_brush_outline.visible = true
	if not _brush_outline.visible:
		return
	_mesh.visible = false
	var look = _marker_look()
	var fill_color: Color = look.fill_albedo(mode, pulse, place_boost, blocked)
	fill_color.a = clampf(fill_color.a * 1.6, 0.0, 0.5)
	_outline_fill_mat.albedo_color = fill_color
	_outline_fill_mat.emission = look.fill_emission(mode, place_boost, blocked)
	_outline_fill_mat.emission_energy_multiplier = look.fill_energy(mode, pulse, place_boost, blocked)
	_outline_edge_mat.albedo_color = look.edge_albedo(mode, blocked)
	_outline_edge_mat.emission = look.edge_emission(mode, blocked)
	_outline_edge_mat.emission_energy_multiplier = look.edge_energy(mode, blocked)


static func break_preview_cells(item_id: String, anchor: Vector3i, aim: Vector3, world, editor = null) -> Array[Vector3i]:
	var listed: Array[Vector3i] = _ItemTypes.break_cells(_ItemTypes.break_shape_for(item_id), anchor, aim)
	return _TerrainEdits.clip_breakable_cells(listed, world, editor)


static func preview_mark_cells(item_id: String, anchor: Vector3i, aim: Vector3, world, editor = null) -> Array[Vector3i]:
	var marks: Array[Vector3i] = []
	for cell in break_preview_cells(item_id, anchor, aim, world, editor):
		if cell.x == anchor.x and cell.z == anchor.z:
			continue
		marks.append(cell)
	return marks


func _update_brush_footprint(cell: Vector2i, layer: float, scale: float) -> void:
	if _ItemTypes.MULTI_BLOCK_BREAK and _ItemTypes.breaks_blocks(_active_item_id()):
		_place_break_preview(cell, layer, scale)
		return
	var radius := _highlight_brush_radius()
	if radius <= 1 or _brush_marks.is_empty():
		_hide_brush_marks()
		return
	var key := Vector3i(cell.x, cell.y, radius)
	if key != _brush_key:
		_brush_key = key
		var cells: Array = _LivingForce.footprint(cell.x, cell.y, radius, world)
		var extra := 0
		var ws = _WorldSettings.get_active()
		for cell_v in cells:
			var c: Vector2i = cell_v
			if c == cell:
				continue
			if extra >= _brush_marks.size():
				break
			var mark: MeshInstance3D = _brush_marks[extra]
			extra += 1
			var top := world.get_surface_height(float(c.x), float(c.y)) + layer
			mark.global_position = Vector3(
				ws.column_to_world(float(c.x) + 0.5),
				top - layer * 0.5,
				ws.column_to_world(float(c.y) + 0.5)
			)
			mark.visible = true
		for i in range(extra, _brush_marks.size()):
			_brush_marks[i].visible = false
		_brush_shown = extra > 0
	for mark in _brush_marks:
		if mark.visible:
			mark.scale = Vector3(scale * 0.92, layer * 0.92, scale * 0.92)


func _place_break_preview(cell: Vector2i, layer: float, scale: float) -> void:
	if _brush_marks.is_empty() or world == null:
		_hide_brush_marks()
		return
	var anchor_y := _TerrainEdits.surface_block_y(world, cell.x, cell.y)
	var anchor := Vector3i(cell.x, anchor_y, cell.y)
	var aim := _break_preview_aim()
	var editor = get_tree().get_first_node_in_group("terrain_editor") if is_inside_tree() else null
	var marks := preview_mark_cells(_active_item_id(), anchor, aim, world, editor)
	var ws = _WorldSettings.get_active()
	var extra := 0
	for raw in marks:
		if extra >= _brush_marks.size():
			break
		var c: Vector3i = raw
		var mark: MeshInstance3D = _brush_marks[extra]
		extra += 1
		var top := float(world.get_surface_height(float(c.x), float(c.z))) + layer
		mark.global_position = Vector3(
			ws.column_to_world(float(c.x) + 0.5),
			top - layer * 0.5,
			ws.column_to_world(float(c.z) + 0.5)
		)
		mark.visible = true
		mark.scale = Vector3(scale * 0.92, layer * 0.92, scale * 0.92)
	for i in range(extra, _brush_marks.size()):
		_brush_marks[i].visible = false
	_brush_shown = extra > 0
	_brush_key = Vector3i(cell.x, cell.y, 1000 + extra)


func _break_preview_aim() -> Vector3:
	var reach := _active_range()
	var weapon := player.get_node_or_null("WeaponController") if player else null
	if weapon != null and weapon.has_method("_aim_forward"):
		return weapon._aim_forward(reach)
	if player != null:
		return _ActionTargeting.cursor_aim(player, reach)
	return Vector3(0, 0, 1)


func _update_prediction(info: Dictionary, range_v: float, layer: float, scale: float, pulse: float) -> void:
	if _ghost == null:
		return
	if _aim_from_cache:
		if not _ghost.visible:
			return
		var cached_mode: StringName = info.get("mode", &"none")
		var look = _marker_look()
		_ghost_mat.albedo_color = look.predict_albedo(cached_mode, pulse)
		_ghost_mat.emission = look.predict_emission(cached_mode)
		_ghost_mat.emission_energy_multiplier = look.predict_energy_at(pulse)
		return
	var mode: StringName = info.get("mode", &"none")
	if mode not in [&"dig", &"build"] or not bool(info.get("valid", false)):
		_ghost.visible = false
		return
	var col: Vector3 = info.get("column", Vector3.ZERO)
	var pred: Vector3 = _ActionTargeting.predict_next_column(
		player, col, world, chunk_manager, range_v
	)
	if pred == Vector3.ZERO:
		_ghost.visible = false
		return
	var pred_info: Dictionary = _ActionTargeting.resolve_action(
		player, world, chunk_manager, range_v, false, mode, pred
	)
	if not bool(pred_info.get("valid", false)):
		_ghost.visible = false
		return
	_ghost.visible = true
	var box_h: float = layer * 1.0
	_ghost.scale = Vector3(scale * 1.02, box_h, scale * 1.02)
	var gpos: Vector3 = pred_info.get("world_pos", Vector3.ZERO)
	gpos.y -= layer * 0.5
	_ghost.global_position = gpos
	var look = _marker_look()
	_ghost_mat.albedo_color = look.predict_albedo(mode, pulse)
	_ghost_mat.emission = look.predict_emission(mode)
	_ghost_mat.emission_energy_multiplier = look.predict_energy_at(pulse)


func _active_range() -> float:
	var weapon := player.get_node_or_null("WeaponController")
	if weapon == null or not weapon.has_method("get_active_item"):
		return _ActionTargeting.reach()
	var slot = weapon.get_active_item()
	if slot == null:
		return _ActionTargeting.reach()
	var def := _ItemTypes.get_def(str(slot.id))
	if def.is_empty():
		return _ActionTargeting.reach()
	var category := int(def.get("category", -1))
	var kind := int(def.get("weapon_kind", -1))
	if category == _ItemTypes.Category.WEAPON \
			and (kind == _ItemTypes.WeaponKind.MELEE or kind == _ItemTypes.WeaponKind.RANGED):
		return float(def.get("range", 2.0))
	if weapon.has_method("action_reach"):
		return float(weapon.action_reach())
	return _ActionTargeting.reach()
