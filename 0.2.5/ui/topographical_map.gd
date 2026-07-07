extends Control

const _TopographicalMapConfig = preload("res://config/topographical_map_config.gd")
const _TopographicalMapBuilder = preload("res://systems/topographical_map_builder.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")

@export var map_config: Resource

var _minimap_rect: TextureRect
var _player_dot: ColorRect
var _fullscreen_panel: PanelContainer
var _fullscreen_rect: TextureRect
var _fullscreen_player_dot: ColorRect

var _world: InfiniteNoiseWorld
var _crystal: CrystalManager
var _player: Node3D
var _fullscreen_open: bool = false
var _rebuild_timer: float = 0.0
var _last_center := Vector2i.ZERO
var _minimap_tex: ImageTexture
var _full_tex: ImageTexture
var _minimap_enabled: bool = true
var _fullscreen_map_enabled: bool = true


func _map_cfg():
	if map_config == null or not map_config is _TopographicalMapConfig:
		map_config = _TopographicalMapConfig.create_default()
	return map_config


func _enter_tree() -> void:
	add_to_group("topographical_map")


func _ready() -> void:
	_build_ui()
	set_process(true)
	call_deferred("_bind_scene")


func _bind_scene() -> void:
	_world = get_tree().get_first_node_in_group("world")
	_crystal = get_tree().get_first_node_in_group("crystal_manager")
	_player = get_tree().get_first_node_in_group("player")


func apply_performance_config(cfg) -> void:
	if cfg == null:
		return
	_minimap_enabled = bool(cfg.minimap_enabled)
	_fullscreen_map_enabled = bool(cfg.map_fullscreen_enabled)
	var mc = _map_cfg()
	mc.rebuild_interval_sec = float(cfg.map_rebuild_interval_sec)
	mc.minimap_size = int(cfg.minimap_pixel_size)
	mc.sample_stride = int(cfg.map_sample_stride)
	if _minimap_rect:
		_minimap_rect.visible = _minimap_enabled
		_minimap_rect.custom_minimum_size = Vector2(mc.minimap_size, mc.minimap_size)
	if not _minimap_enabled and _fullscreen_open:
		_fullscreen_open = false
		_fullscreen_panel.visible = false


func _build_ui() -> void:
	var cfg = _map_cfg()
	_minimap_rect = TextureRect.new()
	_minimap_rect.custom_minimum_size = Vector2(cfg.minimap_size, cfg.minimap_size)
	_minimap_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_minimap_rect.position = Vector2(12, 12)
	add_child(_minimap_rect)

	_player_dot = ColorRect.new()
	_player_dot.color = cfg.color_player
	_player_dot.size = Vector2(5, 5)
	_player_dot.position = Vector2(cfg.minimap_size * 0.5 - 2, cfg.minimap_size * 0.5 - 2)
	_minimap_rect.add_child(_player_dot)

	_fullscreen_panel = PanelContainer.new()
	_fullscreen_panel.visible = false
	_fullscreen_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fullscreen_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_fullscreen_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Topographical Map (M to close)"
	vbox.add_child(title)

	_fullscreen_rect = TextureRect.new()
	_fullscreen_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fullscreen_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fullscreen_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_fullscreen_rect)

	_fullscreen_player_dot = ColorRect.new()
	_fullscreen_player_dot.color = cfg.color_player
	_fullscreen_player_dot.size = Vector2(8, 8)
	_fullscreen_rect.add_child(_fullscreen_player_dot)


func _process(delta: float) -> void:
	if _world == null:
		_bind_scene()
		return

	if Input.is_action_just_pressed("toggle_map"):
		if not _fullscreen_map_enabled:
			return
		_fullscreen_open = not _fullscreen_open
		_fullscreen_panel.visible = _fullscreen_open
		if _fullscreen_open:
			_rebuild_maps(true)

	if not _minimap_enabled and not _fullscreen_open:
		return

	_rebuild_timer -= delta
	var center := _player_center_cell()
	var cfg = _map_cfg()
	if _rebuild_timer <= 0.0 or center.distance_to(_last_center) >= cfg.rebuild_move_threshold_cells:
		_rebuild_timer = cfg.rebuild_interval_sec
		_rebuild_maps(_fullscreen_open)
		_last_center = center


func _player_center_cell() -> Vector2i:
	if _player == null:
		return Vector2i.ZERO
	if _player.has_method("get_voxel_position"):
		return _EntityNavigation.column_pos(_player.get_voxel_position())
	return _EntityNavigation.column_pos(_player.global_position)


func _rebuild_maps(include_full: bool) -> void:
	var center := _player_center_cell()
	var cfg = _map_cfg()
	if _minimap_enabled and _minimap_rect:
		_minimap_tex = _TopographicalMapBuilder.build_local_map(_world, _crystal, center, cfg)
		_minimap_rect.texture = _minimap_tex
		_player_dot.position = Vector2(cfg.minimap_size * 0.5 - 2, cfg.minimap_size * 0.5 - 2)

	if include_full and _fullscreen_map_enabled:
		_full_tex = _TopographicalMapBuilder.build_full_map(_world, _crystal, center, cfg)
		_fullscreen_rect.texture = _full_tex
		var rel := Vector2(0.5, 0.5)
		_fullscreen_player_dot.position = Vector2(
			_fullscreen_rect.size.x * rel.x - 4,
			_fullscreen_rect.size.y * rel.y - 4
		)