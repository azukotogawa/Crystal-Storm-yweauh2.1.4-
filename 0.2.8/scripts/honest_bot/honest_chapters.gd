extends RefCounted

var rows: Array[Dictionary] = []
var _t0 := 0
var _open_feature := ""
var _open_start := 0.0
var _open := false


func begin() -> void:
	_t0 = Time.get_ticks_msec()
	rows.clear()
	_open = false


func seconds() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0


func format_clock() -> String:
	return format_seconds(seconds())


static func format_seconds(seconds: float) -> String:
	var clamped := maxf(seconds, 0.0)
	var mins := int(clamped / 60.0)
	var secs := clamped - float(mins * 60)
	return "%d:%05.2f" % [mins, secs]


func open(feature: String) -> void:
	if _open:
		close()
	_open_feature = feature
	_open_start = seconds()
	_open = true


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
