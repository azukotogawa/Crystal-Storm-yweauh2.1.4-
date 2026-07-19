extends Node3D
## Root scene script for scenes/main.tscn.
##
## Boot is owned by CompositionRoot (child node):
##   CONFIGURED → QUALITY_APPLIED → FEATURES_SEEDED → CHUNKS_CREATED
##   → INITIAL_STREAM_READY → VISUALS_COMMITTED → RUNNING
## Critical services are registered and handed off explicitly; groups remain
## compatibility adapters for UI/debug discovery.


func _ready() -> void:
	var root = get_node_or_null("CompositionRoot")
	if root and root.has_method("boot_async"):
		await root.boot_async()
	else:
		push_warning("[Main] CompositionRoot missing — legacy child _ready boot only")
