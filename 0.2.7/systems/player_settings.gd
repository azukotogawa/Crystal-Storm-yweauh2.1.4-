class_name PlayerSettings
extends RefCounted
## Persisted player settings that map to existing systems only.

const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")
const _InputBindings = preload("res://systems/input_bindings.gd")

const DEFAULT_PATH := "user://player_settings.json"
const UI_SCALE_MIN := 0.75
const UI_SCALE_MAX := 1.5

static var settings_path: String = DEFAULT_PATH

static var screen_shake_enabled: bool = true
static var hit_stop_enabled: bool = true
static var flash_effects_enabled: bool = true
static var hit_markers_enabled: bool = true
static var crack_overlay_enabled: bool = true
static var volume_master: float = 1.0
static var volume_music: float = 1.0
static var volume_sfx: float = 1.0
static var volume_ui: float = 1.0
static var ui_scale: float = 1.0
static var reduce_motion: bool = false
static var colorblind_palette: bool = false
static var tutorial_completed: bool = false
static var fullscreen: bool = false
static var vsync_enabled: bool = true
static var resolution: String = "1280x720"
## Hide terrain between the camera and the player. Default on. Pitch is not persisted.
static var camera_cutaway_enabled: bool = true
static var keybinds: Dictionary = {}
## Times `_apply_display_now` was entered. Headless still counts; it does not touch the window.
static var display_apply_count: int = 0
## True after the first `apply_runtime`. Startup applies once; later reads must not.
static var runtime_applied: bool = false


static func reset_path() -> void:
	settings_path = DEFAULT_PATH


static func defaults() -> Dictionary:
	return {
		"quality_preset": int(_PerformanceQualityConfig.Preset.MEDIUM),
		"render_distance": 2,
		"vegetation_scatter_multiplier": 1.0,
		"combat_visuals_enabled": true,
		"screen_shake_enabled": true,
		"hit_stop_enabled": true,
		"flash_effects_enabled": true,
		"hit_markers_enabled": true,
		"crack_overlay_enabled": true,
		"volume_master": 1.0,
		"volume_music": 1.0,
		"volume_sfx": 1.0,
		"volume_ui": 1.0,
		"ui_scale": 1.0,
		"reduce_motion": false,
		"colorblind_palette": false,
		"tutorial_completed": false,
		"fullscreen": false,
		"vsync": true,
		"resolution": "1280x720",
		"camera_cutaway_enabled": true,
		"keybinds": {},
	}


static func load_settings() -> Dictionary:
	var out: Dictionary = defaults()
	if not FileAccess.file_exists(settings_path):
		_sync_runtime(out)
		return out
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	if parsed == null or not parsed is Dictionary:
		_sync_runtime(out)
		return out
	var data: Dictionary = parsed
	if data.has("quality_preset"):
		out["quality_preset"] = int(data.quality_preset)
	if data.has("render_distance"):
		out["render_distance"] = clampi(int(data.render_distance), 1, 8)
	if data.has("vegetation_scatter_multiplier"):
		out["vegetation_scatter_multiplier"] = clampf(float(data.vegetation_scatter_multiplier), 0.0, 1.0)
	if data.has("combat_visuals_enabled"):
		out["combat_visuals_enabled"] = bool(data.combat_visuals_enabled)
	if data.has("screen_shake_enabled"):
		out["screen_shake_enabled"] = bool(data.screen_shake_enabled)
	if data.has("hit_stop_enabled"):
		out["hit_stop_enabled"] = bool(data.hit_stop_enabled)
	if data.has("flash_effects_enabled"):
		out["flash_effects_enabled"] = bool(data.flash_effects_enabled)
	if data.has("hit_markers_enabled"):
		out["hit_markers_enabled"] = bool(data.hit_markers_enabled)
	if data.has("crack_overlay_enabled"):
		out["crack_overlay_enabled"] = bool(data.crack_overlay_enabled)
	for key in ["volume_master", "volume_music", "volume_sfx", "volume_ui"]:
		if data.has(key):
			out[key] = clampf(float(data[key]), 0.0, 1.0)
	if data.has("ui_scale"):
		out["ui_scale"] = clampf(float(data.ui_scale), UI_SCALE_MIN, UI_SCALE_MAX)
	if data.has("reduce_motion"):
		out["reduce_motion"] = bool(data.reduce_motion)
	if data.has("colorblind_palette"):
		out["colorblind_palette"] = bool(data.colorblind_palette)
	if data.has("tutorial_completed"):
		out["tutorial_completed"] = bool(data.tutorial_completed)
	if data.has("fullscreen"):
		out["fullscreen"] = bool(data.fullscreen)
	if data.has("vsync"):
		out["vsync"] = bool(data.vsync)
	if data.has("resolution"):
		out["resolution"] = str(data.resolution)
	if data.has("camera_cutaway_enabled"):
		out["camera_cutaway_enabled"] = bool(data.camera_cutaway_enabled)
	if data.has("keybinds") and data.keybinds is Dictionary:
		out["keybinds"] = data.keybinds
	_sync_runtime(out)
	return out


static func save_settings(data: Dictionary) -> bool:
	var merged: Dictionary = defaults()
	merged.merge(data, true)
	var dir := settings_path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(settings_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(merged, "\t"))
	f.close()
	_sync_runtime(merged)
	return true


## Copy persisted values into the statics. No InputMap, window, or scale calls.
static func _sync_runtime(data: Dictionary) -> void:
	screen_shake_enabled = bool(data.get("screen_shake_enabled", true))
	hit_stop_enabled = bool(data.get("hit_stop_enabled", true))
	flash_effects_enabled = bool(data.get("flash_effects_enabled", true))
	hit_markers_enabled = bool(data.get("hit_markers_enabled", true))
	crack_overlay_enabled = bool(data.get("crack_overlay_enabled", true))
	volume_master = clampf(float(data.get("volume_master", 1.0)), 0.0, 1.0)
	volume_music = clampf(float(data.get("volume_music", 1.0)), 0.0, 1.0)
	volume_sfx = clampf(float(data.get("volume_sfx", 1.0)), 0.0, 1.0)
	volume_ui = clampf(float(data.get("volume_ui", 1.0)), 0.0, 1.0)
	ui_scale = clampf(float(data.get("ui_scale", 1.0)), UI_SCALE_MIN, UI_SCALE_MAX)
	reduce_motion = bool(data.get("reduce_motion", false))
	colorblind_palette = bool(data.get("colorblind_palette", false))
	tutorial_completed = bool(data.get("tutorial_completed", false))
	fullscreen = bool(data.get("fullscreen", false))
	vsync_enabled = bool(data.get("vsync", true))
	resolution = str(data.get("resolution", "1280x720"))
	camera_cutaway_enabled = bool(data.get("camera_cutaway_enabled", true))
	var binds = data.get("keybinds", {})
	if binds is Dictionary:
		keybinds = (binds as Dictionary).duplicate(true)
	else:
		keybinds = {}


## Push keybinds, UI scale, and display from the statics. Call once at startup and from the settings menu.
static func apply_runtime(tree: SceneTree = null) -> void:
	_apply_keybinds_now()
	_apply_ui_scale_now(tree)
	_apply_display_now()
	runtime_applied = true


static func apply_ui_scale(tree: SceneTree = null) -> void:
	_apply_ui_scale_now(tree)


static func apply_display() -> void:
	_apply_display_now()


static func _apply_keybinds_now() -> void:
	_InputBindings.apply_saved(keybinds)


static func set_bus_volume(bus: String, linear: float, persist: bool = true) -> void:
	var v := clampf(linear, 0.0, 1.0)
	_store_volume(bus, v)
	if not persist:
		return
	var data := load_settings()
	_store_volume(bus, v)
	match bus:
		"Music":
			data["volume_music"] = v
		"SFX":
			data["volume_sfx"] = v
		"UI":
			data["volume_ui"] = v
		_:
			data["volume_master"] = v
	save_settings(data)


static func _store_volume(bus: String, v: float) -> void:
	match bus:
		"Music":
			volume_music = v
		"SFX":
			volume_sfx = v
		"UI":
			volume_ui = v
		_:
			volume_master = v


## Write persisted fields onto the live quality resource (does not call apply_quality).
static func apply_to_performance(perf) -> Dictionary:
	var data: Dictionary = load_settings()
	if perf == null:
		return data
	var quality = perf.get("quality") if "quality" in perf else null
	var env_preset := OS.get_environment("CRYSTALSTORM_PERF_PRESET").strip_edges().to_lower()
	# Env preset owns quality + native render_distance. Do not apply saved
	# quality_preset / render_distance from player_settings.json.
	if not env_preset.is_empty():
		if perf.has_method("apply_env_preset_if_set"):
			perf.apply_env_preset_if_set()
		quality = perf.get("quality") if "quality" in perf else quality
		if quality == null:
			return data
	else:
		var want_preset: int = int(data.get("quality_preset", _PerformanceQualityConfig.Preset.MEDIUM))
		if quality == null or int(quality.preset) != want_preset:
			if want_preset == int(_PerformanceQualityConfig.Preset.SAFE):
				quality = _PerformanceQualityConfig.apply_safe_mode()
			else:
				quality = _PerformanceQualityConfig.apply_preset(want_preset)
			perf.quality = quality
		if quality:
			quality.render_distance = clampi(int(data.get("render_distance", quality.render_distance)), 1, 8)
	if quality == null:
		return data
	quality.vegetation_scatter_multiplier = clampf(
		float(data.get("vegetation_scatter_multiplier", quality.vegetation_scatter_multiplier)), 0.0, 1.0
	)
	quality.combat_visuals_enabled = bool(data.get("combat_visuals_enabled", true))
	return data


static func write_policy(policy: Dictionary) -> void:
	var data: Dictionary = load_settings()
	var env_preset := OS.get_environment("CRYSTALSTORM_PERF_PRESET").strip_edges().to_lower()
	var saved_preset: int = int(data.get("quality_preset", _PerformanceQualityConfig.Preset.MEDIUM))
	var live_preset: int = int(policy.get("preset", saved_preset))
	if env_preset.is_empty() and saved_preset == live_preset:
		policy["render_distance"] = clampi(int(data.get("render_distance", 2)), 1, 8)
	policy["vegetation_scatter_multiplier"] = clampf(
		float(data.get("vegetation_scatter_multiplier", 1.0)), 0.0, 1.0
	)
	if env_preset.is_empty():
		policy["preset"] = saved_preset


## After QUALITY_APPLIED: overlay player fields and push through apply_to_registered.
static func apply_after_quality(perf, registry, resolved: Dictionary = {}) -> Dictionary:
	var data: Dictionary = apply_to_performance(perf)
	if resolved.has("policy") and resolved.policy is Dictionary:
		write_policy(resolved.policy)
	if perf != null and registry != null and perf.has_method("apply_to_registered"):
		perf.apply_to_registered(registry, resolved)
	return data


static func apply_to_tree(tree: SceneTree) -> Dictionary:
	var data: Dictionary = load_settings()
	if tree == null:
		return data
	apply_accessibility(tree)
	var perf = tree.get_first_node_in_group("performance_service")
	return apply_to_performance(perf)


static func set_ui_scale(scale: float, persist: bool = true) -> void:
	var v := clampf(scale, UI_SCALE_MIN, UI_SCALE_MAX)
	if persist:
		var data := load_settings()
		data["ui_scale"] = v
		if not save_settings(data):
			ui_scale = v
			_apply_ui_scale_now()
			return
	else:
		ui_scale = v
	_apply_ui_scale_now()


static func set_tutorial_completed(done: bool) -> void:
	var data := load_settings()
	data["tutorial_completed"] = done
	save_settings(data)


static func bind_action(action: String, event: InputEvent) -> String:
	var data := load_settings()
	var conflict := _InputBindings.conflict_for(action, event)
	if conflict != "":
		return conflict
	_InputBindings.replace_action(action, event)
	data["keybinds"] = _InputBindings.export_current()
	save_settings(data)
	_apply_keybinds_now()
	return ""


static func reset_bindings() -> void:
	var data := load_settings()
	data["keybinds"] = {}
	save_settings(data)
	_apply_keybinds_now()


static func apply_accessibility(tree: SceneTree) -> void:
	if tree == null:
		return
	var crystal = tree.get_first_node_in_group("crystal_manager")
	if crystal and crystal.has_method("apply_color_palette"):
		crystal.apply_color_palette(colorblind_palette)
	var overlay = tree.get_first_node_in_group("game_overlay")
	if overlay and overlay.has_method("apply_hud_palette"):
		overlay.apply_hud_palette(colorblind_palette)


static func _apply_ui_scale_now(tree: SceneTree = null) -> void:
	var host := tree
	if host == null:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			host = loop as SceneTree
	if host and host.root:
		host.root.content_scale_factor = ui_scale


static func _apply_display_now() -> void:
	display_apply_count += 1
	if DisplayServer.get_name() == "headless":
		return
	var want_vsync := DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != want_vsync:
		DisplayServer.window_set_vsync_mode(want_vsync)
	var want_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want_mode:
		DisplayServer.window_set_mode(want_mode)
	if fullscreen:
		return
	var parts := resolution.split("x")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		var want_size := Vector2i(int(parts[0]), int(parts[1]))
		if DisplayServer.window_get_size() != want_size:
			DisplayServer.window_set_size(want_size)
