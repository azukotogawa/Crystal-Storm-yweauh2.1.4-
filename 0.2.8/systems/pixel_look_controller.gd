extends Node
## Optional full-screen low-res nearest upscale. Install only when enabled.
## Renders the existing World3D through a low-res SubViewport camera (no world reparent).
## HUD CanvasLayers stay on the root at full res.

const _PixelLook = preload("res://helpers/pixel_look.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")

const BLIT_SHADER_PATH := "res://shaders/pixel_look_blit.gdshader"

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
var _proxy_cam: Camera3D = null
var _source_cam: Camera3D = null
var _subpixel: Vector2 = Vector2.ZERO
var _installed: bool = false
var _root_disable_3d_prev: bool = false


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
	ctrl.process_priority = -50
	game.add_child(ctrl)
	ctrl.call_deferred("install", game)
	return ctrl


func install(game: Node) -> void:
	if _installed or game == null:
		return
	_game = game
	_installed = true
	print("PIXEL_LOOK install begin height=%d" % internal_height)
	_build_viewport()
	_build_proxy_camera()
	_build_blit()
	_resize_to_window()
	_disable_root_3d()
	var root_vp := get_viewport()
	if root_vp != null and not root_vp.size_changed.is_connected(_on_root_size_changed):
		root_vp.size_changed.connect(_on_root_size_changed)
	set_process(true)
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


func get_content_parent() -> Node:
	## World stays on the game root; late-created 3D nodes should too.
	return _game if _game != null else self


func _build_viewport() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "PixelLookLayer"
	_layer.layer = 0
	_game.add_child(_layer)

	_container = SubViewportContainer.new()
	_container.name = "PixelViewportContainer"
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.stretch = false
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.modulate = Color(1, 1, 1, 0)
	_layer.add_child(_container)

	_viewport = SubViewport.new()
	_viewport.name = "PixelWorld"
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.audio_listener_enable_3d = true
	_viewport.own_world_3d = false
	var root_vp := _game.get_viewport()
	if root_vp != null:
		_viewport.world_3d = root_vp.world_3d
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.scaling_3d_scale = 1.0
	_container.add_child(_viewport)
	print("PIXEL_LOOK viewport ready size=%s" % str(_viewport.size))


func _build_proxy_camera() -> void:
	_proxy_cam = Camera3D.new()
	_proxy_cam.name = "PixelProxyCamera"
	_proxy_cam.current = true
	_viewport.add_child(_proxy_cam)
	_source_cam = _find_source_camera()
	if _source_cam != null:
		_copy_camera_settings(_source_cam, _proxy_cam)
		# Root camera must not remain current or it fights the proxy.
		_source_cam.current = false


func _disable_root_3d() -> void:
	var root_vp := _game.get_viewport()
	if root_vp == null:
		return
	_root_disable_3d_prev = root_vp.disable_3d
	root_vp.disable_3d = true


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
	if not _installed or _viewport == null or _proxy_cam == null:
		return
	if _source_cam == null or not is_instance_valid(_source_cam):
		_source_cam = _find_source_camera()
	if _source_cam == null:
		_subpixel = Vector2.ZERO
		return
	_copy_camera_settings(_source_cam, _proxy_cam)
	_source_cam.current = false
	_proxy_cam.current = true
	_snap_proxy_camera()
	if _blit_mat != null:
		_blit_mat.set_shader_parameter("subpixel", _subpixel)
		_blit_mat.set_shader_parameter("world_tex", _viewport.get_texture())


func _copy_camera_settings(src: Camera3D, dst: Camera3D) -> void:
	dst.projection = src.projection
	dst.fov = src.fov
	dst.size = src.size
	dst.near = src.near
	dst.far = src.far
	dst.keep_aspect = src.keep_aspect
	dst.cull_mask = src.cull_mask
	dst.environment = src.environment
	dst.attributes = src.attributes
	dst.global_transform = src.global_transform


func _snap_proxy_camera() -> void:
	var ortho_size: float = 16.0
	if _proxy_cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		ortho_size = maxf(_proxy_cam.size, 0.01)
	else:
		var dist: float = 50.0
		ortho_size = maxf(2.0 * dist * tan(deg_to_rad(_proxy_cam.fov) * 0.5), 0.01)
	var result: Dictionary = _PixelLook.snap_camera_position(
		_proxy_cam.global_position,
		_proxy_cam.global_transform.basis,
		ortho_size,
		_viewport.size.y
	)
	_proxy_cam.global_position = result["snapped"]
	_subpixel = result["subpixel"]


func _find_source_camera() -> Camera3D:
	var cam := get_tree().get_first_node_in_group("camera") as Camera3D
	if cam != null:
		return cam
	var player := get_tree().get_first_node_in_group("player")
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
