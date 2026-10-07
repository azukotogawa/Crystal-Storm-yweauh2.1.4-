extends SceneTree
## Regression: dig/build/remove/place use INPUT_CONTRACT interaction range (8 columns).

const _ActionTargeting = preload("res://player/action_targeting.gd")


func _init() -> void:
	var failed := false
	if absf(_ActionTargeting.INTERACTION_RANGE - 8.0) > 0.001:
		push_error("ActionTargeting.INTERACTION_RANGE must be 8.0, got %s" % _ActionTargeting.INTERACTION_RANGE)
		failed = true
	else:
		print("OK INTERACTION_RANGE=8")

	var at_src := (_ActionTargeting as GDScript).source_code
	if "const INTERACTION_RANGE := 8.0" not in at_src:
		push_error("action_targeting must declare INTERACTION_RANGE := 8.0")
		failed = true

	var weapon_src := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	if "_resolve_terrain_target(3.0)" in weapon_src:
		push_error("weapon_controller still hardcodes terrain range 3.0")
		failed = true
	elif "_ActionTargeting.INTERACTION_RANGE" not in weapon_src:
		push_error("weapon_controller must use ActionTargeting.INTERACTION_RANGE")
		failed = true
	else:
		print("OK weapon terrain paths use INTERACTION_RANGE")

	var hl_src := (load("res://player/target_highlight.gd") as GDScript).source_code
	if "BUILD_PREVIEW_RANGE := 8.0" not in hl_src:
		push_error("target_highlight BUILD_PREVIEW_RANGE must be 8.0")
		failed = true
	elif "INTERACTION_RANGE" not in hl_src:
		push_error("target_highlight _active_range must use INTERACTION_RANGE for dig/build")
		failed = true
	else:
		print("OK highlight dig/build reach is 8")

	if failed:
		quit(1)
	print("All interaction-range tests OK")
	quit(0)
