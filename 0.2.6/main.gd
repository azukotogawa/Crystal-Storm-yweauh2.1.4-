extends Node3D
## Root scene script for scenes/main.tscn.
##
## Boot is owned by CompositionRoot (child node):
##   CONFIGURED → QUALITY_APPLIED → FEATURES_SEEDED → CHUNKS_CREATED
##   → INITIAL_STREAM_READY → VISUALS_COMMITTED → RUNNING
## Critical services are registered and handed off explicitly; groups remain
## compatibility adapters for UI/debug discovery.
##
## LoadingScreen (CanvasLayer) presents stage progress and fades out at
## INITIAL_STREAM_READY — gameplay interaction is available while remaining
## boot stages finish under the fade.


func _ready() -> void:
	var root = get_node_or_null("CompositionRoot")
	var loading = get_node_or_null("LoadingLayer/LoadingScreen")
	if loading == null:
		loading = get_node_or_null("CanvasLayer/LoadingScreen")
	if loading and root and loading.has_method("bind_composition_root"):
		loading.bind_composition_root(root)
	if root and root.has_method("boot_async"):
		await root.boot_async()
	else:
		push_warning("[Main] CompositionRoot missing — legacy child _ready boot only")
