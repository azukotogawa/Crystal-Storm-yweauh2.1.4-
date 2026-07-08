extends Node

## Optional debug harness — attach to Game root to verify visual node hierarchy.


func _ready() -> void:
	await get_tree().create_timer(3.0).timeout
	print("=== VISUAL HIERARCHY DEBUG ===")

	var wv = get_tree().get_first_node_in_group("world_visuals_root")
	if wv:
		for layer in ["Entities", "Vegetation", "Buildings", "SpawnMarkers", "CombatVFX"]:
			var n = wv.get_node_or_null(layer)
			print("%s: %s (%d children)" % [layer, n != null, n.get_child_count() if n else 0])

	var reg = get_tree().get_first_node_in_group("game_visual_registry")
	if reg and reg.has_method("ensure_ready"):
		await reg.ensure_ready()
	if reg and reg.has_method("get_sprite_texture"):
		var tex = reg.get_sprite_texture("rabbit")
		print("Rabbit texture:", tex != null)

	for entity in get_tree().get_nodes_in_group("world_entity"):
		var sprite: Sprite3D = entity.get_node_or_null("Sprite3D")
		var mesh: MeshInstance3D = entity.get_node_or_null("MeshInstance3D")
		print("Entity %s: Sprite3D=%s Mesh=%s" % [entity.name, sprite != null, mesh != null])
		break

	var veg = wv.get_node_or_null("Vegetation") if wv else null
	if veg and veg.get_child_count() > 0:
		var anchor: Node3D = veg.get_child(0)
		print("Vegetation sample anchor:", anchor.name, "Billboard=", anchor.get_node_or_null("Billboard") != null)

	var buildings = wv.get_node_or_null("Buildings") if wv else null
	if buildings and buildings.get_child_count() > 0:
		var banchor: Node3D = buildings.get_child(0)
		print("Building sample anchor:", banchor.name, "Mesh=", banchor.get_node_or_null("Mesh") != null)

	print("=== END ===")