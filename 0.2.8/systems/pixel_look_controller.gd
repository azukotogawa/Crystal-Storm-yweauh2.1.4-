extends Node
## Optional full-screen low-res nearest upscale. Install only when enabled.
## 3D world renders into a SubViewport; HUD CanvasLayers stay on the root at full res.

const _PixelLook = preload("res://helpers/pixel_look.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")

const BLIT_SHADER_PATH := "res://shaders/pixel_look_blit.gdshader"

## Node names under Game that stay on the root (UI / services), not moved into the SubViewport.
const KEEP_ON_ROOT := {
	"CompositionRoot": true,
	"SpatialQueryService": true,
	"ProgressionService": true,
	"SkillService": true,
	"ConfigService": true,
	"PerformanceService": true,
	"GameVisualRegistry": true,
	"GameManager": true,
	"SaveGameService": true,
	"CanvasLayer": true,
	"LoadingLayer": true,
	"LiveWorldInspector": true,
	"DevToolsCoordinator": true,
	"PauseMenu": true,
	"SkillTree": true,
	"F3Overlay": true,
	"PixelLookController": true,
	"PixelLookLayer": true,
	"DeveloperAssistant": true,
}

var enabled: bool = false
var internal_height: int = _PixelLook.DEFAULT_HEIGHT
var banding: bool = false
var outline: bool = false

var _game: Node = null
var _viewport: SubViewport = null
var _blit: ColorRect = null
var _blit_mat: ShaderMaterial = null
var _layer: CanvasLayer = null
var _container: SubViewportContainer = null
var _subpixel: Vector2 = Vector2.ZERO
var _installed: bool = false
var _camera: Camera3D = null
var _reparent_done: bool = false


static func maybe_install(game: Node) -> Node:
	if game == null:
		return null
	if game.get_node_or_null("PixelLookController") != null:
		return game.get_node("PixelLookController")
	var cfg: Dictionary = {}
	if _PlayerSettings != null:
		cfg = _PlayerSettings.load_settings()
	var settings: Dictionary = _PixelLook.resolve_settings(cfg)
	if not bool(settings.get("enabled", false)):
		return null
	var ctrl := Node.new()
	ctrl.name = "PixelLookController"
	ctrl.set_script(load("res://systems/pixel_look_controller.gd"))
	ctrl.enabled = true
	ctrl.internal_height = int(settings.get("height", _PixelLook.DEFAULT_HEIGHT))
	ctrl.banding = bool(settings.get("banding", false))
	ctrl.outline = bool(settings.get("outline", false))
	# Higher process_priority runs first; negative runs after typical camera controllers.
	ctrl.process_priority = -50
	game.add_child(ctrl)
	# Defer heavy reparent so boot_async / SceneTree scripts can finish their current frame.
	ctrl.call_deferred("install", game)
	return ctrl


func install(game: Node) -> void:
	if _installed or game == null:
		return
	_game = game
	_installed = true
	print("PIXEL_LOOK install begin height=%d" % internal_height)
	_build_viewport()
	print("PIXEL_LOOK viewport ready size=%s" % str(_viewport.size if _viewport else Vector2i.ZERO))
	_build_blit()
	_resize_to_window()
	# Reparent next frame so SubViewport has a size/texture before absorbing the world.
	call_deferred("_reparent_world")
	var root_vp := get_viewport()
	if root_vp != null and not root_vp.size_changed.is_connected(_on_root_size_changed):
		root_vp.size_changed.connect(_on_root_size_changed)
	set_process(true)


func get_content_parent() -> Node:
	if _viewport != null:
		return _viewport
	return _game


func _build_viewport() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "PixelLookLayer"
	_layer.layer = 0
	_game.add_child(_layer)

	_container = SubViewportContainer.new()
	_container.name = "PixelViewportContainer"
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.stretch = false
	_container.mouse_filter = Control.MOUSE_FILTER_STOP
	# Hide the container's own blit; ColorRect+shader does nearest + subpixel.
	_container.modulate = Color(1, 1, 1, 0)
	_layer.add_child(_container)

	_viewport = SubViewport.new()
	_viewport.name = "PixelWorld"
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = true
	_viewport.gui_disable_input = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.audio_listener_enable_3d = true
	# Share the root World3D so physics/navigation RIDs created during boot stay valid.
	_viewport.own_world_3d = false
	_viewport.world_3d = _game.get_viewport().world_3d
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.scaling_3d_scale = 1.0
	_container.add_child(_viewport)


func _reparent_world() -> void:
	if _reparent_done or _viewport == null or _game == null:
		return
	_reparent_done = true
	var to_move: Array[Node] = []
	for child in _game.get_children():
		if child == self or child == _layer:
			continue
		if child is CanvasLayer:
			continue
		if KEEP_ON_ROOT.has(child.name):
			continue
		to_move.append(child)
	print("PIXEL_LOOK reparent count=%d" % to_move.size())
	for child in to_move:
		var was_current := false
		if child is Camera3D:
			was_current = (child as Camera3D).current
		_game.remove_child(child)
		_viewport.add_child(child)
		if child is Camera3D and was_current:
			(child as Camera3D).current = true
	# Player camera often nested — force current on whatever camera we find.
	var cam := _find_camera()
	if cam != null:
		cam.current = true
		_camera = cam
	_resize_to_window()
	_apply_blit_uniforms()
	print(
		"PIXEL_LOOK on height=%d size=%sx%s banding=%s outline=%s"
		% [
			internal_height,
			_viewport.size.x if _viewport else 0,
			_viewport.size.y if _viewport else 0,
			str(banding),
			str(outline),
		]
	)


func _build_blit() -> void:
	_blit = ColorRect.new()
	_blit.name = "PixelBlit"
	_blit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = load(BLIT_SHADER_PATH) as Shader
	_blit_mat = ShaderMaterial.new()
	_blit_mat.shader = shader
	_blit.material = _blit_mat
	_layer.add_child(_blit)
	_apply_blit_uniforms()


func _apply_blit_uniforms() -> void:
	if _blit_mat == null or _viewport == null:
		return
	_blit_mat.set_shader_parameter("world_tex", _viewport.get_texture())
	var sz: Vector2 = Vector2(_viewport.size)
	var px: Vector2 = Vector2(1.0 / maxf(sz.x, 1.0), 1.0 / maxf(sz.y, 1.0))
	_blit_mat.set_shader_parameter("tex_pixel_size", px)
	_blit_mat.set_shader_parameter("subpixel", _subpixel)
	_blit_mat.set_shader_parameter("banding_enabled", banding)
	_blit_mat.set_shader_parameter("outline_enabled", outline)


func _on_root_size_changed() -> void:
	_resize_to_window()


func _resize_to_window() -> void:
	if _viewport == null:
		return
	var win: Vector2i = get_viewport().get_visible_rect().size
	if win.x < 2 or win.y < 2:
		win = DisplayServer.window_get_size()
	var target: Vector2i = _PixelLook.internal_size(win, internal_height)
	if _viewport.size != target:
		_viewport.size = target
	_apply_blit_uniforms()


func _process(_delta: float) -> void:
	if not _installed or _viewport == null or not _reparent_done:
		return
	_snap_camera()
	if _blit_mat != null:
		_blit_mat.set_shader_parameter("subpixel", _subpixel)
		_blit_mat.set_shader_parameter("world_tex", _viewport.get_texture())


func _snap_camera() -> void:
	if _camera == null or not is_instance_valid(_camera):
		_camera = _find_camera()
	if _camera == null:
		_subpixel = Vector2.ZERO
		return
	var ortho_size: float = 16.0
	if _camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		ortho_size = maxf(_camera.size, 0.01)
	else:
		var dist: float = 50.0
		ortho_size = maxf(2.0 * dist * tan(deg_to_rad(_camera.fov) * 0.5), 0.01)
	var result: Dictionary = _PixelLook.snap_camera_position(
		_camera.global_position,
		_camera.global_transform.basis,
		ortho_size,
		internal_height if _viewport == null else _viewport.size.y
	)
	_camera.global_position = result["snapped"]
	_subpixel = result["subpixel"]


func _find_camera() -> Camera3D:
	if _viewport == null:
		return null
	var cam := _viewport.get_camera_3d()
	if cam != null:
		return cam
	var player := _viewport.get_node_or_null("Player")
	if player != null:
		var c = player.get_node_or_null("Camera3D")
		if c is Camera3D:
			return c as Camera3D
	return null


func get_world_viewport() -> SubViewport:
	return _viewport


func get_internal_size() -> Vector2i:
	if _viewport == null:
		return Vector2i.ZERO
	return _viewport.size
