extends CanvasLayer

const _ChunkData = preload("res://chunks/chunk_data.gd")
const _HudLayout = preload("res://config/hud_layout.gd")

@onready var _readout: Label = $Readout

var _ticks := 0
var _text := ""


func _enter_tree() -> void:
	add_to_group("f3_overlay")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	if _readout:
		_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_readout.process_mode = Node.PROCESS_MODE_ALWAYS
		_readout.add_theme_font_size_override("font_size", 14)
		_readout.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 0.95))
		_readout.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.9))
		_readout.add_theme_constant_override("outline_size", 4)
		_place_readout()
	set_process(false)


func _place_readout() -> void:
	if _readout == null:
		return
	var layout := _HudLayout.load_active()
	var spot := layout.debug_position()
	_readout.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_readout.position = spot
	_readout.size = Vector2(layout.debug_width, layout.debug_height)
	_readout.offset_left = spot.x
	_readout.offset_top = spot.y
	_readout.offset_right = spot.x + layout.debug_width
	_readout.offset_bottom = spot.y + layout.debug_height


func is_overlay_visible() -> bool:
	return visible


func overlay_text() -> String:
	return _text


func toggle_overlay() -> bool:
	set_overlay_visible(not visible)
	return visible


func set_overlay_visible(show_overlay: bool) -> void:
	visible = show_overlay
	set_process(show_overlay)
	if show_overlay:
		_refresh()


func _process(_delta: float) -> void:
	_ticks += 1
	if _ticks % 8 != 0:
		return
	_refresh()


func _refresh() -> void:
	if _readout == null:
		return
	var player := _player()
	var pos := _world_position(player)
	var column := _column(player, pos)
	var chunk := _chunk_for(column)
	var crystal := _crystal_progress()
	_text = "FPS %d\npos %.2f %.2f %.2f\nchunk %d %d\n%s\n%s\n%s\n%s" % [
		Engine.get_frames_per_second(),
		pos.x, pos.y, pos.z,
		chunk.x, chunk.y,
		_crystal_line(crystal),
		_boss_line(crystal),
		_xp_line(),
		_enemy_line(),
	]
	_readout.text = _text


func _player() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("player")


func _world_position(player: Node) -> Vector3:
	if player is Node3D:
		return (player as Node3D).global_position
	return Vector3.ZERO


func _column(player: Node, world_pos: Vector3) -> Vector2i:
	if player and player.has_method("get_voxel_position"):
		var voxel: Vector3 = player.get_voxel_position()
		return Vector2i(floori(voxel.x), floori(voxel.z))
	return Vector2i(floori(world_pos.x), floori(world_pos.z))


func _chunk_for(column: Vector2i) -> Vector2i:
	var size := maxi(_ChunkData.SIZE, 1)
	return Vector2i(
		int(floor(float(column.x) / float(size))),
		int(floor(float(column.y) / float(size)))
	)


func _crystal_progress() -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {}
	var crystal := tree.get_first_node_in_group("crystal_manager")
	if crystal == null or not crystal.has_method("get_spawn_progress"):
		return {}
	var progress: Variant = crystal.get_spawn_progress()
	if progress is Dictionary:
		return progress
	return {}


func _crystal_line(progress: Dictionary) -> String:
	if progress.is_empty() or not progress.has("crystal_health"):
		return "crystal —"
	var health := int(round(float(progress.get("crystal_health", 0.0))))
	var maximum := int(round(float(progress.get("crystal_max_health", 0.0))))
	return "crystal %d/%d" % [health, maximum]


func _boss_line(progress: Dictionary) -> String:
	if progress.is_empty():
		return "boss —"
	return "boss %s" % _boss_state(progress)


func _boss_state(progress: Dictionary) -> String:
	if bool(progress.get("warden_alive", false)):
		return "warden"
	if bool(progress.get("boss_spawned", false)):
		return "spawned"
	if bool(progress.get("boss_sealed", false)):
		return "sealed"
	if bool(progress.get("boss_active", false)):
		return "active"
	return "none"


func _xp_line() -> String:
	var progress := _progression()
	if progress == null:
		return "xp —"
	return "xp %d lv %d" % [int(progress.get("xp")), int(progress.get("level"))]


func _progression() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var service := tree.get_first_node_in_group("progression_service")
	if service == null:
		return null
	if service.get("xp") == null or service.get("level") == null:
		return null
	return service


func _enemy_line() -> String:
	var count := _enemy_count()
	if count < 0:
		return "enemies —"
	return "enemies %d" % count


func _enemy_count() -> int:
	var tree := get_tree()
	if tree == null:
		return -1
	var spawner := tree.get_first_node_in_group("crystal_enemy_spawner")
	if spawner != null and spawner.has_method("get_active_count"):
		return int(spawner.get_active_count())
	if tree.get_node_count_in_group("crystal_enemy") == 0 and spawner == null:
		return -1
	var alive := 0
	for node in tree.get_nodes_in_group("crystal_enemy"):
		if is_instance_valid(node):
			alive += 1
	return alive
