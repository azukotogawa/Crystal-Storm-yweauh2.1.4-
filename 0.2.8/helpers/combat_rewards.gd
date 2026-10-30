class_name CombatRewards
extends RefCounted

const _Progression = preload("res://systems/progression_service.gd")


static func grant_player_kill(tree: SceneTree, kind: StringName, display_name: String) -> Dictionary:
	var empty := {"item_id": "", "count": 0, "label": ""}
	if tree == null:
		return empty
	var gm = tree.get_first_node_in_group("game_manager")
	if gm and gm.has_method("note_enemy_killed"):
		gm.note_enemy_killed(_Progression.kill_tier(kind))
	var label: String = display_name if display_name != "" else str(kind).replace("_", " ")
	var loot: Dictionary = _loot_for_kind(kind)
	var item_id: String = str(loot.get("item_id", ""))
	var count: int = int(loot.get("count", 0))
	if item_id.is_empty() or count <= 0:
		var note := "%s down" % label
		_toast(tree, note)
		return {"item_id": "", "count": 0, "label": note}
	var player = tree.get_first_node_in_group("player")
	if player == null:
		return empty
	var inv = player.get("inventory")
	if inv == null or not inv.has_method("add_item"):
		return empty
	inv.add_item(item_id, count)
	var audio = tree.root.get_node_or_null("AudioManager") if tree.root else null
	if audio and audio.has_method("play_sfx"):
		audio.play_sfx("pickup")
	var toast := "%s down — +%d %s for the maze" % [label, count, item_id]
	_toast(tree, toast)
	return {"item_id": item_id, "count": count, "label": toast}


static func _toast(tree: SceneTree, text: String) -> void:
	if tree == null or text == "":
		return
	var overlay = tree.get_first_node_in_group("game_overlay")
	if overlay and overlay.has_method("_show_toast"):
		overlay.call("_show_toast", text)


static func _loot_for_kind(kind: StringName) -> Dictionary:
	match kind:
		&"town_militia", &"town_villager":
			return {"item_id": "", "count": 0}
		&"crystal_mite", &"thornling", &"shard_guard", &"crystal_stag", &"corrupted_beast", &"farm_bomber", &"crystal_enemy":
			return {"item_id": "stone", "count": 1}
		&"spawn_elite":
			return {"item_id": "crystal_bomb", "count": 1}
		&"origin_warden":
			return {"item_id": "crystal_weave", "count": 1}
		&"boar":
			return {"item_id": "wood", "count": 1}
		&"rabbit", &"deer", &"bird", &"fox", &"goat", &"duck", &"sheep", &"wolf", &"heron":
			return {"item_id": "herb", "count": 1}
		_:
			return {"item_id": "stone", "count": 1}
