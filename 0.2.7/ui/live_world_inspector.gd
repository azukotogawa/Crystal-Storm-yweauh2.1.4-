extends CanvasLayer
## Developer Live World Inspector. F4 toggles. Does not change gameplay.

const _LiveWorldQuery = preload("res://helpers/live_world_query.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

var panel_open: bool = false:
	set(v):
		var closing: bool = panel_open and not v
		panel_open = v
		if is_inside_tree():
			_apply_open_state()
		if closing:
			clear_pin()
var toggles: Dictionary = {
	"collision_shapes": false,
	"voxel_boundaries": true,
	"chunk_boundaries": false,
	"mesh_bounds": false,
	"walkable_surface": true,
	"terrain_height": false,
	"feature_anchors": false,
	"water_cells": false,
	"crystal_cells": false,
	"stream_bake_state": true,
}

var last_snapshot: Dictionary = {}
var pin_cell: Vector2i = Vector2i(2147483647, 2147483647):
	set(v):
		pin_cell = v
		_shown_cell = Vector2i(2147483647, 2147483647)
var _shown_cell: Vector2i = Vector2i(2147483647, 2147483647)
var _label: RichTextLabel
var _toggle_box: HFlowContainer
var _status: Label
var _marker: MeshInstance3D
var _im: ImmediateMesh
var _im_inst: MeshInstance3D
var _frame: int = 0
var _panel_root: Control


func _ready() -> void:
	add_to_group("live_world_inspector")
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_ensure_markers()
	set_process(true)
	_apply_open_state()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F4:
		if _GameplayInput.world_loading or _GameplayInput.dev_chat_open:
			return
		panel_open = not panel_open
		get_viewport().set_input_as_handled()


func clear_pin() -> void:
	pin_cell = Vector2i(2147483647, 2147483647)
	last_snapshot = {}
	_shown_cell = Vector2i(2147483647, 2147483647)


func _apply_open_state() -> void:
	if _panel_root:
		_panel_root.visible = panel_open
	if not panel_open and _marker:
		_marker.visible = false


func _build_ui() -> void:
	var root := MarginContainer.new()
	_panel_root = root
	root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	root.offset_left = -360
	root.offset_top = 44
	root.offset_right = -10
	root.offset_bottom = 430
	root.visible = panel_open
	add_child(root)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.96)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	panel.clip_contents = true
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	panel.add_child(v)
	var title := Label.new()
	title.text = "World Inspector  F4"
	title.add_theme_color_override("font_color", Color(0.78, 0.92, 1.0))
	title.add_theme_font_size_override("font_size", 14)
	v.add_child(title)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.clip_text = true
	_status.custom_minimum_size = Vector2(0, 16)
	_status.text = "CURSOR —"
	v.add_child(_status)
	_toggle_box = HFlowContainer.new()
	_toggle_box.add_theme_constant_override("h_separation", 6)
	v.add_child(_toggle_box)
	for key in toggles.keys():
		var cb := CheckBox.new()
		cb.text = str(key).replace("_", " ")
		cb.button_pressed = bool(toggles[key])
		cb.add_theme_font_size_override("font_size", 11)
		cb.toggled.connect(_on_toggle.bind(str(key)))
		_toggle_box.add_child(cb)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = false
	_label.scroll_active = true
	_label.custom_minimum_size = Vector2(330, 260)
	_label.add_theme_font_size_override("normal_font_size", 13)
	v.add_child(_label)


func _on_toggle(pressed: bool, key: String) -> void:
	toggles[key] = pressed
	if key == "collision_shapes":
		get_tree().debug_collisions_hint = pressed


func _ensure_markers() -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game == null:
		game = get_tree().current_scene
	if game == null:
		return
	if _marker == null or not is_instance_valid(_marker):
		_marker = MeshInstance3D.new()
		_marker.name = "LiveInspectorMarker"
		var box := BoxMesh.new()
		var vs: float = _WorldVisualCoords.voxel_scale()
		box.size = Vector3(vs * 1.02, 0.08, vs * 1.02)
		_marker.mesh = box
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.2, 0.95, 1.0, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_marker.material_override = mat
		game.add_child(_marker)
	if _im_inst == null or not is_instance_valid(_im_inst):
		_im = ImmediateMesh.new()
		_im_inst = MeshInstance3D.new()
		_im_inst.name = "LiveInspectorOverlays"
		_im_inst.mesh = _im
		var imat := StandardMaterial3D.new()
		imat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		imat.vertex_color_use_as_albedo = true
		_im_inst.material_override = imat
		game.add_child(_im_inst)


func _process(_delta: float) -> void:
	_frame += 1
	if not panel_open:
		if _marker and _marker.visible:
			_marker.visible = false
		return
	_ensure_markers()
	var want: Vector2i = pin_cell
	if want.x == 2147483647:
		var snap0: Dictionary = _LiveWorldQuery.inspect_targeted(get_tree())
		want = Vector2i(int(snap0.get("wx", 0)), int(snap0.get("wz", 0)))
		if bool(snap0.get("ok", false)) and want != _shown_cell:
			last_snapshot = snap0
			_shown_cell = want
			_refresh_label()
			_update_marker()
			_draw_overlays()
			return
	var force: bool = want != _shown_cell
	if not force and _frame % 4 != 0:
		return
	if pin_cell.x != 2147483647:
		last_snapshot = _LiveWorldQuery.inspect_cell(get_tree(), pin_cell.x, pin_cell.y)
	else:
		last_snapshot = _LiveWorldQuery.inspect_targeted(get_tree())
	_shown_cell = Vector2i(int(last_snapshot.get("wx", want.x)), int(last_snapshot.get("wz", want.y)))
	_refresh_label()
	_update_marker()
	_draw_overlays()


func _refresh_label() -> void:
	if _label == null or not panel_open:
		return
	var s: Dictionary = last_snapshot
	if not bool(s.get("ok", false)):
		_label.text = str(s.get("error", "no snapshot"))
		if _status:
			_status.text = ""
		return
	var pinned: bool = pin_cell.x != 2147483647
	var wx := int(s.get("wx", 0))
	var wz := int(s.get("wz", 0))
	if _status:
		_status.text = ("PINNED %d,%d" if pinned else "CURSOR %d,%d") % [wx, wz]
		_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35) if pinned else Color(0.7, 0.85, 1.0))
	var lines: PackedStringArray = PackedStringArray()
	var disc: Array = []
	var disc_raw = s.get("discrepancies", [])
	if disc_raw is PackedStringArray or disc_raw is Array:
		for item in disc_raw:
			disc.append(str(item))
	if disc.is_empty():
		lines.append("[color=#6ee7a8][AGREE][/color] visual · collision · gameplay")
	else:
		lines.append("[color=#ff6b7a][DISAGREE][/color]")
		for item in disc:
			lines.append("[color=#ff8899]  %s[/color]" % item)
	lines.append("[b]CELL[/b]  %d, %d    chunk %s" % [wx, wz, str(s.get("owning_chunk", ""))])
	var origin := str(s.get("origin", ""))
	var life := str(s.get("chunk_lifecycle", "resident" if bool(s.get("streamed", false)) else "missing"))
	lines.append("        origin %s    chunk %s" % [origin, life])
	lines.append("[b]VOXEL[/b]  id %s    visual %s" % [str(s.get("voxel_id", "")), str(s.get("visual_id", ""))])
	lines.append("[b]HEIGHT[/b]  surf %.2f  walk %.2f  Δh %.2f" % [
		float(s.get("surface_height", 0.0)), float(s.get("walkable_height", 0.0)),
		float(s.get("height_delta", 0.0))
	])
	if bool(s.get("has_ramp", false)):
		var ramp: Dictionary = s.get("ramp", {})
		var rdir = ramp.get("dir", Vector2i.ZERO)
		var kind := "landing"
		if bool(ramp.get("approach", false)):
			kind = "approach"
		elif bool(ramp.get("corner", false)):
			kind = "corner"
		lines.append("[b]RAMP[/b]  %s  dir %s" % [kind, str(rdir)])
	else:
		lines.append("[b]RAMP[/b]  none")
	var covered: bool = bool(s.get("column_mesh_covered", false))
	lines.append("[b]MESH[/b]  %s  faces %s" % [
		"covered" if covered else "HOLE", str(s.get("column_face_codes", []))
	])
	lines.append("[b]COLLIDE[/b]  %s  %s" % [
		str(s.get("collision_kind", "?")),
		"step" if bool(s.get("interactable", false)) else "blocked-input"
	])
	var build_id := str(s.get("build_id", ""))
	var n_wo: int = int(s.get("structure_count", 0))
	var authored := str(s.get("visual_id", ""))
	if build_id != "" or n_wo > 0:
		lines.append("[b]FEATURE[/b]  %s  WorldObject %s  authored %s" % [
			build_id if build_id != "" else "—",
			"yes" if n_wo == 1 else str(n_wo),
			authored
		])
		lines.append("        yaw %.2f  visual %.2f" % [
			float(s.get("orientation_yaw", 0.0)), float(s.get("visual_yaw", 0.0))
		])
	else:
		var plant := str(s.get("plant_id", ""))
		if plant != "":
			lines.append("[b]FEATURE[/b]  plant %s" % plant)
		else:
			lines.append("[b]FEATURE[/b]  none")
	if float(s.get("water_level", 0.0)) > 0.01 or bool(s.get("is_water", false)):
		lines.append("[b]WATER[/b]  level %.2f" % float(s.get("water_level", 0.0)))
	if bool(s.get("has_crystal", false)):
		lines.append("[b]CRYSTAL[/b]  depth %.2f" % float(s.get("crystal_depth", 0.0)))
	_label.text = "\n".join(lines)


func _update_marker() -> void:
	if _marker == null or not is_instance_valid(_marker):
		return
	var s: Dictionary = last_snapshot
	if not bool(s.get("ok", false)):
		_marker.visible = false
		return
	_marker.visible = true
	var p: Vector3 = s.get("world_pos", Vector3.ZERO)
	_marker.global_position = p


func _draw_overlays() -> void:
	if _im == null:
		return
	_im.clear_surfaces()
	var player = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("get_voxel_position"):
		return
	var pv: Vector3 = player.get_voxel_position()
	var pcx := int(floor(pv.x / float(_ChunkData.SIZE)))
	var pcz := int(floor(pv.z / float(_ChunkData.SIZE)))
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	if bool(toggles.get("chunk_boundaries", false)):
		_chunk_box(pcx, pcz, Color(1, 0.85, 0.2, 1))
	if bool(toggles.get("voxel_boundaries", false)) and last_snapshot.get("ok", false):
		var wx := int(last_snapshot.get("wx", 0))
		var wz := int(last_snapshot.get("wz", 0))
		var y0 := float(last_snapshot.get("surface_height", 0.0))
		var y1 := float(last_snapshot.get("walkable_height", y0 + 1.0))
		_column_box(wx, wz, y0, y1, Color(0.3, 1, 0.4, 1))
	if bool(toggles.get("terrain_height", false)) and last_snapshot.get("ok", false):
		var th: float = float(last_snapshot.get("surface_height", 0.0))
		var twx := int(last_snapshot.get("wx", 0))
		var twz := int(last_snapshot.get("wz", 0))
		_column_box(twx, twz, th, th + 0.06, Color(1, 0.55, 0.15, 1))
	if bool(toggles.get("walkable_surface", false)) and last_snapshot.get("ok", false):
		var p: Vector3 = last_snapshot.get("world_pos", Vector3.ZERO)
		var half: float = _WorldVisualCoords.voxel_scale() * 0.4
		_im.surface_set_color(Color(0.2, 0.6, 1, 1))
		_im.surface_add_vertex(p + Vector3(-half, 0.02, -half))
		_im.surface_add_vertex(p + Vector3(half, 0.02, half))
		_im.surface_add_vertex(p + Vector3(half, 0.02, -half))
		_im.surface_add_vertex(p + Vector3(-half, 0.02, half))
	if bool(toggles.get("mesh_bounds", false)):
		var mb: Dictionary = last_snapshot.get("mesh_bounds", {})
		_aabb_lines(mb, Color(1, 0.4, 0.9, 1))
	if bool(toggles.get("water_cells", false)):
		_scan_neighbors(int(floor(pv.x)), int(floor(pv.z)), Color(0.2, 0.5, 1, 1), "is_water")
	if bool(toggles.get("crystal_cells", false)):
		_scan_neighbors(int(floor(pv.x)), int(floor(pv.z)), Color(0.8, 0.3, 1, 1), "has_crystal")
	if bool(toggles.get("feature_anchors", false)):
		_scan_neighbors(int(floor(pv.x)), int(floor(pv.z)), Color(1, 0.7, 0.2, 1), "feature")
	_im.surface_end()


func _scan_neighbors(ox: int, oz: int, color: Color, kind: String) -> void:
	var tree := get_tree()
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var snap: Dictionary = _LiveWorldQuery.inspect_cell(tree, ox + dx, oz + dz)
			var hit := false
			if kind == "is_water":
				hit = bool(snap.get("is_water", false))
			elif kind == "has_crystal":
				hit = bool(snap.get("has_crystal", false))
			elif kind == "feature":
				hit = not (snap.get("feature", {}) as Dictionary).is_empty()
			if hit:
				var y := float(snap.get("walkable_height", 0.0))
				_column_box(ox + dx, oz + dz, y, y + 0.15, color)


func _column_box(wx: int, wz: int, y0: float, y1: float, color: Color) -> void:
	var a: AABB = _WorldVisualCoords.cell_aabb(wx, y0, wz, y1)
	_box_lines(a.position.x, a.position.y, a.position.z,
		a.position.x + a.size.x, a.position.y + a.size.y, a.position.z + a.size.z, color)


func _chunk_box(cx: int, cz: int, color: Color) -> void:
	var a: AABB = _WorldVisualCoords.chunk_aabb(cx, cz)
	_box_lines(a.position.x, a.position.y, a.position.z,
		a.position.x + a.size.x, a.position.y + a.size.y, a.position.z + a.size.z, color)


func _aabb_lines(mb: Dictionary, color: Color) -> void:
	var pos: Array = mb.get("pos", [0, 0, 0])
	var sz: Array = mb.get("size", [0, 0, 0])
	if float(sz[0]) + float(sz[1]) + float(sz[2]) <= 0.01:
		return
	_box_lines(float(pos[0]), float(pos[1]), float(pos[2]),
		float(pos[0]) + float(sz[0]), float(pos[1]) + float(sz[1]), float(pos[2]) + float(sz[2]), color)


func _box_lines(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, color: Color) -> void:
	_im.surface_set_color(color)
	var pts := [
		Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1),
		Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1),
	]
	var edges := [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
	for i in range(0, edges.size(), 2):
		_im.surface_add_vertex(pts[edges[i]])
		_im.surface_add_vertex(pts[edges[i + 1]])
