class_name ScenarioPresets
extends RefCounted

const _ItemTypes = preload("res://helpers/item_types.gd")


static func list_ids() -> PackedStringArray:
	return PackedStringArray([
		"dig_flat", "combat_ring", "crystal_edge", "builder", "smoke_origin"
	])


static func apply(tree: SceneTree, scenario_id: String) -> String:
	var id := scenario_id.strip_edges().to_lower()
	match id:
		"dig_flat":
			return _tp_player(tree, 8.0, 8.0) + "; " + _give_starter_kit(tree, true)
		"combat_ring":
			return _tp_player(tree, 11.0, 11.0) + "; " + _give_starter_kit(tree, false) + "; sword equipped"
		"crystal_edge":
			return _tp_player(tree, -6.0, 6.0) + "; near relocated crystal origin"
		"builder":
			return _tp_player(tree, 5.0, 5.0) + "; " + _give_build_kit(tree)
		"smoke_origin":
			return _tp_player(tree, 2.5, 4.5) + "; smoke probe start pose"
		_:
			return "Unknown scenario '%s'. Try: %s" % [scenario_id, ", ".join(list_ids())]


static func _tp_player(tree: SceneTree, wx: float, wz: float) -> String:
	var player: Player = tree.get_first_node_in_group("player") as Player
	if player == null:
		return "Player missing"
	player.voxel_position.x = wx + 0.5
	player.voxel_position.z = wz + 0.5
	if player.has_method("_sync_global_from_voxel"):
		player.call("_sync_global_from_voxel")
	if player.has_method("_snap_to_ground"):
		player.call("_snap_to_ground")
	return "tp(%.0f,%.0f)" % [wx, wz]


static func _give_starter_kit(tree: SceneTree, with_pick: bool) -> String:
	var player: Node = tree.get_first_node_in_group("player")
	if player == null or not ("inventory" in player):
		return "no inventory"
	var inv: Inventory = player.inventory
	if inv == null:
		return "no inventory"
	inv.add_item("wooden_sword", 1)
	if with_pick:
		inv.add_item("stone_pick", 1)
	inv.add_item("stone", 8)
	var weapon: Node = player.get_node_or_null("WeaponController")
	if weapon and weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(0 if not with_pick else 1)
	return "kit granted"


static func _give_build_kit(tree: SceneTree) -> String:
	var player: Node = tree.get_first_node_in_group("player")
	if player == null or not ("inventory" in player):
		return "no inventory"
	var inv: Inventory = player.inventory
	inv.add_item("stone", 16)
	inv.add_item("wooden_sword", 1)
	var weapon: Node = player.get_node_or_null("WeaponController")
	if weapon and weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(0)
	return "builder kit"