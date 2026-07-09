# world_viewer.gd
# Fast, high-performance world DESIGN viewer for quick iteration on InfiniteNoiseWorld.
# Texture-driven (ImageTexture) instead of slow per-cell TileMap — excellent perf even when zoomed out.
# Multiple view modes focused on validating the current world design (biomes, rivers, valleys, height, carving).
# Especially useful after river system changes to confirm thin connected channels in proper valleys (not lakes).
#
# Controls (designed for fast design validation loops):
#   Drag (LMB/MMB) or WASD/Arrows (+Shift faster) : pan
#   Mouse wheel : zoom (in/out for detail vs macro)
#   R / + / - / Numpad+/- : change seed (instant regen of current view)
#   Space : random new seed
#   1-4 or M / Tab : cycle view modes (Composite is the main "does the world look good?" design view)
#   S : print detailed design snapshot + river quality hints to console
#   Mouse move : live inspector (biome, height, river strength, carve, etc.)
#
# The goal: easily see macro layout, biome balance, river placement/width/connectedness,
# valley carving, and height variety at a glance with snappy feedback.
#
# Note: This is a design/dev tool. The real game uses the 3D chunk system.
extends Node2D

@export var seed_value: int = 12349
@export var internal_res: int = 112
@export var quality_res: int = 320

var world: InfiniteNoiseWorld

var view_center := Vector2(0, 0)
var units_per_pixel := 4.0

var map_view: TextureRect
var map_image: Image
var map_texture: ImageTexture

enum ViewMode {
	COMPOSITE,
	BIOME,
	HEIGHT,
	RIVERS
}
var current_mode: ViewMode = ViewMode.COMPOSITE
var mode_names := ["COMPOSITE (design)", "BIOME", "HEIGHT + SLOPE", "RIVERS (thin mask)"]

var is_panning := false
var last_mouse_pos := Vector2.ZERO
var needs_regen := true

var last_regen_time_ms := 0
const REGEN_THROTTLE_MS := 45

var prev_view_center := Vector2.ZERO
var prev_units_per_pixel := 4.0

var _regen_thread: Thread = null
var _pending_image: Image = null
var _regen_mutex := Mutex.new()

var hud_label: Label
var inspector_label: Label
var mode_label: Label

const BASE_UNITS_PER_PIXEL := 4.0
const MIN_UNITS_PER_PIXEL := 0.6
const MAX_UNITS_PER_PIXEL := 28.0

func _ready():
	world = InfiniteNoiseWorld.new(seed_value)
	_create_map_view()
	_setup_debug_ui()
	
	if has_node("TileMapLayer"):
		$TileMapLayer.visible = false
	
	await get_tree().process_frame
	_regenerate(true)
	_update_hud()
	_print_world_stats()

func _create_map_view():
	if has_node("MapView"):
		map_view = $MapView
	else:
		map_view = TextureRect.new()
		map_view.name = "MapView"
		map_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		map_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(map_view)
	
	map_view.size = get_viewport_rect().size * 0.96
	map_view.position = Vector2(10, 10)
	map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_on_viewport_resized)

func _on_viewport_resized():
	if map_view:
		map_view.size = get_viewport_rect().size * 0.96
	needs_regen = true

func _setup_debug_ui():
	var canvas = CanvasLayer.new()
	canvas.name = "DebugCanvas"
	canvas.layer = 10
	add_child(canvas)
	
	hud_label = Label.new()
	hud_label.position = Vector2(12, 8)
	hud_label.add_theme_color_override("font_color", Color(1,1,1))
	hud_label.add_theme_font_size_override("font_size", 13)
	canvas.add_child(hud_label)
	
	inspector_label = Label.new()
	inspector_label.position = Vector2(12, 92)
	inspector_label.add_theme_color_override("font_color", Color(1,0.95,0.7))
	inspector_label.add_theme_font_size_override("font_size", 12)
	canvas.add_child(inspector_label)
	
	mode_label = Label.new()
	mode_label.position = Vector2(12, 58)
	mode_label.add_theme_color_override("font_color", Color(0.6,1,0.9))
	mode_label.add_theme_font_size_override("font_size", 12)
	canvas.add_child(mode_label)

func _process(_delta):
	var move_dir := Vector2.ZERO
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D): move_dir.x += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A): move_dir.x -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S): move_dir.y += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W): move_dir.y -= 1

	if move_dir.length() > 0:
		var speed := 420.0 * units_per_pixel
		if Input.is_key_pressed(KEY_SHIFT): speed *= 3.2
		view_center += move_dir.normalized() * speed * _delta
		needs_regen = true

	if needs_regen:
		_regenerate()
		needs_regen = false
	
	_update_hud()
	_update_inspector()

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			is_panning = event.pressed
			last_mouse_pos = event.position
			if not is_panning:
				needs_regen = true

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			units_per_pixel = max(MIN_UNITS_PER_PIXEL, units_per_pixel * 0.82)
			needs_regen = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			units_per_pixel = min(MAX_UNITS_PER_PIXEL, units_per_pixel * 1.22)
			needs_regen = true

	if event is InputEventMouseMotion and is_panning:
		view_center -= (event.position - last_mouse_pos) * units_per_pixel
		last_mouse_pos = event.position
		needs_regen = true

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R or event.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
			seed_value += 1
			_change_seed()
		elif event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			seed_value -= 1
			_change_seed()
		elif event.keycode == KEY_SPACE:
			seed_value = randi() % 1000000
			_change_seed()
		elif event.keycode == KEY_S:
			_print_world_stats()
		elif event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_M, KEY_TAB]:
			_cycle_view_mode()
		elif event.keycode == KEY_Q:
			_force_quality_render()

func _change_seed():
	world = InfiniteNoiseWorld.new(seed_value)
	_clear_caches()
	_regenerate(true)
	print("Regenerated with seed:", seed_value)

func _clear_caches():
	if world:
		world._surface_cache.clear()
		world._tile_cache.clear()
		world._biome_cache.clear()
		print("All caches cleared for fresh height/river computation")

func _cycle_view_mode():
	current_mode = (current_mode + 1) % ViewMode.size() as ViewMode
	_regenerate(true)
	_update_hud()

func _force_quality_render():
	var old_res = internal_res
	internal_res = quality_res
	
	# Force full recreation of image + texture
	map_image = null
	map_texture = null
	
	_regenerate(true)
	internal_res = old_res
	print("Quality render (", quality_res, " res)")

func _regenerate(force_full := false):
	if force_full:
		_clear_caches()  # force fresh heights + rivers
	if not map_view:
		return
		# Safety: ensure image matches current resolution
	var res = clamp(internal_res, 96, 512)
	if map_image == null or map_image.get_width() != res or map_image.get_height() != res:
		map_image = Image.create(res, res, false, Image.FORMAT_RGBA8)
		map_texture = null  # force new texture

	var now = Time.get_ticks_msec()
	if not force_full and is_panning and (now - last_regen_time_ms) < REGEN_THROTTLE_MS:
		return

	var img_w = res
	var img_h = res

	var need_new_image = (map_image == null or map_image.get_width() != img_w or map_image.get_height() != img_h)
	if need_new_image:
		map_image = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)

	var half_x = (img_w * units_per_pixel) * 0.5
	var half_y = (img_h * units_per_pixel) * 0.5
	var left = view_center.x - half_x
	var top = view_center.y - half_y

	if not need_new_image and not force_full and abs(units_per_pixel - prev_units_per_pixel) < 0.0001:
		var dx = (prev_view_center.x - view_center.x) / units_per_pixel
		var dy = (prev_view_center.y - view_center.y) / units_per_pixel
		var sx = roundi(dx)
		var sy = roundi(dy)
		if abs(sx) < img_w * 0.92 and abs(sy) < img_h * 0.92:
			_scroll_and_fill_strips(map_image, sx, sy, left, top, units_per_pixel, img_w, img_h)
			# continue with texture update below

	var sample_step = 1
	if internal_res <= 128 or units_per_pixel > 8.0:
		sample_step = 2

	if force_full:
		for y in range(0, img_h, sample_step):
			for x in range(0, img_w, sample_step):
				var wx = left + (x + 0.5) * units_per_pixel
				var wz = top + (y + 0.5) * units_per_pixel
				var col = _sample_design_color(wx, wz)
				for yy in range(y, y + sample_step):
					for xx in range(x, x + sample_step):
						if xx < img_w and yy < img_h:
							map_image.set_pixel(xx, yy, col)
	else:
		_start_threaded_regen(res, left, top, units_per_pixel, current_mode)
		last_regen_time_ms = now
		prev_view_center = view_center
		prev_units_per_pixel = units_per_pixel
		return

	# Update texture
	if map_texture == null:
		map_texture = ImageTexture.create_from_image(map_image)
	else:
		map_texture.update(map_image)
	map_view.texture = map_texture
	map_view.size = get_viewport_rect().size * 0.96

	last_regen_time_ms = now
	prev_view_center = view_center
	prev_units_per_pixel = units_per_pixel

func _start_threaded_regen(res: int, left: float, top: float, upp: float, mode: ViewMode):
	if _regen_thread and _regen_thread.is_alive():
		return
	_regen_mutex.lock()
	_pending_image = null
	_regen_mutex.unlock()

	_regen_thread = Thread.new()
	var params = {"seed": seed_value, "res": res, "left": left, "top": top, "upp": upp, "mode": mode}
	_regen_thread.start(_thread_regen_worker.bind(params))

func _thread_regen_worker(params: Dictionary):
	var sw = InfiniteNoiseWorld.new(params.seed)
	var r = params.res
	var l = params.left
	var t = params.top
	var u = params.upp
	var m = params.mode

	var img = Image.create(r, r, false, Image.FORMAT_RGBA8)
	var sstep = 2 if r <= 128 else 1

	for y in range(0, r, sstep):
		for x in range(0, r, sstep):
			var wx = l + (x + 0.5) * u
			var wz = t + (y + 0.5) * u
			var col = _thread_sample_color(sw, wx, wz, m)
			for yy in range(y, y + sstep):
				for xx in range(x, x + sstep):
					if xx < r and yy < r:
						img.set_pixel(xx, yy, col)

	_regen_mutex.lock()
	_pending_image = img
	_regen_mutex.unlock()
	call_deferred("_apply_threaded_result")

func _apply_threaded_result():
	_regen_mutex.lock()
	var new_img = _pending_image
	_pending_image = null
	_regen_mutex.unlock()

	if new_img:
		map_image = new_img
		if map_texture:
			map_texture.update(map_image)
		else:
			map_texture = ImageTexture.create_from_image(map_image)
		if map_view:
			map_view.texture = map_texture
		last_regen_time_ms = Time.get_ticks_msec()

	if _regen_thread:
		_regen_thread.wait_to_finish()
		_regen_thread = null

func _thread_sample_color(sw: InfiniteNoiseWorld, wx: float, wz: float, mode: ViewMode) -> Color:
	match mode:
		ViewMode.BIOME:
			var b = sw.get_biome_uncached(wx, 0.0, wz)
			return _biome_color(b.get("name", "plains"))
		ViewMode.HEIGHT:
			var h = sw.get_surface_height_uncached(wx, wz)
			return _height_shaded_color(sw, wx, wz, h)
		ViewMode.RIVERS:
			var h = sw.get_surface_height_uncached(wx, wz)
			var rmask = sw.get_river_mask(wx, wz) if sw.has_method("get_river_mask") else {"active": false, "strength": 0.0}
			return _thread_rivers_color_new(sw, wx, wz, h, rmask)
		_:
			var h: float = sw.get_surface_height_uncached(wx, wz)
			var b: Dictionary = sw.get_biome_uncached(wx, 0.0, wz)
			
			var river_mask_dict: Dictionary = sw.get_river_mask(wx, wz) if sw.has_method("get_river_mask") else {"active": false}
			var river = sw._compute_river_carve(wx, wz, h) if sw.has_method("_compute_river_carve") else {"carve": 0.0}
			
			var min_carve: float = sw.world_config.river_min_carve_for_tile if sw.world_config else 0.55
			var is_river_tile = river_mask_dict.get("active", false) and river.get("carve", 0.0) > max(min_carve, 4.0)
			
			if is_river_tile:
				return Color(0.05, 0.75, 1.0)
			
			return _composite_design_color(b.get("name", "plains"), h, wx, wz)

func _thread_rivers_color_new(sw: InfiniteNoiseWorld, wx: float, wz: float, h: float, rmask: Dictionary) -> Color:
	var active = rmask.get("active", false)
	var strength = rmask.get("strength", 0.0)
	var base = _height_shaded_color(sw, wx, wz, h)
	if active:
		base = base.lerp(Color(0.05, 0.92, 1.0), strength * 0.95)
		if strength > 0.7:
			base = base.darkened(0.2)
	return base

func _height_shaded_color(sw: InfiniteNoiseWorld, wx: float, wz: float, h: float) -> Color:
	var du: float = 8.0
	var hr: float = sw.get_surface_height_uncached(wx + du, wz)
	var hd: float = sw.get_surface_height_uncached(wx, wz + du)
	var slope: float = abs(hr - h) + abs(hd - h)
	
	var t: float = clamp((h + 8.0) / 130.0, 0.0, 1.0)
	var base: Color = Color(0.15, 0.12, 0.08).lerp(Color(0.95, 0.93, 0.88), t)
	
	var light: float = 0.55 + 0.45 * clamp(1.0 - slope / 18.0, 0.0, 1.0)
	base.r *= light
	base.g *= light
	base.b *= light
	
	if h < 32:
		base = base.lerp(Color(0.2, 0.35, 0.5), clamp((32.0 - h) / 45.0, 0.0, 0.55))
	return base

func _composite_design_color(bname: String, h: float, wx: float, wz: float) -> Color:
	var base: Color = _biome_color(bname)
	var t: float = clamp((h + 6.0) / 125.0, 0.0, 1.0)
	base = base.lerp(base.darkened(0.35).lightened(0.15), t * 0.65)
	
	# River check for Composite mode (new mask)
	var is_river = false
	if world.has_method("get_river_mask"):
		var rmask = world.get_river_mask(wx, wz)
		is_river = rmask.get("active", false)
	
	if is_river:
		base = base.lerp(Color(0.08, 0.88, 0.98), 0.92)  # bright cyan river
		base = base.darkened(0.1)
	
	return base

func _biome_color(name: String) -> Color:
	match name:
		"plains": return Color(0.58, 0.78, 0.42)
		"forest": return Color(0.18, 0.42, 0.18)
		"steppe": return Color(0.78, 0.72, 0.38)
		"marsh": return Color(0.28, 0.48, 0.42)
		"mountain": return Color(0.52, 0.50, 0.48)
		_: return Color(0.6, 0.6, 0.55)

func _thread_height_color(sw: InfiniteNoiseWorld, wx: float, wz: float, h: float) -> Color:
	var du: float = 8.0
	var hr: float = sw.get_surface_height_uncached(wx + du, wz)
	var hd: float = sw.get_surface_height_uncached(wx, wz + du)
	var sl: float = abs(hr - h) + abs(hd - h)
	var tt: float = clamp((h + 8.0) / 130.0, 0.0, 1.0)
	var bs: Color = Color(0.15, 0.12, 0.08).lerp(Color(0.95, 0.93, 0.88), tt)
	var lt: float = 0.55 + 0.45 * clamp(1.0 - sl / 18.0, 0.0, 1.0)
	bs.r *= lt; bs.g *= lt; bs.b *= lt
	if h < 32:
		bs = bs.lerp(Color(0.2, 0.35, 0.5), clamp((32.0 - h) / 45.0, 0.0, 0.55))
	return bs

func _thread_rivers_color(sw: InfiniteNoiseWorld, wx: float, wz: float, h: float, rinfo: Dictionary) -> Color:
	var isr: bool = rinfo.get("is_river", false)
	var rf: float = rinfo.get("river_factor", 0.0)
	var cv: float = rinfo.get("carve", 0.0)
	var corr: float = rinfo.get("corridor_factor", 0.0)
	var bs: Color = _thread_height_color(sw, wx, wz, h)
	if isr:
		# Strong, uniform bright cyan for the clean thick line (less variation to avoid noise look)
		bs = bs.lerp(Color(0.05, 0.90, 1.0), 0.95)
		if cv > 3.0: bs = bs.darkened(0.15)
	elif corr > 0.2:
		# Stronger, cleaner corridor tint for the valley around the line
		var v : float = clamp((corr - 0.1) / 0.75, 0.0, 0.9)
		bs = bs.lerp(Color(0.15, 0.45, 0.55), v * 0.65)
		if cv > 2.5:
			bs = bs.lerp(Color(0.12, 0.32, 0.40), clamp((cv-2.0)/9.0, 0.0, 0.5))
	elif cv > 2.5:
		bs = bs.lerp(Color(0.25, 0.42, 0.48), clamp((cv-2.0)/11.0, 0.0, 0.55))
	return bs

func _thread_composite_color(bnm: String, h: float, rinfo: Dictionary, sw: InfiniteNoiseWorld, wx: float, wz: float) -> Color:
	var bs: Color = Color(0.58, 0.78, 0.42)
	match bnm:
		"forest": bs = Color(0.18, 0.42, 0.18)
		"steppe": bs = Color(0.78, 0.72, 0.38)
		"marsh": bs = Color(0.28, 0.48, 0.42)
		"mountain": bs = Color(0.52, 0.50, 0.48)
	var tt: float = clamp((h + 6.0) / 125.0, 0.0, 1.0)
	bs = bs.lerp(bs.darkened(0.35).lightened(0.15), tt * 0.65)
	var cv: float = rinfo.get("carve", 0.0)
	var isr: bool = rinfo.get("is_river", false)
	var rf: float = rinfo.get("river_factor", 0.0)
	var corr: float = rinfo.get("corridor_factor", 0.0)
	if corr > 0.15 and not isr:
		var v: float = clamp((corr - 0.08) / 0.8, 0.0, 0.8)
		bs = bs.darkened(0.06 + v * 0.18)
		bs = bs.lerp(Color(0.15, 0.40, 0.50), v * 0.55)
	elif cv > 1.8 and not isr:
		var v: float = clamp((cv - 1.5) / 10.0, 0.0, 0.65)
		bs = bs.darkened(0.15 + v * 0.35)
		bs = bs.lerp(Color(0.22, 0.38, 0.42), v * 0.6)
	if isr:
		bs = bs.lerp(Color(0.08, 0.92, 1.0), 0.92)
		if cv > 4.0: bs = bs.darkened(0.12)
	if h > 95 and (bnm == "mountain" or bnm == "ridge"):
		bs = bs.lerp(Color(0.92, 0.95, 0.98), clamp((h-95)/45.0, 0.0, 0.6))
	return bs

# Efficiently shift existing pixel data and only sample the newly exposed strips.
# This turns a full 160x160 regen (~25k world samples) into a few thousand during normal panning.
func _scroll_and_fill_strips(img: Image, sx: int, sy: int, new_left: float, new_top: float, upp: float, w: int, h: int):
	var temp: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)

	# Copy the still-valid region from old positions to new positions
	var src_x: int = max(0, sx)
	var src_y: int = max(0, sy)
	var dst_x: int = max(0, -sx)
	var dst_y: int = max(0, -sy)
	var cw: int = w - abs(sx)
	var ch: int = h - abs(sy)

	if cw > 0 and ch > 0:
		for j in ch:
			for i in cw:
				temp.set_pixel(dst_x + i, dst_y + j, img.get_pixel(src_x + i, src_y + j))

	# Write the kept region back (we could also do img.blit_rect but per-pixel is predictable)
	for j in h:
		for i in w:
			if i >= dst_x and i < dst_x + cw and j >= dst_y and j < dst_y + ch:
				img.set_pixel(i, j, temp.get_pixel(i, j))
			else:
				# Mark as needing fill (we'll overwrite the strips below)
				pass

	# Fill the exposed vertical strips (left or right)
	if sx > 0:
		# New content on the left
		for yy in h:
			for xx in sx:
				var wx: float = new_left + (xx + 0.5) * upp
				var wz: float = new_top  + (yy + 0.5) * upp
				img.set_pixel(xx, yy, _sample_design_color(wx, wz))
	elif sx < 0:
		# New content on the right
		var startx: int = w + sx
		for yy in h:
			for xx in range(startx, w):
				var wx: float = new_left + (xx + 0.5) * upp
				var wz: float = new_top  + (yy + 0.5) * upp
				img.set_pixel(xx, yy, _sample_design_color(wx, wz))

	# Fill the exposed horizontal strips (top or bottom), avoiding double-work on corners
	if sy > 0:
		# New on top
		for yy in sy:
			for xx in w:
				if not ( (sx > 0 and xx < sx) or (sx < 0 and xx >= w + sx) ):
					var wx: float = new_left + (xx + 0.5) * upp
					var wz: float = new_top  + (yy + 0.5) * upp
					img.set_pixel(xx, yy, _sample_design_color(wx, wz))
	elif sy < 0:
		# New on bottom
		var starty: int = h + sy
		for yy in range(starty, h):
			for xx in w:
				if not ( (sx > 0 and xx < sx) or (sx < 0 and xx >= w + sx) ):
					var wx: float = new_left + (xx + 0.5) * upp
					var wz: float = new_top  + (yy + 0.5) * upp
					img.set_pixel(xx, yy, _sample_design_color(wx, wz))

func _update_hud():
	if not hud_label or not mode_label:
		return
	
	var view_width := get_viewport_rect().size.x * units_per_pixel
	hud_label.text = """Seed: %d    View center: (%.0f, %.0f)
Units/pixel: %.2f   (view ~%.0f units wide)    %s
Drag/WASD: pan   Wheel: zoom   R/+/Space: seed   1-4/M: mode   S: stats""" % [
		seed_value, view_center.x, view_center.y, units_per_pixel, view_width, mode_names[current_mode]
	]
	
	mode_label.text = "MODE: " + mode_names[current_mode]

func _update_inspector():
	if not inspector_label:
		return
	
	var mouse_screen: Vector2 = get_viewport().get_mouse_position()
	var vp: Vector2 = get_viewport_rect().size
	var norm: Vector2 = Vector2(mouse_screen.x / max(vp.x, 1), mouse_screen.y / max(vp.y, 1))
	
	var half_x: float = (vp.x * units_per_pixel) * 0.5
	var half_y: float = (vp.y * units_per_pixel) * 0.5
	var wx: float = view_center.x - half_x + norm.x * (vp.x * units_per_pixel)
	var wz: float = view_center.y - half_y + norm.y * (vp.y * units_per_pixel)
	
	var h: float = world.get_surface_height_uncached(wx, wz)
	var b: Dictionary = world.get_biome_uncached(wx, 0.0, wz)
	
	var bname: String = b.get("name", "???")
	var t: int = world.get_tile_type_uncached(wx, wz)
	
	var river_strength: float = 0.0
	var is_river_active: bool = false
	
	if world.has_method("get_river_mask"):
		var rmask: Dictionary = world.get_river_mask(wx, wz)
		river_strength = rmask.get("strength", 0.0)
		is_river_active = rmask.get("active", false)
	
	# Global tile coordinates
	var global_tile_x: int = int(floor(wx))
	var global_tile_z: int = int(floor(wz))
	
	inspector_label.text = """Mouse world: (%.0f, %.0f)   Global tile: (%d, %d)
h:%.0f   tile:%d   biome:%s   river:%.2f (active:%s)""" % [
		wx, wz, global_tile_x, global_tile_z, h, t, bname, river_strength, str(is_river_active)
	]

func _print_world_stats():
	# Rich design-oriented snapshot. Great for judging the new river system (thin channels vs wide lakes,
	# connected long rivers, good biome distribution, interesting carving/height variety).
	var cx = view_center.x
	var cy = view_center.y
	var step: float = 11.0
	var radius: float = 520.0
	
	var biome_counts: Dictionary = {}
	var river_hits: int = 0
	var total: int = 0
	var height_sum: float = 0.0
	var hcount: int = 0
	var carve_sum: float = 0.0
	var river_neighbor_hits: int = 0   # for linearity check
	
	var river_positions: Array[Vector2] = []
	
	var x: float = -radius
	while x <= radius:
		var y: float = -radius
		while y <= radius:
			var wx: float = cx + x
			var wz: float = cy + y
			total += 1
			
			var t: int = world.get_tile_type_uncached(wx, wz)
			var hh: float = world.get_surface_height_uncached(wx, wz)
			var rinfo: Dictionary = world._compute_river_carve(wx, wz, world._compute_raw_elevation(wx, wz)) if world.has_method("_compute_river_carve") else {}
			var river_mask = world.get_river_mask(wx, wz) if world.has_method("get_river_mask") else {"active": false}
			var is_riv: bool = river_mask.get("active", false)
			var crv: float = rinfo.get("carve", 0.0)
			
			if is_riv:
				river_hits += 1
				river_positions.append(Vector2(wx, wz))
				# Cheap linearity probe (4 directions)
				for d in [Vector2(step, 0), Vector2(-step, 0), Vector2(0, step), Vector2(0, -step)]:
					var nb_info: Dictionary = world._compute_river_carve(wx + d.x, wz + d.y, world._compute_raw_elevation(wx + d.x, wz + d.y)) if world.has_method("_compute_river_carve") else {}
					if nb_info.get("is_river", false):
						river_neighbor_hits += 1
			
			var b: Dictionary = world.get_biome_uncached(wx, 0.0, wz)
			if b:
				var bn: String = b.get("name", "unknown")
				biome_counts[bn] = biome_counts.get(bn, 0) + 1
			
			height_sum += hh
			carve_sum += crv
			hcount += 1
			
			y += step
		x += step
	
	var biome_line: String = ""
	for bn in biome_counts:
		var pct: float = 100.0 * biome_counts[bn] / total
		biome_line += "%s:%.0f%% " % [bn, pct]
	
	var river_pct: float = 100.0 * river_hits / total
	var avg_h: float = height_sum / hcount if hcount > 0 else 0.0
	var avg_carve: float = carve_sum / hcount if hcount > 0 else 0.0
	
	var continuity: float = 0.0
	if river_hits > 0:
		continuity = float(river_neighbor_hits) / float(river_hits * 4)
	
	# --- Improved diagnostics for "continuous winding" (addresses optimistic prior metrics) ---
	# 1. Connected components via proximity (real fragmentation + longest connected feature span in world units)
	var comps: Array = []
	for pos in river_positions:
		var found: bool = false
		for c in comps:
			for p in c:
				if pos.distance_to(p) < step * 1.65:
					c.append(pos)
					found = true
					break
			if found:
				break
		if not found:
			comps.append([pos])
	
	var num_comps := comps.size()
	var max_comp_pts := 0
	var max_comp_span := 0.0
	for c in comps:
		max_comp_pts = max(max_comp_pts, c.size())
		for ii in c.size():
			for jj in range(ii + 1, c.size()):
				max_comp_span = max(max_comp_span, c[ii].distance_to(c[jj]))
	
	# 2. Flow-traced unbroken run length (walk along plausible river direction from samples)
	var max_flow_run: float = 0.0
	var flow_step: float = step * 0.9
	for pos in river_positions:
		var cur := pos
		var run_len: float = 0.0
		var prev_dir: Vector2 = Vector2.ZERO
		for _i in range(18):  # up to ~ 18*10u ~180+ units of unbroken
			var best_next: Vector2 = Vector2.ZERO
			var best_score: float = -1.0
			for d in [Vector2(flow_step, 0), Vector2(-flow_step, 0), Vector2(0, flow_step), Vector2(0, -flow_step),
					  Vector2(flow_step * 0.7, flow_step * 0.7), Vector2(-flow_step * 0.7, flow_step * 0.7),
					  Vector2(flow_step * 0.7, -flow_step * 0.7), Vector2(-flow_step * 0.7, -flow_step * 0.7)]:
				var np : Vector2 = cur + d
				var nb_info: Dictionary = world._compute_river_carve(np.x, np.y, world._compute_raw_elevation(np.x, np.y)) if world.has_method("_compute_river_carve") else {}
				if nb_info.get("is_river", false):
					var score := 1.0
					if prev_dir != Vector2.ZERO:
						score += d.normalized().dot(prev_dir) * 0.8   # prefer continuing direction
					if score > best_score:
						best_score = score
						best_next = np
			if best_next == Vector2.ZERO:
				break
			prev_dir = (best_next - cur).normalized()
			cur = best_next
			run_len += flow_step
		if run_len > max_flow_run:
			max_flow_run = run_len
	
	# 3. Water level flatness on the river samples themselves (low stddev = good "flat surface")
	var wl_mean := 0.0
	var wl_var := 0.0
	var n_wl := 0
	for pos in river_positions:
		var wl: float = world.get_surface_height_uncached(pos.x, pos.y)
		wl_mean += wl
		wl_var += wl * wl
		n_wl += 1
	if n_wl > 1:
		wl_mean /= n_wl
		wl_var = (wl_var / n_wl) - (wl_mean * wl_mean)
	var wl_std := sqrt(max(0.0, wl_var))
	
	print("\n=== World Design Snapshot (center %.0f,%.0f  ~%d samples) ===" % [cx, cy, total])
	print("Biomes: ", biome_line)
	print("RIVER (thin channels): %.2f%%    avg carve: %.2f    river continuity (neighbor fraction): %.2f" % [river_pct, avg_carve, continuity])
	print("Avg height: %.1f" % avg_h)
	print("River components: %d   largest: %d pts, span: %.0f units   max flow-traced unbroken: %.0f units" % [num_comps, max_comp_pts, max_comp_span, max_flow_run])
	print("Water level flatness (stddev on river surfs): %.2f" % wl_std)
	if max_flow_run > 120.0 or max_comp_span > 150.0:
		print("LONG CONTINUOUS RIVER FEATURE(S) DETECTED — good!")
	print("View mode was: %s" % mode_names[current_mode])
	print("Tip: Look at 'max flow-traced unbroken' and 'components span' for true winding continuity (not just local density). Low water_level stddev = flat filled surface working. RIVER% 0.5-4 typical for 10-15 ribbons.")
	print("========================================================\n")

func get_tile_x_from_name(tile_name: String) -> int:
	# Reference (kept for any future tile-based debugging). Not used by the fast texture viewer.
	match tile_name.to_lower():
		"river": return 37
		"basin": return 36
		_: return 6

# -------------------------------------------------------------------
# Design color sampling (the heart of the fast viewer)
# -------------------------------------------------------------------

func _sample_design_color(wx: float, wz: float) -> Color:
	match current_mode:
		ViewMode.BIOME:
			var b: Dictionary = world.get_biome_uncached(wx, 0.0, wz)
			return _biome_color(b.get("name", "plains"))
		ViewMode.HEIGHT:
			var h: float = world.get_surface_height_uncached(wx, wz)
			return _height_shaded_color(world, wx, wz, h)
		ViewMode.RIVERS:
			var h: float = world.get_surface_height_uncached(wx, wz)
			var rmask: Dictionary = world.get_river_mask(wx, wz) if world.has_method("get_river_mask") else {"active": false, "strength": 0.0}
			return _thread_rivers_color_new(world, wx, wz, h, rmask)
		_:
			var h: float = world.get_surface_height_uncached(wx, wz)
			var b: Dictionary = world.get_biome_uncached(wx, 0.0, wz)
			
			# Exact match to game logic
			var river_mask_dict: Dictionary = world.get_river_mask(wx, wz) if world.has_method("get_river_mask") else {"active": false}
			var river = world._compute_river_carve(wx, wz, h) if world.has_method("_compute_river_carve") else {"carve": 0.0}
			
			var min_carve: float = world.world_config.river_min_carve_for_tile if world.world_config else 0.55
			var is_river_tile = river_mask_dict.get("active", false) and river.get("carve", 0.0) > max(min_carve, 4.0)
			
			if is_river_tile:
				return Color(0.05, 0.75, 1.0)
			
			return _composite_design_color(b.get("name", "plains"), h, wx, wz)

func _rivers_valleys_color(wx: float, wz: float, h: float, rinfo: Dictionary) -> Color:
	var is_riv: bool = rinfo.get("is_river", false)
	var rfac: float = rinfo.get("river_factor", 0.0)
	var crv: float = rinfo.get("carve", 0.0)
	
	var base: Color = _height_shaded_color(world, wx, wz, h)  # ← Fixed
	
	if is_riv:
		var river_col: Color = Color(0.15, 0.82, 0.95)
		var strength: float = clamp(0.6 + rfac * 0.5, 0.0, 1.0)
		base = base.lerp(river_col, strength)
		if crv > 4.0:
			base = base.darkened(0.25)
	elif crv > 2.5:
		var valley_tint: Color = Color(0.25, 0.42, 0.48)
		base = base.lerp(valley_tint, clamp((crv - 2.0) / 11.0, 0.0, 0.55))
	
	return base

# End of remade fast design viewer. Enjoy iterating on biomes + the natural river system!
