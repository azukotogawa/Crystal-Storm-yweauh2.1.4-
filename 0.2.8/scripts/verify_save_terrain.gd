extends SceneTree

const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _SaveCodec = preload("res://systems/save_codec.gd")


func _init() -> void:
	var failed := false
	_TerrainEdits.reset()
	_TerrainEdits.dig(7, 7, 1)
	var before: float = _TerrainEdits.get_height_delta(7, 7)
	var blob: Dictionary = _TerrainEdits.to_dict()
	_TerrainEdits.reset()
	if not is_equal_approx(_TerrainEdits.get_height_delta(7, 7), 0.0):
		push_error("reset should clear edits")
		failed = true
	_TerrainEdits.load_from_dict(blob)
	var after: float = _TerrainEdits.get_height_delta(7, 7)
	if not is_equal_approx(before, after) or before >= -0.01:
		push_error("terrain edit roundtrip failed before=%s after=%s" % [before, after])
		failed = true
	else:
		print("OK terrain_edits save roundtrip delta=", after)
	if failed:
		quit(1)
	print("All save terrain tests OK")
	quit(0)