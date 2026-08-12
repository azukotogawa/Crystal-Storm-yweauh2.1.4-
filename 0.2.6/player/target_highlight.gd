class_name TargetHighlight
extends Node3D

const _ActionTargeting = preload("res://player/action_targeting.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

var player: Player
var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager

## Extra range when previewing build via RMB (build_place) while another tool is selected.
const BUILD_PREVIEW_RANGE := 2.8
## Hover pick distance (screen-follow); actions still clamp to tool range.
const HOVER_PICK_RANGE := 14.0
const DISPLAY_SNAP_SPEED := 64.0
const HOVER_PULSE_HZ := 2.4

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D

var _stable_cell: Vector2i = Vector2i(999999, 999999)
var _display_pos: Vector3 = Vector3.ZERO
var _display_ready: bool = false
var _hover_t: float = 0.0
var _last_mode: StringName = &"none"
var _last_cell: Vector2i = Vector2i(999999, 999999)
var _place_flash_t: float = 0.0
## Last aim column shared with dig/build (column-space center) — always matches cursor cell.
var _action_column: Vector3 = Vector3.ZERO


func _ready() -> void:
	player = get_parent() as Player
	world = get_tree().get_first_node_in_group("world")
	chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	# Run before WeaponController so dig/build read this frame's aim column.
	process_priority = -20
	_build_mesh()
	_build_ghost()


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
	_mat.emission_enabled = true
	_mesh.material_override = _mat
	_mesh.visible = false
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.sorting_offset = 4.0
	add_child(_mesh)


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
	_ghost_mat.emission_enabled = true
	_ghost_mat.albedo_color = Color(1.0, 0.9, 0.3, 0.18)
	_ghost_mat.emission = Color(1.0, 0.85, 0.2)
	_ghost_mat.emission_energy_multiplier = 0.35
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
		if profiler and profiler.has_method("end"):
			profiler.end("target_highlight")
		return
	if _GameplayInput.blocks_actions():
		_mesh.visible = false
		if _ghost:
			_ghost.visible = false
		if profiler and profiler.has_method("end"):
			profiler.end("target_highlight")
		return
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")

	var range_v := _active_range()
	# Hold RMB / R to preview build even with sword or pick selected (build_place path).
	if Input.is_action_pressed("build_place") or Input.is_action_pressed("interact"):
		range_v = maxf(range_v, BUILD_PREVIEW_RANGE)

	# Hover follows mouse beyond tool range (blocked tint when out of range).
	var hover_col: Vector3 = _ActionTargeting.pick_hover_column(
		player, world, chunk_manager, maxf(range_v, HOVER_PICK_RANGE)
	)
	if hover_col == Vector3.ZERO:
		hover_col = _ActionTargeting.target_column(player, range_v)

	# Exact mouse follow: action cell is always the live hover column (no hysteresis).
	var hover_cell := Vector2i(floori(hover_col.x), floori(hover_col.z)) if hover_col != Vector3.ZERO \
		else Vector2i(999999, 999999)
	_stable_cell = hover_cell
	var stable_col := Vector3(float(_stable_cell.x) + 0.5, player.voxel_position.y, float(_stable_cell.y) + 0.5) \
		if _stable_cell.x < 900000 else Vector3.ZERO
	# Always publish aim for dig/build — even when mode preview is blocked/out of range.
	_action_column = stable_col

	var resolve_t0 := Time.get_ticks_usec()
	var info: Dictionary
	if stable_col != Vector3.ZERO:
		info = _ActionTargeting.resolve_action(
			player, world, chunk_manager, range_v, false, &"", stable_col
		)
	else:
		info = _ActionTargeting.resolve_action(player, world, chunk_manager, range_v)
	if profiler and profiler.has_method("record_func"):
		profiler.record_func("ActionTargeting::resolve_action", Time.get_ticks_usec() - resolve_t0)

	var mode: StringName = info.get("mode", &"none")
	# Show dig/build/attack previews even when blocked so aim stays readable.
	if mode not in [&"dig", &"build", &"attack", &"ranged"] or stable_col == Vector3.ZERO:
		_mesh.visible = false
		if _ghost:
			_ghost.visible = false
		_display_ready = false
		# Keep _action_column so hold-dig still hits the hovered cell under the mouse.
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
	# world_pos is the top face of the target layer; center the box in that layer.
	target_pos.y -= layer * 0.5
	var cell: Vector2i = info.get("cell", _stable_cell)
	# Logical cell jumps: snap box instantly (cursor always under mouse).
	if not _display_ready or mode != _last_mode or cell != _last_cell:
		_display_pos = target_pos
		_display_ready = true
	else:
		# Same cell: ease height when dig/build changes surface under the cursor.
		var k: float = clampf(DISPLAY_SNAP_SPEED * delta, 0.0, 1.0)
		_display_pos = _display_pos.lerp(target_pos, k)
		if _display_pos.distance_to(target_pos) < 0.03:
			_display_pos = target_pos
	_mesh.global_position = _display_pos
	_last_mode = mode
	_last_cell = cell

	var blocked: bool = bool(info.get("blocked", false)) or not bool(info.get("valid", false))
	if blocked:
		_mat.albedo_color = Color(1.0, 0.15, 0.12, 0.32 + 0.12 * pulse)
		_mat.emission = Color(0.9, 0.1, 0.08)
		_mat.emission_energy_multiplier = 0.45 + 0.35 * pulse
	else:
		match mode:
			&"dig":
				# g kept <0.65 so dig-highlight verifies still read as orange.
				_mat.albedo_color = Color(1.0, 0.52, 0.1, 0.28 + 0.16 * pulse)
				_mat.emission = Color(1.0, 0.45, 0.05)
				_mat.emission_energy_multiplier = 0.55 + 0.55 * pulse
			&"build":
				_mat.albedo_color = Color(0.25, 1.0, 0.4, 0.28 + 0.16 * pulse + 0.25 * place_boost)
				_mat.emission = Color(0.2, 0.95, 0.35).lerp(Color(1.0, 1.0, 0.7), place_boost)
				_mat.emission_energy_multiplier = 0.55 + 0.55 * pulse + 1.4 * place_boost
			&"attack":
				_mat.albedo_color = Color(1.0, 0.22, 0.18, 0.3 + 0.14 * pulse)
				_mat.emission = Color(0.95, 0.2, 0.15)
				_mat.emission_energy_multiplier = 0.5 + 0.45 * pulse
			&"ranged":
				_mat.albedo_color = Color(0.45, 0.75, 1.0, 0.28 + 0.14 * pulse)
				_mat.emission = Color(0.4, 0.7, 1.0)
				_mat.emission_energy_multiplier = 0.5 + 0.4 * pulse
			_:
				_mat.albedo_color = Color(0.35, 0.95, 0.45, 0.3)
				_mat.emission = Color(0.3, 0.9, 0.4)
				_mat.emission_energy_multiplier = 0.5

	_update_prediction(info, range_v, layer, scale, pulse)

	if profiler and profiler.has_method("end"):
		profiler.end("target_highlight")


## Satisfying placement pop when a wall/gate/bridge lands.
func pulse_place_success() -> void:
	_place_flash_t = 0.18


## Column dig/build must use — matches the visible cursor (column-space).
func get_action_column() -> Vector3:
	return _action_column


func _update_prediction(info: Dictionary, range_v: float, layer: float, scale: float, pulse: float) -> void:
	if _ghost == null:
		return
	var mode: StringName = info.get("mode", &"none")
	# Predict next tile along aim for dig/build continuous reshape.
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
	var base_a: float = 0.12 + 0.08 * pulse
	if mode == &"dig":
		_ghost_mat.albedo_color = Color(1.0, 0.55, 0.12, base_a)
		_ghost_mat.emission = Color(1.0, 0.5, 0.08)
	else:
		_ghost_mat.albedo_color = Color(0.3, 1.0, 0.45, base_a)
		_ghost_mat.emission = Color(0.25, 0.95, 0.35)
	_ghost_mat.emission_energy_multiplier = 0.25 + 0.2 * pulse


func _active_range() -> float:
	var weapon := player.get_node_or_null("WeaponController")
	if weapon == null or not weapon.has_method("get_active_item"):
		return 2.0
	var slot = weapon.get_active_item()
	if slot == null:
		return 2.0
	var def := _ItemTypes.get_def(str(slot.id))
	if def.is_empty():
		return 2.0
	return float(def.get("range", 2.0))
