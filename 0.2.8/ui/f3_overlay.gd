extends CanvasLayer

const _ChunkData = preload("res://chunks/chunk_data.gd")

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
	set_process(false)


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
	_text = "FPS %d\npos %.2f %.2f %.2f\nchunk %d %d" % [
		Engine.get_frames_per_second(),
		pos.x, pos.y, pos.z,
		chunk.x, chunk.y,
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
