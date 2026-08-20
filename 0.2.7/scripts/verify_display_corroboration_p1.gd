extends SceneTree
## P1 contract: display + smoke probes corroborate recent presentation fixes.


const DISPLAY := "res://scripts/display_session_probe.gd"
const SMOKE := "res://scripts/smoke_gameplay.gd"
const HELPERS := "res://scripts/smoke_probe_helpers.gd"

const REQUIRED: PackedStringArray = [
	"audit_spawn_markers",
	"audit_ramp_descent_walk",
	"audit_vegetation_billboard_distance",
	"audit_entity_billboard_distance",
	"Pre-rebuild collision",
	"Build modifier",
	"Crystal settling config",
	"Vegetation billboard distance",
	"Entity billboard distance",
	"audit_terrain_atlas_style",
	"Terrain atlas style",
	"audit_vegetation_prop_shapes",
	"Vegetation prop shapes",
	"Highlight surface lift",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var helpers_src := FileAccess.get_file_as_string(ProjectSettings.globalize_path(HELPERS))
	for fn in [
		"audit_spawn_markers",
		"audit_ramp_descent_walk",
		"audit_vegetation_billboard_distance",
		"audit_entity_billboard_distance",
		"audit_terrain_atlas_style",
		"audit_vegetation_prop_shapes",
	]:
		if fn not in helpers_src:
			push_error("smoke_probe_helpers missing %s" % fn)
			failed = true
		else:
			print("OK smoke_probe_helpers.%s" % fn)

	for path in [DISPLAY, SMOKE]:
		var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(path))
		if text.is_empty():
			push_error("missing %s" % path)
			failed = true
			continue
		for req in REQUIRED:
			if req not in text:
				push_error("%s missing %s" % [path, req])
				failed = true
			else:
				print("OK %s has %s" % [path.get_file(), req])

	if failed:
		quit(1)
		return
	print("All display corroboration P1 tests OK")
	quit(0)