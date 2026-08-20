extends Control
## Production loading overlay driven by CompositionRoot stages + WorldBakeService status.
## Covers the viewport from the first frame until INITIAL_STREAM_READY, then fades out.
## Does not alter boot logic — presentation only.

const _GameplayInput = preload("res://helpers/gameplay_input.gd")

const FADE_SEC: float = 0.35
const TIP_ROTATE_SEC: float = 5.5

const STAGE_LABELS := {
	"UNINITIALIZED": "Starting...",
	"CONFIGURED": "Initializing Engine",
	"QUALITY_APPLIED": "Applying Graphics Settings",
	"FEATURES_SEEDED": "Loading World Data",
	"CHUNKS_CREATED": "Preparing Terrain",
	"INITIAL_STREAM_READY": "Loading Nearby Chunks",
	"VISUALS_COMMITTED": "Finalizing Rendering",
	"RUNNING": "Entering World",
	"FAILED": "Startup Failed",
}

const STAGE_PROGRESS := {
	"UNINITIALIZED": 0.02,
	"CONFIGURED": 0.12,
	"QUALITY_APPLIED": 0.24,
	"FEATURES_SEEDED": 0.40,
	"CHUNKS_CREATED": 0.58,
	"INITIAL_STREAM_READY": 0.82,
	"VISUALS_COMMITTED": 0.94,
	"RUNNING": 1.0,
}

const TIPS: PackedStringArray = [
	"Dig trenches to slow the crystal's advance.",
	"Build walls and mazes — time is your weapon.",
	"Rivers and valleys shape how the crystal spreads.",
	"Explore ruins for power the crystal also wants.",
	"Rotate the camera with Q / E; zoom with the mouse wheel.",
	"Towns can raise militia if you keep them safe.",
	"Plant vegetation to restore terrain after digging.",
	"The origin holds the final crystal heart.",
]

var _compose: Node = null
var _bg: ColorRect
var _vignette: ColorRect
var _title: Label
var _subtitle: Label
var _phase: Label
var _bake_label: Label
var _tip: Label
var _bar: ProgressBar
var _pct: Label
var _elapsed_label: Label
var _version: Label
var _error_panel: PanelContainer
var _error_text: Label
var _retry_btn: Button
var _rebuild_btn: Button
var _crystal_layer: Control
var _crystals: Array = []  # { node, phase, speed, base }

var _progress: float = 0.0
var _display_progress: float = 0.0
var _phase_text: String = "Starting..."
var _bake_mode: String = "idle"
var _fading: bool = false
var _dismissed: bool = false
var _tip_i: int = 0
var _tip_t: float = 0.0
var _boot_t0_ms: int = 0
var _pulse: float = 0.0
var _bake_connected: bool = false


func _ready() -> void:
	add_to_group("loading_screen")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	_GameplayInput.set_world_loading(true)
	_boot_t0_ms = Time.get_ticks_msec()
	_build_ui()
	_set_progress(0.02, "Starting...")
	_tip_i = randi() % maxi(TIPS.size(), 1)
	_refresh_tip()
	set_process(true)
	# Bind as soon as CompositionRoot exists (same frame parent tree).
	call_deferred("_try_bind")


func _try_bind() -> void:
	if _compose != null:
		return
	var tree := get_tree()
	if tree == null:
		return
	_compose = tree.get_first_node_in_group("composition_root")
	if _compose == null:
		# Parent may be Game/CompositionRoot path
		var game := get_parent()
		while game and game.name != "Game":
			game = game.get_parent()
		if game:
			_compose = game.get_node_or_null("CompositionRoot")
	if _compose == null:
		return
	if _compose.has_signal("stage_changed") and not _compose.stage_changed.is_connected(_on_stage_changed):
		_compose.stage_changed.connect(_on_stage_changed)
	if _compose.has_signal("boot_failed") and not _compose.boot_failed.is_connected(_on_boot_failed):
		_compose.boot_failed.connect(_on_boot_failed)
	if _compose.has_signal("boot_completed") and not _compose.boot_completed.is_connected(_on_boot_completed):
		_compose.boot_completed.connect(_on_boot_completed)
	# Catch late bind mid-boot.
	if _compose.has_method("get_stage_name"):
		_on_stage_changed(int(_compose.stage) if "stage" in _compose else 0, str(_compose.get_stage_name()))
	_try_bind_bake()


func _try_bind_bake() -> void:
	if _bake_connected:
		return
	var wb = load("res://world/world_bake_service.gd")
	if wb == null or not wb.has_method("get_active"):
		return
	var bake = wb.get_active()
	if bake == null:
		return
	if bake.has_signal("status_changed") and not bake.status_changed.is_connected(_on_bake_status):
		bake.status_changed.connect(_on_bake_status)
		_bake_connected = true
	if str(bake.get("last_status_mode")) != "" and str(bake.get("last_status_mode")) != "idle":
		_on_bake_status(
			str(bake.get("last_status_mode")),
			float(bake.get("last_status_progress")),
			str(bake.get("last_status_message"))
		)


func bind_composition_root(root: Node) -> void:
	_compose = root
	_try_bind()


func _build_ui() -> void:
	# Full-bleed dark backdrop (never black-void: deep indigo crystal night).
	_bg = ColorRect.new()
	_bg.name = "Backdrop"
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color(0.04, 0.05, 0.10, 1.0)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_crystal_layer = Control.new()
	_crystal_layer.name = "CrystalLayer"
	_crystal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crystal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crystal_layer)
	_spawn_crystal_accents()

	_vignette = ColorRect.new()
	_vignette.name = "Vignette"
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(0.02, 0.02, 0.05, 0.35)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)

	var center := VBoxContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.anchor_left = 0.5
	center.anchor_right = 0.5
	center.anchor_top = 0.5
	center.anchor_bottom = 0.5
	center.offset_left = -280.0
	center.offset_right = 280.0
	center.offset_top = -160.0
	center.offset_bottom = 200.0
	center.add_theme_constant_override("separation", 10)
	add_child(center)

	_title = Label.new()
	_title.name = "Title"
	_title.text = "CRYSTAL STORM"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 42)
	_title.add_theme_color_override("font_color", Color(0.78, 0.92, 1.0, 1.0))
	_title.add_theme_color_override("font_outline_color", Color(0.15, 0.35, 0.55, 0.9))
	_title.add_theme_constant_override("outline_size", 4)
	center.add_child(_title)

	_subtitle = Label.new()
	_subtitle.name = "Subtitle"
	_subtitle.text = "Maze. Dig. Survive."
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 16)
	_subtitle.add_theme_color_override("font_color", Color(0.55, 0.72, 0.88, 0.95))
	center.add_child(_subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 28)
	center.add_child(spacer)

	_phase = Label.new()
	_phase.name = "PhaseLabel"
	_phase.text = "Starting..."
	_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase.add_theme_font_size_override("font_size", 18)
	_phase.add_theme_color_override("font_color", Color(0.85, 0.9, 0.98, 1.0))
	center.add_child(_phase)
	var lock := Label.new()
	lock.name = "LockHint"
	lock.text = "Controls locked until nearby terrain is ready"
	lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock.add_theme_font_size_override("font_size", 14)
	lock.add_theme_color_override("font_color", Color(1.0, 0.78, 0.45, 0.95))
	center.add_child(lock)

	_bake_label = Label.new()
	_bake_label.name = "BakeLabel"
	_bake_label.text = ""
	_bake_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bake_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bake_label.add_theme_font_size_override("font_size", 13)
	_bake_label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.9, 0.95))
	center.add_child(_bake_label)

	_bar = ProgressBar.new()
	_bar.name = "ProgressBar"
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 18)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(_bar)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(row)

	_pct = Label.new()
	_pct.name = "Percent"
	_pct.text = "0%"
	_pct.add_theme_font_size_override("font_size", 14)
	_pct.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.9))
	row.add_child(_pct)

	var mid := Label.new()
	mid.text = "  ·  "
	mid.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7, 0.8))
	row.add_child(mid)

	_elapsed_label = Label.new()
	_elapsed_label.name = "Elapsed"
	_elapsed_label.text = "0.0s"
	_elapsed_label.add_theme_font_size_override("font_size", 14)
	_elapsed_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.9))
	row.add_child(_elapsed_label)

	var tip_spacer := Control.new()
	tip_spacer.custom_minimum_size = Vector2(0, 18)
	center.add_child(tip_spacer)

	_tip = Label.new()
	_tip.name = "Tip"
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_font_size_override("font_size", 13)
	_tip.add_theme_color_override("font_color", Color(0.55, 0.68, 0.82, 0.9))
	center.add_child(_tip)

	_version = Label.new()
	_version.name = "Version"
	_version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_version.anchor_left = 1.0
	_version.anchor_top = 1.0
	_version.anchor_right = 1.0
	_version.anchor_bottom = 1.0
	_version.offset_left = -220.0
	_version.offset_top = -36.0
	_version.offset_right = -16.0
	_version.offset_bottom = -12.0
	_version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_version.add_theme_font_size_override("font_size", 11)
	_version.add_theme_color_override("font_color", Color(0.45, 0.55, 0.65, 0.75))
	var ver := str(Engine.get_version_info().get("string", ""))
	_version.text = "Crystalstorm  ·  Godot %s" % ver
	add_child(_version)

	_build_error_panel()


func _spawn_crystal_accents() -> void:
	# Lightweight decorative quads — no textures required.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 14:
		var poly := Polygon2D.new()
		var s: float = rng.randf_range(10.0, 28.0)
		poly.polygon = PackedVector2Array([
			Vector2(0, -s),
			Vector2(s * 0.55, 0),
			Vector2(0, s * 0.85),
			Vector2(-s * 0.55, 0),
		])
		var c := Color(
			rng.randf_range(0.25, 0.55),
			rng.randf_range(0.55, 0.9),
			rng.randf_range(0.85, 1.0),
			rng.randf_range(0.08, 0.22)
		)
		poly.color = c
		poly.position = Vector2(rng.randf_range(0.05, 0.95), rng.randf_range(0.08, 0.92))
		# Position as fraction — update in process via size
		_crystal_layer.add_child(poly)
		_crystals.append({
			"node": poly,
			"fx": rng.randf(),
			"fy": rng.randf(),
			"phase": rng.randf() * TAU,
			"speed": rng.randf_range(0.6, 1.6),
			"base_a": c.a,
		})


func _build_error_panel() -> void:
	_error_panel = PanelContainer.new()
	_error_panel.name = "ErrorPanel"
	_error_panel.visible = false
	_error_panel.set_anchors_preset(Control.PRESET_CENTER)
	_error_panel.anchor_left = 0.5
	_error_panel.anchor_right = 0.5
	_error_panel.anchor_top = 0.5
	_error_panel.anchor_bottom = 0.5
	_error_panel.offset_left = -260.0
	_error_panel.offset_right = 260.0
	_error_panel.offset_top = -120.0
	_error_panel.offset_bottom = 120.0
	add_child(_error_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_error_panel.add_child(v)

	var err_title := Label.new()
	err_title.text = "Could not start"
	err_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	err_title.add_theme_font_size_override("font_size", 22)
	v.add_child(err_title)

	_error_text = Label.new()
	_error_text.name = "ErrorText"
	_error_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_text.add_theme_font_size_override("font_size", 14)
	v.add_child(_error_text)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	v.add_child(buttons)

	_retry_btn = Button.new()
	_retry_btn.text = "Retry"
	_retry_btn.custom_minimum_size = Vector2(120, 36)
	_retry_btn.pressed.connect(_on_retry)
	buttons.add_child(_retry_btn)

	_rebuild_btn = Button.new()
	_rebuild_btn.text = "Rebuild World"
	_rebuild_btn.custom_minimum_size = Vector2(140, 36)
	_rebuild_btn.pressed.connect(_on_rebuild_world)
	buttons.add_child(_rebuild_btn)


func _process(delta: float) -> void:
	_try_bind()
	if not _bake_connected:
		_try_bind_bake()
	_poll_composition_stage()
	_poll_start_region()

	_pulse += delta
	_tip_t += delta
	if _tip_t >= TIP_ROTATE_SEC and not _error_panel.visible:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % maxi(TIPS.size(), 1)
		_refresh_tip()

	# Smooth progress bar (never jump backwards except on error reset).
	if _display_progress < _progress:
		_display_progress = minf(_progress, _display_progress + delta * 0.55)
	_bar.value = _display_progress
	_pct.text = "%d%%" % int(round(_display_progress * 100.0))
	var elapsed_s: float = float(Time.get_ticks_msec() - _boot_t0_ms) / 1000.0
	_elapsed_label.text = "%.1fs" % elapsed_s

	# Animate crystal accents with viewport size.
	var sz := size
	if sz.x < 1.0 or sz.y < 1.0:
		sz = get_viewport_rect().size
	for entry in _crystals:
		var n: Polygon2D = entry["node"]
		var fx: float = float(entry["fx"])
		var fy: float = float(entry["fy"])
		var ph: float = float(entry["phase"]) + _pulse * float(entry["speed"])
		n.position = Vector2(fx * sz.x, fy * sz.y + sin(ph) * 8.0)
		var col := n.color
		col.a = float(entry["base_a"]) * (0.65 + 0.35 * sin(ph * 1.3))
		n.color = col

	# Soft pulse on title
	if _title:
		var a: float = 0.88 + 0.12 * sin(_pulse * 1.8)
		_title.modulate = Color(1, 1, 1, a)


## Fallback if stage_changed was missed (e.g. bind order / headless edge cases).
func _poll_composition_stage() -> void:
	if _compose == null or _fading or _dismissed:
		return
	if not ("stage" in _compose):
		return
	var st: int = int(_compose.stage)
	# CompositionRoot.Stage.INITIAL_STREAM_READY = 5, FAILED = 9
	if st == 9:
		return
	if st >= 5:
		if _progress < 0.82:
			_set_progress(0.88, "Ready")
		_begin_fade_out()
	elif st >= 1 and _compose.has_method("get_stage_name"):
		var sn: String = str(_compose.get_stage_name())
		var want_p: float = float(STAGE_PROGRESS.get(sn, _progress))
		if want_p > _progress + 0.001:
			_set_progress(want_p, str(STAGE_LABELS.get(sn, sn)))


func _refresh_tip() -> void:
	if TIPS.is_empty():
		_tip.text = ""
		return
	_tip.text = "Tip: %s" % TIPS[_tip_i % TIPS.size()]


func _set_progress(p: float, phase_text: String) -> void:
	_progress = clampf(maxf(p, _progress) if not _fading else p, 0.0, 1.0)
	if not phase_text.is_empty():
		_phase_text = phase_text
		_phase.text = _phase_text


func _on_stage_changed(_stage_id: int, stage_name: String) -> void:
	if _dismissed and stage_name != "FAILED":
		return
	var label: String = str(STAGE_LABELS.get(stage_name, stage_name))
	var p: float = float(STAGE_PROGRESS.get(stage_name, _progress))
	# Prefer bake-driven copy during terrain stages when generating.
	if stage_name == "CHUNKS_CREATED" or stage_name == "FEATURES_SEEDED":
		if _bake_mode == "generating":
			label = _phase_text if not _phase_text.is_empty() else "Generating World..."
		elif _bake_mode == "loading" or _bake_mode == "valid":
			if _bake_label.text.is_empty():
				_bake_label.text = "Loading World..."
	_set_progress(p, label)

	if stage_name == "INITIAL_STREAM_READY":
		# Early enter: player-safe world is ready; remaining work continues under the fade.
		var _STP = load("res://systems/startup_total_profiler.gd")
		if _STP and _STP.is_enabled():
			_STP.mark_playable("loading_screen.INITIAL_STREAM_READY fade")
			_STP.event("loading_screen.fade_begin", {}, "playable_gate")
		_set_progress(0.88, "Ready")
		_begin_fade_out()
	elif stage_name == "RUNNING" and not _dismissed and not _fading:
		_set_progress(1.0, "Entering World")
		_begin_fade_out()


func _on_bake_status(mode: String, progress: float, message: String) -> void:
	_bake_mode = mode
	if not message.is_empty():
		_bake_label.text = message
	if _fading or _dismissed:
		if mode == "generating" and _bake_label:
			_bake_label.text = message if not message.is_empty() else "Generating remaining world..."
		return
	# Do not map full-world fill (16k packages) onto the start-region bar.
	# Start-region occupancy is polled from ChunkManager.start_region_status.
	if mode == "generating" and not message.is_empty():
		if not _bake_label.text.begins_with("Start region"):
			_bake_label.text = message
	elif mode == "loading":
		_set_progress(maxf(_progress, 0.40), message if not message.is_empty() else "Loading World Data...")
	elif mode == "valid":
		_set_progress(maxf(_progress, 0.55), "Loading World...")
	elif mode == "error":
		_bake_label.text = message


func _poll_start_region() -> void:
	if _fading or _dismissed:
		return
	var tree := get_tree()
	if tree == null:
		return
	var cm = tree.get_first_node_in_group("chunk_manager")
	if cm == null or not cm.has_method("start_region_status"):
		return
	var st: Dictionary = cm.start_region_status()
	var need: int = int(st.get("needed", 0))
	var have: int = int(st.get("resident", 0))
	var pkgs: int = int(st.get("packages", 0))
	if need <= 0:
		return
	var frac: float = clampf(float(have) / float(need), 0.0, 1.0)
	var p: float = 0.58 + frac * 0.30
	if have < need:
		_set_progress(p, "Nearby chunks %d / %d — cannot play yet" % [have, need])
	else:
		_set_progress(p, "Nearby chunks %d / %d — ready" % [have, need])
	_bake_label.text = "Start region streamed %d / %d  ·  packages %d / %d" % [have, need, pkgs, need]


func _on_boot_failed(reason: String, _dump: Dictionary) -> void:
	_fading = false
	_dismissed = false
	visible = true
	modulate = Color.WHITE
	_error_panel.visible = true
	_error_text.text = reason if not reason.is_empty() else "Unknown startup failure."
	_phase.text = "Startup Failed"
	_bar.value = 0.0
	_progress = 0.0
	_display_progress = 0.0
	# Rebuild is useful when bake/world package is the failure surface.
	var r := reason.to_lower()
	_rebuild_btn.visible = (
		r.contains("bake") or r.contains("chunk") or r.contains("world") or r.contains("timeout")
	)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _on_boot_completed() -> void:
	# If fade already started at INITIAL_STREAM_READY, nothing to do.
	if not _dismissed and not _fading:
		_begin_fade_out()


func _begin_fade_out() -> void:
	if _fading or _dismissed:
		return
	if _error_panel.visible:
		return
	_fading = true
	_progress = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.set_parallel(false)
	tw.tween_property(self, "modulate:a", 0.0, FADE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_finish_dismiss)


func _finish_dismiss() -> void:
	_dismissed = true
	_fading = false
	visible = false
	_GameplayInput.set_world_loading(false)
	# Allow HUD toasts etc. to show cleanly.
	var overlay = get_tree().get_first_node_in_group("game_overlay") if get_tree() else null
	if overlay == null:
		var cl := get_parent()
		if cl:
			overlay = cl.get_node_or_null("GameOverlay")
	if overlay and overlay.has_method("notify_loading_finished"):
		overlay.notify_loading_finished()


func _on_retry() -> void:
	_error_panel.visible = false
	get_tree().reload_current_scene()


func _on_rebuild_world() -> void:
	var wb = load("res://world/world_bake_service.gd")
	if wb != null:
		wb.force_rebuild_next = true
	_error_panel.visible = false
	_bake_label.text = "Generating World... This only happens the first time you play or after major world updates."
	get_tree().reload_current_scene()
