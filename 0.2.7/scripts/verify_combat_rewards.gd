extends SceneTree
## Player kills convert into maze materials.


const _CombatRewards = preload("res://helpers/combat_rewards.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")


class _FakePlayer extends Node:
	var inventory


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var src_e := (load("res://entities/crystal_enemy.gd") as GDScript).source_code
	if "grant_player_kill" not in src_e or "signal killed" not in src_e:
		push_error("crystal_enemy must grant loot and emit killed")
		failed = true
	else:
		print("OK crystal_enemy kill rewards wired")
	var src_w := (load("res://entities/world_entity.gd") as GDScript).source_code
	if "grant_player_kill" not in src_w:
		push_error("world_entity player-kills must grant loot")
		failed = true
	else:
		print("OK world_entity kill rewards wired")

	_ItemTypes.ensure_builtins()
	var player := _FakePlayer.new()
	player.inventory = _Inventory.new()
	root.add_child(player)
	player.add_to_group("player")

	var mite: Dictionary = _CombatRewards.grant_player_kill(self, &"crystal_mite", "Crystal Mite")
	if str(mite.get("item_id", "")) != "stone" or int(mite.get("count", 0)) < 1:
		push_error("mite kill should grant stone, got %s" % str(mite))
		failed = true
	elif player.inventory.count_item("stone") < 1:
		push_error("inventory should receive mite stone")
		failed = true
	else:
		print("OK mite kill → stone")

	var rabbit: Dictionary = _CombatRewards.grant_player_kill(self, &"rabbit", "Rabbit")
	if str(rabbit.get("item_id", "")) != "herb":
		push_error("rabbit kill should grant herb")
		failed = true
	else:
		print("OK rabbit kill → herb")

	var militia: Dictionary = _CombatRewards.grant_player_kill(self, &"town_militia", "Militia")
	if int(militia.get("count", 0)) != 0:
		push_error("militia kills must not grant loot")
		failed = true
	else:
		print("OK militia kill grants nothing")

	if failed:
		quit(1)
	print("All combat-reward tests OK")
	quit(0)
