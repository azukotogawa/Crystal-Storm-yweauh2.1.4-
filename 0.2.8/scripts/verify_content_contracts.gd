extends SceneTree

const _ItemTypes = preload("res://helpers/item_types.gd")
const _ItemDef = preload("res://config/item_def.gd")
const _BuildableDef = preload("res://config/buildable_def.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _CrystalEvolution = preload("res://crystal/crystal_evolution.gd")
const _AbsorptionUnlockDef = preload("res://config/absorption_unlock_def.gd")
const _GameConfig = preload("res://config/game_config.gd")
const _RelicRegistry = preload("res://relics/relic_registry.gd")
const _RelicManager = preload("res://relics/relic_manager.gd")


var _failed: int = 0


func _init() -> void:
	_run()
	if _failed == 0:
		print("All content contract tests OK")
		quit(0)
	else:
		push_error("verify_content_contracts: %d failure(s)" % _failed)
		quit(1)


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_test_item_def()
	_test_visual_id()
	_test_absorption_table()
	_test_relic_flow_mult()
	_test_break_and_place_rules()


func _test_item_def() -> void:
	_ItemTypes.reset()
	_ItemTypes.ensure_builtins()
	var stone = _ItemTypes.get_item_def("stone")
	if stone == null:
		_fail("stone ItemDef missing")
		return
	var lookup: Dictionary = _ItemTypes.get_def("stone")
	if str(lookup.get("name", "")) != "Stone":
		_fail("ItemTypes.get_def must keep dict API")
	if str(lookup.get("visual_id", "")) != "stone":
		_fail("item visual_id defaults to id")
	if not _ItemTypes.is_valid("wooden_sword"):
		_fail("wooden_sword should be valid after builtins")
	var extra := _ItemDef.new()
	extra.id = "copper"
	extra.display_name = "Copper"
	extra.visual_id = &"stone"
	_ItemTypes.register(extra)
	if str(_ItemTypes.get_def("copper").get("visual_id", "")) != "stone":
		_fail("registered ItemDef visual_id not visible via get_def")
	else:
		print("OK ItemDef façade + visual_id reuse")


func _test_visual_id() -> void:
	_BuildingRegistry.reset()
	_BuildingRegistry.ensure_builtins()
	var wall = _BuildingRegistry.get_def(&"stone_wall")
	if wall == null or wall.resolved_visual_id() != &"stone_wall":
		_fail("stone_wall visual defaults to id")
	var palisade := _BuildableDef.new()
	palisade.id = &"copper_wall"
	palisade.visual_id = &"stone_wall"
	if palisade.resolved_visual_id() != &"stone_wall":
		_fail("new buildable must reuse authored visual_id")
	else:
		print("OK buildable visual_id reuse")


func _test_absorption_table() -> void:
	var evo = _CrystalEvolution.new()
	evo.configure([])
	if not evo.is_unlocked(&"crystal_mite"):
		_fail("builtin table must unlock crystal_mite at start")
	var custom := _AbsorptionUnlockDef.new()
	custom.source_id = &"grass"
	custom.enemy_id = &"crystal_mite"
	custom.threshold = 99
	custom.unlock_at_start = false
	var evo2 = _CrystalEvolution.new()
	evo2.configure([custom])
	if evo2.is_unlocked(&"crystal_mite"):
		_fail("mite must not unlock when table omits unlock_at_start")
	else:
		print("OK AbsorptionUnlockDef is the only mite unlock")
	var cfg = _GameConfig.create_default()
	if cfg.absorption_unlocks.is_empty():
		_fail("GameConfig.ensure_defaults must ingest absorption_unlocks")
	else:
		print("OK GameConfig absorption_unlocks ingest")


func _test_relic_flow_mult() -> void:
	_RelicRegistry.reset()
	_RelicRegistry.ensure_builtins()
	var ward = _RelicRegistry.get_def(&"crystal_ward")
	if ward == null or ward.crystal_flow_mult >= 1.0:
		_fail("crystal_ward must dampen crystal_flow_mult")
		return
	var rm = _RelicManager.new()
	rm.equip(&"crystal_ward")
	var mult: float = rm.get_crystal_flow_mult()
	if mult >= 1.0 or absf(mult - ward.crystal_flow_mult) > 0.001:
		_fail("relic flow_mult expected %.2f got %.2f" % [ward.crystal_flow_mult, mult])
	else:
		print("OK relic crystal_flow_mult=%.2f" % mult)


## Only dig tools break blocks. Right-click abilities never place. Hammer wind-up stays.
func _test_break_and_place_rules() -> void:
	_ItemTypes.reset()
	_ItemTypes.ensure_builtins()
	if not _ItemTypes.breaks_blocks("stone_pick"):
		_fail("stone_pick must break blocks")
	var no_break: PackedStringArray = [
		"wooden_sword", "crystal_hammer", "shortbow", "spear", "sling",
		"stone", "wood", "herb", "crystal_bomb", "leather_armor", "crystal_shard", "torch",
	]
	for item_id in no_break:
		if _ItemTypes.breaks_blocks(item_id):
			_fail("%s must not break blocks" % item_id)
	var abilities: PackedStringArray = [
		"herb", "crystal_bomb", "leather_armor", "stone_plate", "crystal_weave",
	]
	for item_id in abilities:
		if not _ItemTypes.has_right_click_ability(item_id):
			_fail("%s must have a right-click ability" % item_id)
		if _ItemTypes.is_placeable_block(item_id):
			_fail("%s must not be a placeable block" % item_id)
	var can_place: PackedStringArray = [
		"stone", "wood", "stone_pick", "wooden_sword", "crystal_hammer", "shortbow",
	]
	for item_id in can_place:
		if _ItemTypes.has_right_click_ability(item_id):
			_fail("%s must not have a right-click ability" % item_id)
	if not _ItemTypes.is_placeable_block("stone") or not _ItemTypes.is_placeable_block("wood"):
		_fail("stone and wood must be placeable blocks")
	var hammer := _ItemTypes.get_def("crystal_hammer")
	if not is_equal_approx(float(hammer.get("impact_ratio", -1.0)), 0.62):
		_fail("hammer pre-hit impact_ratio must stay 0.62")
	elif not is_equal_approx(float(hammer.get("anim_duration", -1.0)), 1.1):
		_fail("hammer pre-hit anim_duration must stay 1.1")
	var src := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	if "func _try_dig_tool_or_fill_remove" in src:
		_fail("non-dig items must not have a fill dig path")
	var place_at := src.find("func _try_place_selected")
	var place_end := src.find("\nfunc ", place_at + 10)
	var place_body := src.substr(place_at, maxi(place_end - place_at, 0))
	if "if _held_has_right_click_ability():" not in place_body:
		_fail("_try_place_selected must return for a right-click ability")
	elif "try_dig_brush(" in place_body:
		_fail("place path must not dig")
	var dig_at := src.find("func _do_dig_attack")
	var dig_end := src.find("\nfunc ", dig_at + 10)
	var dig_body := src.substr(dig_at, maxi(dig_end - dig_at, 0))
	if "if not _is_active_dig_tool():" not in dig_body or "try_dig_brush(" not in dig_body:
		_fail("dig stroke must require a dig tool")
	elif _failed == 0:
		print("OK only dig tools break blocks; right-click abilities do not place")
