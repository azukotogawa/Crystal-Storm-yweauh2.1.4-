class_name CombatLog
extends RefCounted

const MAX_LINES := 6

static var _lines: PackedStringArray = PackedStringArray()


static func push(message: String) -> void:
	_lines.append(message)
	while _lines.size() > MAX_LINES:
		_lines.remove_at(0)
	if OS.is_debug_build():
		print("[Combat] ", message)


static func get_recent(joiner: String = "\n") -> String:
	if _lines.is_empty():
		return "—"
	return joiner.join(_lines)


static func clear() -> void:
	_lines.clear()