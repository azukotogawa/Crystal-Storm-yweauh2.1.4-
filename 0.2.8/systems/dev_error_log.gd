extends Node

const ENV_FLAG := "CRYSTALSTORM_DEV_ERROR_LOG"
const ARG_FLAG := "--dev-error-log"
const LOG_PATH := "user://logs/dev_errors.log"
const LOG_MAX_BYTES := 262144
const TOAST_SECONDS := 6.0


class _Sink extends Logger:
	var owner_ref: WeakRef

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind := "ERROR"
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		if error_type == Logger.ERROR_TYPE_SCRIPT:
			kind = "SCRIPT"
		elif error_type == Logger.ERROR_TYPE_SHADER:
			kind = "SHADER"
		var text := rationale if rationale != "" else code
		var where := "%s:%d %s" % [file, line, function]
		var o = owner_ref.get_ref() if owner_ref else null
		if o:
			o.call_deferred("_record", kind, text, where)

	func _log_message(_message: String, _error: bool) -> void:
		pass


var enabled: bool = false
var last_entry: String = ""
var entries: int = 0
var _sink: _Sink = null
var _layer: CanvasLayer = null
var _label: Label = null
var _toast_left: float = 0.0
var _writing: bool = false


static func flag_requested() -> bool:
	if OS.get_environment(ENV_FLAG) == "1":
		return true
	return ARG_FLAG in OS.get_cmdline_user_args() or ARG_FLAG in OS.get_cmdline_args()


func _ready() -> void:
	set_process(false)
	if flag_requested():
		enable()


func enable() -> void:
	if enabled:
		return
	enabled = true
	_sink = _Sink.new()
	_sink.owner_ref = weakref(self)
	OS.add_logger(_sink)
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)
	_label = Label.new()
	_label.name = "DevErrorToast"
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_label.offset_left = 12.0
	_label.offset_top = -64.0
	_label.offset_right = 900.0
	_label.offset_bottom = -12.0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_layer.add_child(_label)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_PATH.get_base_dir()))


func disable() -> void:
	if not enabled:
		return
	enabled = false
	if _sink:
		OS.remove_logger(_sink)
	_sink = null
	if _layer:
		_layer.queue_free()
	_layer = null
	_label = null
	set_process(false)


func _exit_tree() -> void:
	disable()


func _record(kind: String, text: String, where: String) -> void:
	if not enabled or _writing:
		return
	entries += 1
	last_entry = "[%s] %s (%s)" % [kind, text, where]
	_append_line("%s %s" % [Time.get_datetime_string_from_system(), last_entry])
	if _label:
		_label.text = "Dev error #%d: %s" % [entries, last_entry]
		_label.visible = true
		_toast_left = TOAST_SECONDS
		set_process(true)


func _append_line(line: String) -> void:
	_writing = true
	var abs_path := ProjectSettings.globalize_path(LOG_PATH)
	if FileAccess.file_exists(LOG_PATH):
		var size_f := FileAccess.open(LOG_PATH, FileAccess.READ)
		if size_f and size_f.get_length() > LOG_MAX_BYTES:
			size_f.close()
			DirAccess.rename_absolute(abs_path, abs_path + ".1")
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE) if FileAccess.file_exists(LOG_PATH) else FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()
	_writing = false


func _process(delta: float) -> void:
	_toast_left -= delta
	if _toast_left <= 0.0:
		if _label:
			_label.visible = false
		set_process(false)
