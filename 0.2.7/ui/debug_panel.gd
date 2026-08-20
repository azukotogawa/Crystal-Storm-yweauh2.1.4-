extends Control
## Compact F3 performance/status overlay. Presentation only — no gameplay.

const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

@onready var label = $DebugLabel

var _update_counter := 0
var _debug_update_every := 8
var _panel_enabled := true
var _last_text := ""
var _last_interact := ""


func _enter_tree() -> void:
	add_to_group("debug_panel")
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parent := get_parent()
	if parent is CanvasLayer:
		parent.process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	if label:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.process_mode = Node.PROCESS_MODE_ALWAYS
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(0.86, 0.93, 1.0, 0.95))
		label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.9))
		label.add_theme_constant_override("outline_size", 4)
		label.custom_minimum_size = Vector2(520, 88)
	_place_away_from_minimap()
	call_deferred("_place_away_from_minimap")


func apply_performance_config(cfg: _PerformanceQualityConfig) -> void:
	if cfg == null:
		return
	_panel_enabled = bool(cfg.debug_panel_enabled)
	_debug_update_every = maxi(int(cfg.debug_update_every), 4)
	visible = _panel_enabled
	set_process(_panel_enabled)
	_place_away_from_minimap()


func _interact_flag() -> String:
	if _GameplayInput.world_loading:
		return "LOADING"
	if _GameplayInput.pause_open:
		return "PAUSE"
	if _GameplayInput.blocks_actions():
		return "LOCKED"
	return "PLAY"


func _process(_delta: float) -> void:
	if not _panel_enabled or not label:
		return
	_update_counter += 1
	var interact := _interact_flag()
	var force: bool = interact != _last_interact
	if not force and _update_counter % _debug_update_every != 0:
		return
	_last_interact = interact
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("debug_panel")
	if profiler and profiler.has_method("sample_scene_stats"):
		profiler.sample_scene_stats(get_tree())
	_last_text = _build_text(profiler)
	label.text = _last_text
	if profiler and profiler.has_method("end"):
		profiler.end("debug_panel")


func get_overlay_text() -> String:
	return _last_text if not _last_text.is_empty() else (label.text if label else "")


func is_overlay_visible() -> bool:
	return visible


func toggle_overlay() -> bool:
	set_overlay_visible(not visible)
	return visible


func set_overlay_visible(show_overlay: bool) -> void:
	visible = show_overlay
	set_process(show_overlay and _panel_enabled)


func refresh_now() -> String:
	if not label:
		return get_overlay_text()
	_place_away_from_minimap()
	_last_interact = _interact_flag()
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("sample_scene_stats"):
		profiler.sample_scene_stats(get_tree())
	_last_text = _build_text(profiler)
	label.text = _last_text
	return _last_text


func _place_away_from_minimap() -> void:
	if label == null:
		return
	var x := 10.0
	var y := 8.0
	var tree := get_tree()
	if tree:
		var map = tree.get_first_node_in_group("topographical_map")
		if map and map.has_method("get_minimap_screen_rect"):
			var r: Rect2 = map.get_minimap_screen_rect()
			if r.size.x > 1.0 and r.size.y > 1.0:
				x = r.position.x + r.size.x + 10.0
				y = r.position.y
	label.position = Vector2(x, y)


func _build_text(profiler: Node) -> String:
	var fps: int = Engine.get_frames_per_second()
	var frame_ms: float = 1000.0 / maxf(float(fps), 1.0)
	var main_ms := -1.0
	var hottest := "—"
	var mem_s := ""
	if profiler and profiler.has_method("get_snapshot"):
		var snap: Dictionary = profiler.get_snapshot()
		main_ms = float(snap.get("frame_ms", -1.0))
		if main_ms > 0.05:
			frame_ms = main_ms
		hottest = _hottest_name(snap)
		var gauges: Dictionary = snap.get("gauges", {})
		var mem: float = float(gauges.get("mem_current_mb", 0.0))
		if mem > 0.5:
			mem_s = "  mem %.0f MB" % mem
	var col := Vector2i.ZERO
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_voxel_position"):
		var pv: Vector3 = player.get_voxel_position()
		col = Vector2i(floori(pv.x), floori(pv.z))
	elif player and "voxel_position" in player:
		col = Vector2i(floori(player.voxel_position.x), floori(player.voxel_position.z))
	var chunk := Vector2i(
		int(floor(float(col.x) / float(_ChunkData.SIZE))),
		int(floor(float(col.y) / float(_ChunkData.SIZE)))
	)
	var stream := _stream_line()
	var bake := _bake_line()
	var water := _water_line()
	var interact := _interact_flag()
	var lines: PackedStringArray = PackedStringArray()
	if main_ms >= 0.0:
		lines.append("F3  %d fps  %.1f ms  main %.1f  %s%s" % [
			fps, frame_ms, main_ms, interact, mem_s
		])
	else:
		lines.append("F3  %d fps  %.1f ms  %s%s" % [fps, frame_ms, interact, mem_s])
	lines.append("col %d,%d  chunk %d,%d  %s" % [col.x, col.y, chunk.x, chunk.y, stream])
	lines.append("%s  %s  hot %s" % [bake, water, hottest])
	lines.append("F4 inspect  F11 report  ESC pause")
	return "\n".join(lines)


func _hottest_name(snap: Dictionary) -> String:
	var secs: Dictionary = snap.get("sections", {})
	var best := ""
	var best_ms := 0.08
	for key_v in secs.keys():
		var e: Dictionary = secs[key_v]
		var ms: float = float(e.get("last_ms", e.get("last_us", 0.0) / 1000.0 if e.get("last_us", 0) else 0.0))
		if e.has("last_ms"):
			ms = float(e.last_ms)
		elif e.has("last_us"):
			ms = float(e.last_us) / 1000.0
		if ms > best_ms:
			best_ms = ms
			best = str(key_v)
	if best.is_empty():
		return "—"
	return "%s %.1f" % [best, best_ms]


func _stream_line() -> String:
	var cm = get_tree().get_first_node_in_group("chunk_manager")
	if cm == null:
		return "chunks —"
	var st: Dictionary = {}
	if cm.has_method("get_stream_status"):
		st = cm.get_stream_status()
	else:
		st = {"resident": cm.chunks.size() if "chunks" in cm else 0}
	var res: int = int(st.get("resident", 0))
	var sq: int = int(st.get("stream_queue", 0))
	var mq: int = int(st.get("mesh_pending", 0))
	var inf: int = int(st.get("inflight", 0))
	var rb: int = int(st.get("rebuild_pending", 0))
	return "chunks %d  streamQ %d  meshQ %d  inflight %d  rebuild %d" % [res, sq, mq, inf, rb]


func _bake_line() -> String:
	var wb = load("res://world/world_bake_service.gd")
	if wb == null or not wb.has_method("get_active"):
		return "bake —"
	var bake = wb.get_active()
	if bake == null:
		return "bake —"
	if bake.has_method("fill_status"):
		var fs: Dictionary = bake.fill_status()
		if bool(fs.get("bake_in_progress", false)):
			return "bake %d/%d" % [int(fs.get("done", 0)), int(fs.get("total", 0))]
		if bool(fs.get("valid", false)):
			return "bake idle"
		var mode_fill := str(bake.last_status_mode) if "last_status_mode" in bake else "off"
		return "bake %s" % mode_fill
	var mode := str(bake.last_status_mode) if "last_status_mode" in bake else "idle"
	var baking := bool(bake.bake_in_progress) if "bake_in_progress" in bake else false
	if mode == "generating" or baking:
		var msg := str(bake.last_status_message) if "last_status_message" in bake else mode
		return "bake %s" % msg
	return "bake idle"


func _water_line() -> String:
	var fluid = get_tree().get_first_node_in_group("voxel_fluid_service")
	if fluid == null or not fluid.has_method("get_sim_diagnostics"):
		return "water —"
	var d: Dictionary = fluid.get_sim_diagnostics()
	var us: int = int(d.get("last_tick_us", 0))
	if bool(d.get("sleeping", false)):
		return "water sleep"
	return "water %.2fms dirty=%d" % [float(us) / 1000.0, int(d.get("dirty_cells", 0))]
