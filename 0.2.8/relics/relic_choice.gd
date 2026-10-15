class_name RelicChoice
extends RefCounted

const _RelicRegistry = preload("res://relics/relic_registry.gd")
const _RelicChoicePanel = preload("res://ui/relic_choice_panel.gd")

const POOL: Array[StringName] = [
	&"mason_glove",
	&"flow_anchor",
	&"crystal_ward",
	&"pathfinder_charm",
	&"ruin_seal",
]


static func roll(seed: int) -> Array[StringName]:
	_RelicRegistry.ensure_builtins()
	var out: Array[StringName] = []
	var start := posmod(seed, POOL.size())
	for step in POOL.size():
		var relic_id: StringName = POOL[(start + step) % POOL.size()]
		if relic_id in out:
			continue
		if _RelicRegistry.get_def(relic_id) == null:
			continue
		out.append(relic_id)
		if out.size() >= 3:
			break
	return out


static func present(tree: SceneTree, relic_mgr, seed: int, title: String) -> StringName:
	var ids := roll(seed)
	if ids.is_empty():
		return &""
	var overlay = null
	if tree:
		overlay = tree.get_first_node_in_group("game_overlay")
	if overlay != null and is_instance_valid(overlay):
		_RelicChoicePanel.open(tree, relic_mgr, ids, title)
		return &""
	if relic_mgr and relic_mgr.has_method("equip"):
		relic_mgr.equip(ids[0])
	return ids[0]
