extends SceneTree

const _Water = preload("res://helpers/water_locomotion.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

var _failed := 0


func _init() -> void:
	var ws = _WorldSettings.get_active()
	var height: float = ws.player_height()
	var layer: float = ws.layer_height()
	var cfg = GameFeelConfig.active()
	var depth: float = float(cfg.get("swim_visual_depth")) if "swim_visual_depth" in cfg else 0.0
	var helper = _Water.new()
	var has_drop: bool = helper.has_method("visual_drop")
	for surface in [10.0, 12.0, 20.0]:
		var sink: float = clampf(height * 0.55, layer * 0.45, height * 0.8)
		for feet in [surface - sink, surface - sink * 0.5, surface]:
			var info := {"submerged": true, "surface_y": surface, "float_y": surface - sink, "ground_y": surface - 3.0 * layer}
			var drop: float = helper.call("visual_drop", info, feet, height, depth) if has_drop else 0.0
			var shown: float = feet - drop
			var above: float = (shown + height - surface) / height
			if above > 0.25:
				_fail("surface %.1f feet %.2f: %.0f%% of the body above water" % [surface, feet, above * 100.0])
			else:
				print("OK surface %.1f feet %.2f drop %.2f above %.0f%%" % [surface, feet, drop, above * 100.0])
	if has_drop:
		var dry := _Water.dry(10.0)
		if float(helper.call("visual_drop", dry, 10.0, height, depth)) != 0.0:
			_fail("dry ground lowers the model")
	if depth < 0.6:
		_fail("swim_visual_depth %.2f too shallow" % depth)
	var src := FileAccess.get_file_as_string("res://player/player.gd")
	if src.find("_mesh_rest_y - _swim_visual_drop()") < 0:
		_fail("player mesh does not apply the swim visual drop")
	if _failed == 0:
		print("All swim visual depth tests OK")
		quit(0)
	else:
		quit(1)


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)