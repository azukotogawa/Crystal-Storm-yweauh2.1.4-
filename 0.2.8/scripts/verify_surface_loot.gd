extends SceneTree

const _Loot = preload("res://world/surface_loot.gd")
const _World = preload("res://world/InfiniteNoiseWorld.gd")
const _Features = preload("res://world/feature_registry.gd")
const _Types = preload("res://helpers/world_feature_types.gd")
const _Voxels = preload("res://helpers/voxel_types.gd")
const _Items = preload("res://helpers/item_types.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _Gen = preload("res://config/world_gen_config.gd")
const _Budget = preload("res://systems/frame_budget_scheduler.gd")
const _Brains = preload("res://entities/entity_brain_registry.gd")
const _Creatures = preload("res://helpers/voxel_creature_builder.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	_check_rates()
	_check_plan(44021)
	_check_plan(918337)
	_check_zero()
	_check_place_and_trade(44021)
	_check_flag_off(44021)
	_check_brains_and_budget()
	if _failed == 0:
		print("All surface loot tests OK")
		quit(0)
	else:
		push_error("verify_surface_loot: %d failure(s)" % _failed)
		quit(1)


func _check_rates() -> void:
	var cfg = _Gen.create_default()
	var rates: Dictionary = _Loot.config_rates(cfg)
	if not is_equal_approx(float(rates.surface_vein_chance), _Loot.VEIN_CHANCE):
		_fail("vein chance drifted")
		return
	if not is_equal_approx(float(rates.rare_ore_chance), _Loot.RARE_ORE_CHANCE):
		_fail("rare ore chance drifted")
		return
	if not is_equal_approx(float(rates.encounter_chance), _Loot.ENCOUNTER_CHANCE):
		_fail("encounter chance drifted")
		return
	if not is_equal_approx(float(rates.trader_share), _Loot.TRADER_SHARE):
		_fail("trader share drifted")
		return
	if _Loot.VEIN_CHANCE > 0.08 or _Loot.RARE_ORE_CHANCE > 0.02 or _Loot.ENCOUNTER_CHANCE > 0.03:
		_fail("surface loot rates are not low")
		return
	if _Loot.RARE_ORE_CHANCE >= _Loot.VEIN_CHANCE:
		_fail("rare ore is not rarer than a vein")
		return
	if _Loot.WAKE_CAP != 2 or _Loot.VEIN_MIN < 3 or _Loot.VEIN_LENGTH < _Loot.VEIN_MIN:
		_fail("vein length or wake cap")
		return
	print("OK rates vein=%.3f rare=%.3f encounter=%.3f trader=%.2f" % [_Loot.VEIN_CHANCE, _Loot.RARE_ORE_CHANCE, _Loot.ENCOUNTER_CHANCE, _Loot.TRADER_SHARE])


func _check_plan(seed_value: int) -> void:
	var world = _World.new(seed_value)
	var first: Dictionary = _Loot.plan(world)
	var again: Dictionary = _Loot.plan(world)
	if _signature(first) != _signature(again):
		_fail("plan seed %d is not deterministic" % seed_value)
		return
	var veins: Array = first.get("veins", [])
	var sites: Array = first.get("encounters", [])
	if veins.size() < 4 or veins.size() > 90:
		_fail("seed %d vein sites %d" % [seed_value, veins.size()])
		return
	if sites.size() < 2 or sites.size() > 40:
		_fail("seed %d encounters %d" % [seed_value, sites.size()])
		return
	var rare := 0
	var common := 0
	var anchors: Array[Vector2i] = []
	for vein_v in veins:
		var vein: Dictionary = vein_v
		var cells: Array = vein.get("cells", [])
		if cells.size() < _Loot.VEIN_MIN or cells.size() > _Loot.VEIN_LENGTH:
			_fail("vein length %d" % cells.size())
			return
		var item_id := str(vein.get("item_id", ""))
		if bool(vein.get("rare", false)):
			rare += 1
			if item_id != "rare_ore" or int(vein.get("tile", -1)) != _Voxels.CRYSTAL_VEIN:
				_fail("rare vein is not rare ore")
				return
		else:
			common += 1
			if item_id not in ["stone", "wood", "herb"]:
				_fail("common vein item %s" % item_id)
				return
			if int(vein.get("tile", -1)) == _Voxels.CRYSTAL_VEIN:
				_fail("common vein uses the rare tile")
				return
		var origin: Vector2i = vein.get("origin", Vector2i.ZERO)
		if not _spaced(origin, anchors):
			_fail("vein %s is crowded" % origin)
			return
		anchors.append(origin)
	var traders := 0
	var ambushes := 0
	for site_v in sites:
		var site: Dictionary = site_v
		var origin: Vector2i = site.get("world_pos", Vector2i.ZERO)
		if not _spaced(origin, anchors):
			_fail("encounter %s is crowded" % origin)
			return
		anchors.append(origin)
		var kind := str(site.get("encounter", ""))
		if kind == "trader":
			traders += 1
			if int(site.get("pay_count", 0)) < 1 or str(site.get("give_id", "")).is_empty():
				_fail("trader has no offer")
				return
			if _Loot.spawn_cells(site).size() != 1:
				_fail("trader spawns a pack")
				return
		elif kind == "ambush":
			ambushes += 1
			var pack := _Loot.spawn_cells(site)
			if pack.size() < 1 or pack.size() > _Loot.WAKE_CAP:
				_fail("ambush pack %d" % pack.size())
				return
		else:
			_fail("unknown encounter %s" % kind)
			return
	if rare < 1 or common < 1 or traders < 1 or ambushes < 1:
		_fail("seed %d rare=%d common=%d traders=%d ambushes=%d" % [seed_value, rare, common, traders, ambushes])
		return
	if rare >= common:
		_fail("seed %d rare veins are not rarer than common" % seed_value)
		return
	print("OK surface plan seed=%d veins=%d rare=%d encounters=%d traders=%d ambushes=%d" % [seed_value, veins.size(), rare, sites.size(), traders, ambushes])


func _check_zero() -> void:
	var world = _World.new(7)
	var planned: Dictionary = _Loot.plan(world, {
		"surface_vein_chance": 0.0,
		"rare_ore_chance": 0.0,
		"encounter_chance": 0.0,
		"trader_share": 0.5,
	})
	if not (planned.get("veins", []) as Array).is_empty() or not (planned.get("encounters", []) as Array).is_empty():
		_fail("zero chances still placed loot")
		return
	print("OK zero chances")


func _check_place_and_trade(seed_value: int) -> void:
	_Features.reset()
	_Items.reset()
	_Items.ensure_builtins()
	var world = _World.new(seed_value)
	var planned: Dictionary = _Loot.plan(world)
	var placed := _Loot.install(planned)
	if placed < 1:
		_fail("install placed nothing")
		return
	var rare_cell := Vector2i.ZERO
	var found_rare := false
	for vein_v in planned.get("veins", []):
		var vein: Dictionary = vein_v
		if not bool(vein.get("rare", false)):
			continue
		var cells: Array = vein.get("cells", [])
		if cells.is_empty():
			continue
		rare_cell = cells[0]
		found_rare = true
		break
	if not found_rare:
		_fail("no rare cell to dig")
		return
	if _Features.get_tile_override(rare_cell.x, rare_cell.y) != _Voxels.CRYSTAL_VEIN:
		_fail("rare ore is not visible as a crystal vein tile")
		return
	if _Loot.take_drop(rare_cell.x, rare_cell.y) != "rare_ore":
		_fail("digging a rare vein did not drop rare ore")
		return
	if _Loot.take_drop(rare_cell.x, rare_cell.y) != "":
		_fail("a dug vein dropped twice")
		return
	if _Features.get_tile_override(rare_cell.x, rare_cell.y) >= 0:
		_fail("dug vein kept its tile")
		return
	var trader := Vector2i.ZERO
	var pay_id := ""
	var pay_n := 0
	var give_id := ""
	for site_v in planned.get("encounters", []):
		var site: Dictionary = site_v
		if str(site.get("encounter", "")) != "trader":
			continue
		trader = site.get("world_pos", Vector2i.ZERO)
		pay_id = str(site.get("pay_id", ""))
		pay_n = int(site.get("pay_count", 0))
		give_id = str(site.get("give_id", ""))
		break
	if pay_id.is_empty():
		_fail("no trader to trade with")
		return
	var inv = _Inventory.new()
	if _Loot.try_trade(inv, trader.x, trader.y):
		_fail("trade succeeded with an empty pack")
		return
	inv.add_item(pay_id, pay_n)
	if not _Loot.try_trade(inv, trader.x, trader.y):
		_fail("trade did not take %d %s" % [pay_n, pay_id])
		return
	if inv.count_item(pay_id) != 0 or inv.count_item(give_id) < 1:
		_fail("trade left pay=%d give=%d" % [inv.count_item(pay_id), inv.count_item(give_id)])
		return
	inv.add_item(pay_id, pay_n)
	if _Loot.try_trade(inv, trader.x, trader.y):
		_fail("trader sold twice")
		return
	print("OK place=%d rare dig and one trade" % placed)


func _check_flag_off(seed_value: int) -> void:
	_Features.reset()
	var prior := _Loot.ENABLED
	_Loot.ENABLED = false
	var world = _World.new(seed_value)
	var placed := _Loot.place(world)
	_Loot.ENABLED = prior
	if placed != 0 or not _Features.get_entity_spawns().is_empty():
		_fail("flag off still placed %d" % placed)
		return
	print("OK flag off")


func _check_brains_and_budget() -> void:
	_Brains.reset()
	_Brains.ensure_builtins()
	var trader = _Brains.get_def(&"wandering_trader")
	var ambush = _Brains.get_def(&"ambush")
	if trader == null or ambush == null:
		_fail("missing encounter brains")
		return
	if float(trader.contact_damage) > 0.0 or float(trader.flee_distance) > 0.0:
		_fail("trader should wander and not hit")
		return
	if float(ambush.contact_damage) <= 0.0:
		_fail("ambush does no damage")
		return
	if _Creatures.parts_for(&"wandering_trader").is_empty() or _Creatures.parts_for(&"ambush").is_empty():
		_fail("encounter bodies have no voxel parts")
		return
	var units := int(_Budget.DEFAULT_MAX_UNITS[_Budget.SYS_ENTITY_SPAWN])
	var us := int(_Budget.DEFAULT_BUDGET_US[_Budget.SYS_ENTITY_SPAWN])
	if units != 2 or us != 1000:
		_fail("entity_spawn frame budget units=%d us=%d" % [units, us])
		return
	print("OK encounter brains wake=%d frame units=%d us=%d" % [_Loot.WAKE_CAP, units, us])


func _spaced(origin: Vector2i, anchors: Array[Vector2i]) -> bool:
	for other in anchors:
		if Vector2(origin).distance_to(Vector2(other)) < float(_Loot.MIN_SPACING):
			return false
	return true


func _signature(planned: Dictionary) -> String:
	var bits: PackedStringArray = []
	for vein_v in planned.get("veins", []):
		var vein: Dictionary = vein_v
		bits.append("v%s:%s" % [vein.get("origin", Vector2i.ZERO), vein.get("item_id", "")])
	for site_v in planned.get("encounters", []):
		var site: Dictionary = site_v
		bits.append("e%s:%s" % [site.get("world_pos", Vector2i.ZERO), site.get("encounter", "")])
	return "|".join(bits)
