extends SceneTree
## Fails when a new hard-coded world-size number (2048, 1024, 16384, 128, 1088) shows up in
## game code. Known non-world-size uses are listed in scripts/world_size_literal_allowlist.txt.
## Run: godot --headless --path 0.2.8 -s res://scripts/verify_world_size_literals.gd

const ALLOWLIST := "res://scripts/world_size_literal_allowlist.txt"
const SKIP_TOP := ["scripts", "addons", "archive", ".godot"]

var _rx := RegEx.new()
var _allowed: Dictionary = {}
var _failed: int = 0


func _init() -> void:
	_rx.compile("(?<![\\w.])(2048|1024|16384|128|1088)(\\.0)?(?![\\w.])")
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("OK " + msg)
	else:
		_failed += 1
		print("FAIL " + msg)


func line_flagged(rel: String, line: String) -> bool:
	var t := line.strip_edges()
	if _rx.search(t) == null:
		return false
	return not _allowed.has(rel + " | " + t)


func _run() -> void:
	var f := FileAccess.open(ALLOWLIST, FileAccess.READ)
	_check(f != null, "allowlist readable")
	if f:
		while not f.eof_reached():
			var l := f.get_line().strip_edges()
			if l.is_empty() or l.begins_with("#"):
				continue
			_allowed[l] = true
		f.close()

	# Self-test of the matcher.
	_check(line_flagged("world/x.gd", "var half := 1024"), "flags a new 1024")
	_check(line_flagged("world/x.gd", "var n: int = b.get(\"chunks\", 16384)"), "flags a new 16384")
	_check(line_flagged("ui/x.gd", "const EXT := 1088.0"), "flags 1088.0")
	_check(not line_flagged("world/x.gd", "var v := 10240 + 0.1284"), "ignores longer numbers")
	_check(not line_flagged("helpers/world_border.gd", "const PLAYABLE_HALF_X := 1024"), "allowlisted source line passes")

	var files: Array[String] = []
	_collect("res://", "", files)
	var scanned := 0
	var bad: Array[String] = []
	for rel in files:
		var fa := FileAccess.open("res://" + rel, FileAccess.READ)
		if fa == null:
			continue
		scanned += 1
		var n := 0
		while not fa.eof_reached():
			var line := fa.get_line()
			n += 1
			if line_flagged(rel, line):
				bad.append("%s:%d: %s" % [rel, n, line.strip_edges()])
		fa.close()
	for b in bad:
		print("LITERAL " + b)
	_check(scanned > 100, "scanned %d .gd files" % scanned)
	_check(bad.is_empty(), "no new world-size literals (%d found)" % bad.size())
	print("WORLD_SIZE_LITERALS %s" % ("PASS" if _failed == 0 else "FAIL %d" % _failed))
	quit(0 if _failed == 0 else 1)


func _collect(base: String, rel: String, out: Array[String]) -> void:
	var path := base + rel
	for d in DirAccess.get_directories_at(path):
		if rel.is_empty() and SKIP_TOP.has(d):
			continue
		if d.begins_with("."):
			continue
		_collect(base, rel + d + "/", out)
	for fn in DirAccess.get_files_at(path):
		if fn.ends_with(".gd"):
			out.append(rel + fn)
