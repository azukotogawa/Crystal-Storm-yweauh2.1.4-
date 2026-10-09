extends SceneTree
## Manifest JSON has the required fields and flags missing generator art.

const _Manifest = preload("res://tools/texture_manifest.gd")

const _FIELDS: PackedStringArray = [
	"path", "expected_size", "scale", "animation_frames", "appears_in", "category", "art",
]


var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _run() -> void:
	if _Manifest.classify_art("res://assets/art/crystal/amethyst.png") != "missing":
		_fail("amethyst.png should be missing")
	if _Manifest.classify_art("res://assets/tiles/Cube.png") != "art":
		_fail("Cube.png should be art")
	if _Manifest.classify_art("runtime://generated/crystal/amethyst") != "placeholder":
		_fail("runtime crystal slot should be placeholder")
	var doc: Dictionary = _Manifest.write_project()
	var json_path := ProjectSettings.globalize_path("res://docs/texture_manifest.json")
	var md_path := ProjectSettings.globalize_path("res://docs/TEXTURE_MANIFEST.md")
	if not FileAccess.file_exists(json_path) or not FileAccess.file_exists(md_path):
		_fail("manifest files were not written")
		quit(1)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if parsed == null or not (parsed is Dictionary):
		_fail("manifest JSON did not parse")
		quit(1)
		return
	var file_doc: Dictionary = parsed
	var slots: Array = file_doc.get("slots", [])
	if slots.is_empty():
		_fail("manifest has no slots")
	if int(file_doc.get("slot_count", -1)) != slots.size():
		_fail("slot_count %s != %d" % [file_doc.get("slot_count"), slots.size()])
	var art_n := 0
	var missing_n := 0
	var placeholder_n := 0
	var saw_amethyst := false
	var saw_runtime := false
	var saw_cube := false
	for slot in slots:
		if not (slot is Dictionary):
			_fail("slot is not an object")
			continue
		for field in _FIELDS:
			if not slot.has(field):
				_fail("slot missing %s (%s)" % [field, slot.get("path", "?")])
				break
		var size = slot.get("expected_size", [])
		if not (size is Array) or size.size() != 2:
			_fail("expected_size invalid for %s" % slot.get("path", "?"))
		if not (slot.get("appears_in") is Array):
			_fail("appears_in invalid for %s" % slot.get("path", "?"))
		var art := str(slot.get("art", ""))
		if art != "art" and art != "missing" and art != "placeholder":
			_fail("bad art flag %s" % art)
		var path := str(slot.get("path", ""))
		if art == "art":
			art_n += 1
			if path.begins_with("res://") and not FileAccess.file_exists(path) and not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
				_fail("art slot missing on disk %s" % path)
		elif art == "missing":
			missing_n += 1
			if path.begins_with("res://") and (FileAccess.file_exists(path) or FileAccess.file_exists(ProjectSettings.globalize_path(path))):
				_fail("existing file marked missing %s" % path)
		elif art == "placeholder":
			placeholder_n += 1
		if path == "res://assets/art/crystal/amethyst.png" and art == "missing":
			saw_amethyst = true
		if path == "runtime://generated/crystal/amethyst" and art == "placeholder":
			saw_runtime = true
		if path == "res://assets/tiles/Cube.png" and art == "art":
			saw_cube = true
	if not saw_amethyst:
		_fail("amethyst missing entry absent")
	if not saw_runtime:
		_fail("runtime crystal placeholder absent")
	if not saw_cube:
		_fail("Cube.png art entry absent")
	if int(file_doc.get("art_count", -1)) != art_n:
		_fail("art_count mismatch")
	if int(file_doc.get("missing_count", -1)) != missing_n:
		_fail("missing_count mismatch")
	if int(file_doc.get("placeholder_count", -1)) != placeholder_n:
		_fail("placeholder_count mismatch")
	if int(doc.get("slot_count", 0)) != slots.size():
		_fail("write_project slot_count drifted from the file")
	var md := FileAccess.get_file_as_string(md_path)
	if not md.contains("amethyst") or not md.contains("|"):
		_fail("markdown table missing")
	if _failed > 0:
		print("Texture manifest tests failed: %d" % _failed)
		quit(1)
		return
	print("slots=%d art=%d missing=%d placeholder=%d" % [slots.size(), art_n, missing_n, placeholder_n])
	print("All texture manifest tests OK")
	quit(0)
