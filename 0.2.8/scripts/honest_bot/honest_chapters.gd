extends RefCounted

const _Pace = preload("res://scripts/honest_bot/honest_pace.gd")

var rows: Array[Dictionary] = []
var _elapsed := 0.0
var _open_feature := ""
var _open_start := 0.0
var _open := false


func begin() -> void:
	_elapsed = 0.0
	rows.clear()
	_open = false


func advance(delta: float) -> void:
	if delta > 0.0:
		_elapsed += delta


func seconds() -> float:
	return _elapsed


func format_clock() -> String:
	return format_seconds(seconds())


static func format_seconds(seconds: float) -> String:
	var clamped := maxf(seconds, 0.0)
	var mins := int(clamped / 60.0)
	var secs := clamped - float(mins * 60)
	return "%d:%05.2f" % [mins, secs]


func feature() -> String:
	if not _open:
		return ""
	return _open_feature


func span() -> float:
	if not _open:
		return 0.0
	return seconds() - _open_start


func can_advance() -> bool:
	if not _open:
		return true
	return span() >= _Pace.MIN_CHAPTER


func open(feature: String) -> bool:
	if _open and _open_feature == feature:
		return true
	if _open and not can_advance():
		return false
	if _open:
		close()
	_open_feature = feature
	_open_start = seconds()
	_open = true
	return true


func close() -> void:
	if not _open:
		return
	rows.append({
		"feature": _open_feature,
		"start": snappedf(_open_start, 0.001),
		"end": snappedf(seconds(), 0.001),
	})
	_open = false


func payload() -> Dictionary:
	return {"route": "showcase-speedrun", "chapters": rows}


func text_body() -> String:
	var lines := PackedStringArray()
	for row in rows:
		lines.append("%s %.3f %.3f" % [str(row.get("feature", "")), float(row.get("start", 0.0)), float(row.get("end", 0.0))])
	if lines.is_empty():
		return ""
	return "\n".join(lines) + "\n"


func write_dir(dir_path: String) -> bool:
	if _open:
		close()
	var err := DirAccess.make_dir_recursive_absolute(dir_path)
	if err != OK:
		push_error("chapters mkdir %s" % dir_path)
		return false
	var folder := dir_path
	while folder.ends_with("/") or folder.ends_with("\\"):
		folder = folder.substr(0, folder.length() - 1)
	var json_path := "%s/chapters.json" % folder
	var text_path := "%s/chapters.txt" % folder
	if not _store(json_path, JSON.stringify(payload(), "\t")):
		return false
	if not _store(text_path, text_body()):
		return false
	print("CHAPTERS %s" % json_path)
	print("CHAPTERS %s" % text_path)
	return true


func _store(path: String, body: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("chapters write %s" % path)
		return false
	file.store_string(body)
	file.close()
	return true
