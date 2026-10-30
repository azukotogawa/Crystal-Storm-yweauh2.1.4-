extends Node3D

const _Gate = preload("res://helpers/debug_view_gate.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _Coords = preload("res://helpers/world_visual_coords.gd")

const VIEW_CHUNK := "chunk_borders"
const VIEW_FRONTIER := "crystal_frontier"
const VIEW_COLLISION := "collision"
const VIEW_PERF := "perf_overlay"
const _CHUNK_RADIUS := 2
const _FRONTIER_HALF := 24
const _FRONTIER_CAP := 180
const _COLLISION_RADIUS := 2
const _MIN_DEPTH := 0.04

var _on := {
	VIEW_CHUNK: false,
	VIEW_FRONTIER: false,
	VIEW_COLLISION: false,
	VIEW_PERF: false,
}
var _tick := 0
var _line_count := 0
var _segs: Array = []
var _mesh_host: MeshInstance3D
var _im: ImmediateMesh
var _perf_layer: CanvasLayer
var _perf_label: Label
var _menu_layer: CanvasLayer


func _ready() -> void:
	add_to_group("debug_view_layer")
	set_physics_process(false)
	set_process(false)
	set_process_unhandled_input(false)
	_ensure_actions()
	_apply_gate()


func dev_views_allowed() -> bool:
	return _Gate.dev_flag_on()


func is_view_on(id: String) -> bool:
	return bool(_on.get(id, false))


func set_view(id: String, on: bool) -> bool:
	if not _on.has(id):
		return false
	if not _Gate.dev_flag_on():
		_shut()
		set_process_unhandled_input(false)
		return false
	_on[id] = on
	_sync()
	return is_view_on(id) == on


func toggle_view(id: String) -> bool:
	return set_view(id, not is_view_on(id))


func all_views_off() -> bool:
	for id in _on.keys():
		if bool(_on[id]):
			return false
	return true


func render_idle() -> bool:
	return (
		not is_processing()
		and _mesh_host == null
		and not _perf_visible()
		and _menu_layer == null
		and all_views_off()
	)


func debug_line_count() -> int:
	return _line_count


func perf_text() -> String:
	if _perf_label == null:
		return ""
	return _perf_label.text


func menu_open() -> bool:
	return _menu_layer != null and is_instance_valid(_menu_layer)


func _apply_gate() -> void:
	if not _Gate.dev_flag_on():
		_shut()
		set_process_unhandled_input(false)
		return
	set_process_unhandled_input(true)
	set_process(_any_on())


func _shut() -> void:
	for id in _on.keys():
		_on[id] = false
	_drop_mesh()
	_hide_perf()
	_drop_menu()
	set_process(false)


func _any_on() -> bool:
	for id in _on.keys():
		if bool(_on[id]):
			return true
	return false


func _sync() -> void:
	if not _Gate.dev_flag_on():
		_shut()
		set_process_unhandled_input(false)
		return
	var spatial := bool(_on[VIEW_CHUNK]) or bool(_on[VIEW_FRONTIER]) or bool(_on[VIEW_COLLISION])
	if spatial:
		_ensure_mesh()
		_rebuild()
	else:
		_drop_mesh()
	if bool(_on[VIEW_PERF]):
		_ensure_perf()
		_perf_label.visible = true
		_refresh_perf()
	else:
		_hide_perf()
	set_process(_any_on())
	_sync_menu_checks()


func _unhandled_input(event: InputEvent) -> void:
	if not _Gate.dev_flag_on():
		_shut()
		set_process_unhandled_input(false)
		return
	if event.is_action_pressed("debug_view_menu"):
		_toggle_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_view_chunk_borders"):
		toggle_view(VIEW_CHUNK)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_view_crystal_frontier"):
		toggle_view(VIEW_FRONTIER)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_view_collision"):
		toggle_view(VIEW_COLLISION)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_view_perf"):
		toggle_view(VIEW_PERF)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _Gate.dev_flag_on() or not _any_on():
		_shut()
		return
	_tick += 1
	if _tick % 8 != 0:
		return
	if bool(_on[VIEW_CHUNK]) or bool(_on[VIEW_FRONTIER]) or bool(_on[VIEW_COLLISION]):
		_rebuild()
	if bool(_on[VIEW_PERF]):
		_refresh_perf()


func _ensure_actions() -> void:
	_bind_action("debug_view_menu", KEY_F8)
	_bind_action("debug_view_chunk_borders", KEY_F13)
	_bind_action("debug_view_crystal_frontier", KEY_F14)
	_bind_action("debug_view_collision", KEY_F15)
	_bind_action("debug_view_perf", KEY_F16)


func _bind_action(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if InputMap.action_get_events(action).is_empty():
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


func _toggle_menu() -> void:
	if not _Gate.dev_flag_on():
		_drop_menu()
		return
	if menu_open():
		_drop_menu()
		return
	_build_menu()


func _build_menu() -> void:
	_menu_layer = CanvasLayer.new()
	_menu_layer.name = "DebugViewMenu"
	_menu_layer.layer = 40
	add_child(_menu_layer)
	var root := PanelContainer.new()
	root.name = "DebugViewMenuPanel"
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2(12, 220)
	root.custom_minimum_size = Vector2(240, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.1, 0.92)
	style.set_content_margin_all(8)
	root.add_theme_stylebox_override("panel", style)
	_menu_layer.add_child(root)
	var box := VBoxContainer.new()
	root.add_child(box)
	var title := Label.new()
	title.text = "Dev views  F8"
	title.add_theme_color_override("font_color", Color(0.8, 0.92, 1.0))
	box.add_child(title)
	var hint := Label.new()
	hint.text = "F13 borders  F14 frontier  F15 collision  F16 perf"
	hint.add_theme_font_size_override("font_size", 11)
	box.add_child(hint)
	for id in [VIEW_CHUNK, VIEW_FRONTIER, VIEW_COLLISION, VIEW_PERF]:
		var check := CheckBox.new()
		check.name = id
		check.text = id.replace("_", " ")
		check.button_pressed = is_view_on(id)
		check.focus_mode = Control.FOCUS_NONE
		check.toggled.connect(_on_menu_toggled.bind(id))
		box.add_child(check)


func _on_menu_toggled(pressed: bool, id: String) -> void:
	set_view(id, pressed)


func _sync_menu_checks() -> void:
	if not menu_open():
		return
	for id in _on.keys():
		var check := _menu_layer.find_child(id, true, false) as CheckBox
		if check:
			check.set_pressed_no_signal(is_view_on(id))


func _drop_menu() -> void:
	if _menu_layer and is_instance_valid(_menu_layer):
		_menu_layer.queue_free()
	_menu_layer = null


func _ensure_mesh() -> void:
	if _mesh_host and is_instance_valid(_mesh_host):
		return
	_im = ImmediateMesh.new()
	_mesh_host = MeshInstance3D.new()
	_mesh_host.name = "DebugViewMesh"
	_mesh_host.mesh = _im
	_mesh_host.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_host.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_mesh_host.material_override = mat
	var game := get_tree().get_first_node_in_group("game") if get_tree() else null
	if game:
		game.add_child(_mesh_host)
	else:
		add_child(_mesh_host)


func _drop_mesh() -> void:
	_line_count = 0
	_segs.clear()
	if _im:
		_im.clear_surfaces()
	if _mesh_host and is_instance_valid(_mesh_host):
		_mesh_host.queue_free()
	_mesh_host = null
	_im = null


func _rebuild() -> void:
	if _im == null:
		return
	_segs.clear()
	var y := _draw_y()
	var column := _player_column()
	if bool(_on[VIEW_CHUNK]):
		_draw_chunks(column, y)
	if bool(_on[VIEW_FRONTIER]):
		_draw_frontier(column, y)
	if bool(_on[VIEW_COLLISION]):
		_draw_collision(column)
	_im.clear_surfaces()
	_line_count = _segs.size()
	if _segs.is_empty():
		return
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	for seg in _segs:
		_im.surface_set_color(seg[2])
		_im.surface_add_vertex(seg[0])
		_im.surface_add_vertex(seg[1])
	_im.surface_end()


func _draw_chunks(column: Vector2i, y: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var cm := tree.get_first_node_in_group("chunk_manager")
	if cm == null:
		return
	var raw = cm.get("chunks")
	if not (raw is Dictionary):
		return
	var origin := Vector2i(
		int(floor(float(column.x) / float(_ChunkData.SIZE))),
		int(floor(float(column.y) / float(_ChunkData.SIZE)))
	)
	var drawn := 0
	var color := Color(0.25, 0.9, 1.0, 1.0)
	for key_v in raw.keys():
		if drawn >= 48:
			break
		if not (key_v is Vector2i):
			continue
		var key: Vector2i = key_v
		if maxi(absi(key.x - origin.x), absi(key.y - origin.y)) > _CHUNK_RADIUS:
			continue
		var x0 := key.x * _ChunkData.SIZE
		var z0 := key.y * _ChunkData.SIZE
		var x1 := x0 + _ChunkData.SIZE
		var z1 := z0 + _ChunkData.SIZE
		var a := _Coords.column_to_world_pos(float(x0), y, float(z0))
		var b := _Coords.column_to_world_pos(float(x1), y, float(z0))
		var c := _Coords.column_to_world_pos(float(x1), y, float(z1))
		var d := _Coords.column_to_world_pos(float(x0), y, float(z1))
		_line(a, b, color)
		_line(b, c, color)
		_line(c, d, color)
		_line(d, a, color)
		drawn += 1


func _draw_frontier(column: Vector2i, y: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var crystal := tree.get_first_node_in_group("crystal_manager")
	if crystal == null or not crystal.has_method("get_depth_cells_in_rect"):
		return
	var rect := Rect2i(column.x - _FRONTIER_HALF, column.y - _FRONTIER_HALF, _FRONTIER_HALF * 2, _FRONTIER_HALF * 2)
	var cells: Dictionary = crystal.get_depth_cells_in_rect(rect)
	var drawn := 0
	var color := Color(0.72, 0.28, 1.0, 1.0)
	for key_v in cells.keys():
		if drawn >= _FRONTIER_CAP:
			break
		if not (key_v is Vector2i):
			continue
		var pos: Vector2i = key_v
		if float(cells[pos]) < _MIN_DEPTH:
			continue
		if not _cell_is_frontier(cells, pos):
			continue
		var center := _Coords.column_to_world_pos(float(pos.x) + 0.5, y + 0.2, float(pos.y) + 0.5)
		var scale := _Coords.voxel_scale() * 0.28
		_line(center + Vector3(-scale, 0, 0), center + Vector3(scale, 0, 0), color)
		_line(center + Vector3(0, 0, -scale), center + Vector3(0, 0, scale), color)
		drawn += 1


func _cell_is_frontier(cells: Dictionary, pos: Vector2i) -> bool:
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = pos + dir
		if not cells.has(n) or float(cells[n]) < _MIN_DEPTH:
			return true
	return false


func _draw_collision(column: Vector2i) -> void:
	var probe := _probe()
	if probe == null:
		return
	var color := Color(0.35, 1.0, 0.45, 1.0)
	for dx in range(-_COLLISION_RADIUS, _COLLISION_RADIUS + 1):
		for dz in range(-_COLLISION_RADIUS, _COLLISION_RADIUS + 1):
			var wx := float(column.x + dx) + 0.5
			var wz := float(column.y + dz) + 0.5
			var h: float = float(probe.walkable_height_at(wx, wz))
			var base := _Coords.column_to_world_pos(wx, h, wz)
			_line(base, base + Vector3(0, 0.45, 0), color)


func _probe() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var player := tree.get_first_node_in_group("player")
	if player:
		var named := player.get_node_or_null("VoxelFloorProbe")
		if named and named.has_method("walkable_height_at"):
			return named
		for child in player.get_children():
			if child.has_method("walkable_height_at"):
				return child
	var grouped := tree.get_first_node_in_group("voxel_floor_probe")
	if grouped and grouped.has_method("walkable_height_at"):
		return grouped
	return null


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_segs.append([a, b, color])


func _player_column() -> Vector2i:
	var tree := get_tree()
	if tree == null:
		return Vector2i.ZERO
	var player := tree.get_first_node_in_group("player")
	if player and player.has_method("get_voxel_position"):
		var voxel: Vector3 = player.get_voxel_position()
		return Vector2i(floori(voxel.x), floori(voxel.z))
	if player is Node3D:
		var pos := (player as Node3D).global_position
		var scale := maxf(_Coords.voxel_scale(), 0.001)
		return Vector2i(floori(pos.x / scale), floori(pos.z / scale))
	return Vector2i.ZERO


func _draw_y() -> float:
	var tree := get_tree()
	if tree == null:
		return 0.35
	var player := tree.get_first_node_in_group("player")
	if player is Node3D:
		return (player as Node3D).global_position.y + 0.15
	return 0.35


func _ensure_perf() -> void:
	if _perf_label and is_instance_valid(_perf_label):
		return
	_perf_layer = CanvasLayer.new()
	_perf_layer.name = "DebugPerfOverlay"
	_perf_layer.layer = 35
	add_child(_perf_layer)
	_perf_label = Label.new()
	_perf_label.name = "PerfReadout"
	_perf_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_perf_label.position = Vector2(12, 188)
	_perf_label.add_theme_font_size_override("font_size", 14)
	_perf_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 0.95))
	_perf_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.9))
	_perf_label.add_theme_constant_override("outline_size", 4)
	_perf_layer.add_child(_perf_label)


func _hide_perf() -> void:
	if _perf_label and is_instance_valid(_perf_label):
		_perf_label.visible = false
		_perf_label.text = ""
	if _perf_layer and is_instance_valid(_perf_layer):
		_perf_layer.queue_free()
	_perf_layer = null
	_perf_label = null


func _perf_visible() -> bool:
	return _perf_label != null and is_instance_valid(_perf_label) and _perf_label.visible


func _refresh_perf() -> void:
	if _perf_label == null:
		return
	var fps := Engine.get_frames_per_second()
	var frame_ms := 1000.0 / maxf(float(fps), 1.0)
	var hottest := "—"
	var profiler := get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("get_snapshot"):
		var snap: Dictionary = profiler.get_snapshot()
		var main_ms := float(snap.get("frame_ms", -1.0))
		if main_ms > 0.05:
			frame_ms = main_ms
		hottest = _hottest_name(snap)
	_perf_label.text = "PERF %d fps  %.1f ms  %s" % [fps, frame_ms, hottest]


func _hottest_name(snap: Dictionary) -> String:
	var secs: Dictionary = snap.get("sections", {})
	var best := ""
	var best_ms := 0.08
	for key_v in secs.keys():
		var entry: Dictionary = secs[key_v]
		var ms := 0.0
		if entry.has("last_ms"):
			ms = float(entry.last_ms)
		elif entry.has("last_us"):
			ms = float(entry.last_us) / 1000.0
		if ms > best_ms:
			best_ms = ms
			best = str(key_v)
	if best.is_empty():
		return "—"
	return "%s %.1f" % [best, best_ms]
