extends SceneTree

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")


func _init() -> void:
	var failed := false
	_FeatureRegistry.reset()
	_FeatureRegistry.register_feature(10, 12, _WorldFeatureTypes.FeatureKind.RUIN, {
		"center": [10, 12],
	})
	var centers: Array = _FeatureRegistry.get_ruin_centers()
	if centers.size() != 1:
		push_error("expected 1 ruin center, got %d" % centers.size())
		failed = true
	elif centers[0] != Vector2i(10, 12):
		push_error("ruin center coerce failed: %s" % str(centers[0]))
		failed = true
	else:
		print("OK get_ruin_centers coerces Array center")
	if failed:
		quit(1)
	print("All ruin center tests OK")
	quit(0)