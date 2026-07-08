extends Node
## Lightweight CPU profiler — shows up in Godot Monitor (Debugger → Monitors)
## and in the debug panel via get_snapshot().

var enabled: bool = true

var _sections: Dictionary = {}  # name -> {active: int, total_us: int, last_us: int, max_us: int}
var _frame_us: int = 0
var _frame_start: int = 0
var _worker_us: int = 0
var _worker_frame_us: int = 0


func _enter_tree() -> void:
	add_to_group("perf_profiler")
	_frame_start = Time.get_ticks_usec()


func _ready() -> void:
	set_process(true)
	call_deferred("_register_monitors_if_in_game")


func _register_monitors_if_in_game() -> void:
	if get_tree().get_first_node_in_group("config_service") == null:
		return
	_register_monitors()


func _process(_delta: float) -> void:
	if not enabled:
		return
	_frame_us = Time.get_ticks_usec() - _frame_start
	_frame_start = Time.get_ticks_usec()
	_worker_frame_us = _worker_us
	_worker_us = 0
	for key in _sections.keys():
		var s: Dictionary = _sections[key]
		if int(s.get("active", 0)) <= 0:
			s.last_us = 0
			_sections[key] = s


var _monitors_registered: bool = false


func _register_monitors() -> void:
	if _monitors_registered:
		return
	_monitors_registered = true
	var names := [
		"main_thread", "worker_total",
		"chunk_mesh", "chunk_buffer", "chunk_upload", "crystal_sim", "crystal_mesh",
		"map_build", "entity_physics", "entity_navigation", "vegetation_growth", "debug_panel",
	]
	for n in names:
		var key := "crystalstorm/%s_ms" % n
		Performance.add_custom_monitor(key, _make_monitor_callback(n))


func _make_monitor_callback(section: String) -> Callable:
	if section == "main_thread":
		return func() -> float:
			return float(_frame_us) / 1000.0
	if section == "worker_total":
		return func() -> float:
			return float(_worker_frame_us) / 1000.0
	return func() -> float:
		var s: Dictionary = _sections.get(section, {})
		return float(s.get("last_us", 0)) / 1000.0


func record_worker_us(elapsed_us: int) -> void:
	if not enabled or elapsed_us <= 0:
		return
	_worker_us += elapsed_us


func begin(section: String) -> void:
	if not enabled:
		return
	var s: Dictionary = _sections.get(section, {
		"active": 0, "total_us": 0, "last_us": 0, "max_us": 0, "start": 0,
	})
	s.active = int(s.active) + 1
	s.start = Time.get_ticks_usec()
	_sections[section] = s


func record_us(section: String, elapsed_us: int) -> void:
	if not enabled or elapsed_us <= 0:
		return
	var s: Dictionary = _sections.get(section, {
		"active": 0, "total_us": 0, "last_us": 0, "max_us": 0, "start": 0,
	})
	s.last_us = int(s.get("last_us", 0)) + elapsed_us
	s.total_us = int(s.total_us) + elapsed_us
	s.max_us = maxi(int(s.max_us), elapsed_us)
	_sections[section] = s


func end(section: String) -> void:
	if not enabled:
		return
	var s: Dictionary = _sections.get(section, {})
	if int(s.get("active", 0)) <= 0:
		return
	var elapsed: int = Time.get_ticks_usec() - int(s.get("start", 0))
	s.active = int(s.active) - 1
	s.last_us = int(s.get("last_us", 0)) + elapsed
	s.total_us = int(s.total_us) + elapsed
	s.max_us = maxi(int(s.max_us), elapsed)
	_sections[section] = s


func scope(section: String) -> RefCounted:
	return _Scope.new(self, section)


func get_snapshot() -> Dictionary:
	var main_us := _frame_us
	var worker_us := _worker_frame_us
	var tracked_main := 0
	for key in _sections.keys():
		tracked_main += int(_sections[key].get("last_us", 0))
	var untracked := maxi(main_us - tracked_main, 0)
	return {
		"frame_ms": float(main_us) / 1000.0,
		"worker_ms": float(worker_us) / 1000.0,
		"untracked_ms": float(untracked) / 1000.0,
		"sections": _snapshot_sections(),
	}


func _snapshot_sections() -> Dictionary:
	var out := {}
	for key in _sections.keys():
		var s: Dictionary = _sections[key]
		out[key] = {
			"last_ms": float(s.get("last_us", 0)) / 1000.0,
			"max_ms": float(s.get("max_us", 0)) / 1000.0,
		}
	return out


func format_debug_line() -> String:
	var snap := get_snapshot()
	var parts: PackedStringArray = []
	parts.append("main %.1fms" % snap.frame_ms)
	if float(snap.worker_ms) > 0.05:
		parts.append("worker %.1f" % snap.worker_ms)
	if float(snap.untracked_ms) > 0.5:
		parts.append("other %.1f" % snap.untracked_ms)
	var secs: Dictionary = snap.sections
	for key in [
		"chunk_upload", "crystal_sim", "crystal_mesh", "map_build", "entity_navigation",
	]:
		if secs.has(key):
			var e: Dictionary = secs[key]
			if float(e.last_ms) > 0.05:
				parts.append("%s %.1f" % [key, e.last_ms])
	return " | ".join(parts)


class _Scope:
	var _profiler: Node
	var _section: String

	func _init(profiler: Node, section: String) -> void:
		_profiler = profiler
		_section = section
		if _profiler:
			_profiler.begin(_section)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and _profiler:
			_profiler.end(_section)