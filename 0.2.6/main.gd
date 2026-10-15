extends Node3D


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
