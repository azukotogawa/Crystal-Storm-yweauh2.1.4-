class_name SurfaceLoot
extends RefCounted

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _Voxels = preload("res://helpers/voxel_types.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
const _WorldGen = preload("res://config/world_gen_config.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")

static var ENABLED: bool = true

const VEIN_CHANCE := 0.035
const RARE_ORE_CHANCE := 0.006
const ENCOUNTER_CHANCE := 0.01
const TRADER_SHARE := 0.5
const VEIN_LENGTH := 4
const VEIN_MIN := 3
const MIN_SPACING := 14
const ORIGIN_CLEAR := 48.0
const WAKE_CAP := 2
const REGION_MIN := Vector2i(-16, -16)
const REGION_MAX := Vector2i(15, 15)
const SEED_SALT := 77041

const _COMMON: Array[String] = ["stone", "wood", "herb"]
const _PACK: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]


static func config_rates(cfg = null) -> Dictionary:
	var vein := VEIN_CHANCE
	var rare := RARE_ORE_CHANCE
	var encounter := ENCOUNTER_CHANCE
	var trader := TRADER_SHARE
	if cfg != null:
		if "surface_vein_chance" in cfg:
			vein = float(cfg.surface_vein_chance)
		if "rare_ore_chance" in cfg:
			rare = float(cfg.rare_ore_chance)
		if "encounter_chance" in cfg:
			encounter = float(cfg.encounter_chance)
		if "trader_share" in cfg:
			trader = float(cfg.trader_share)
	vein = clampf(vein, 0.0, 0.25)
	rare = clampf(rare, 0.0, vein if vein > 0.0 else 0.0)
	encounter = clampf(encounter, 0.0, 0.1)
	trader = clampf(trader, 0.0, 1.0)
	return {
		"surface_vein_chance": vein,
		"rare_ore_chance": rare,
		"encounter_chance": encounter,
		"trader_share": trader,
	}


static func plan(world, rates: Dictionary = {}) -> Dictionary:
	var empty := {"veins": [], "encounters": []}
	if world == null:
		return empty
	var used := config_rates(rates if not rates.is_empty() else _world_cfg(world))
	var seed_value := int(world.world_seed) + SEED_SALT
	var veins: Array[Dictionary] = []
	var encounters: Array[Dictionary] = []
	var anchors: Array[Vector2i] = []
	var trader_n := 0
	var size := int(_ChunkData.SIZE)
	for cz in range(REGION_MIN.y, REGION_MAX.y + 1):
		for cx in range(REGION_MIN.x, REGION_MAX.x + 1):
			var vein_roll := _mix(seed_value, cx, cz, 1)
			var enc_roll := _mix(seed_value, cx, cz, 2)
			if _hit(vein_roll, float(used.surface_vein_chance)):
				var vein := _vein_at(world, seed_value, cx, cz, size, vein_roll, used, anchors)
				if not vein.is_empty():
					veins.append(vein)
					anchors.append(vein.get("origin", Vector2i.ZERO))
			if _hit(enc_roll, float(used.encounter_chance)):
				var want_trader := _wants_trader(encounters.size(), trader_n, float(used.trader_share))
				var site := _encounter_at(world, cx, cz, size, enc_roll, _mix(seed_value, cx, cz, 4), want_trader, anchors)
				if not site.is_empty():
					encounters.append(site)
					anchors.append(site.get("world_pos", Vector2i.ZERO))
					if str(site.get("encounter", "")) == "trader":
						trader_n += 1
	return {"veins": veins, "encounters": encounters}


static func place(world, rates: Dictionary = {}) -> int:
	if not ENABLED or world == null:
		return 0
	return install(plan(world, rates))


static func install(planned: Dictionary) -> int:
	var placed := 0
	for vein_v in planned.get("veins", []):
		var vein: Dictionary = vein_v
		var item_id := str(vein.get("item_id", ""))
		var tile := int(vein.get("tile", _Voxels.STONE))
		var rare := bool(vein.get("rare", false))
		for cell_v in vein.get("cells", []):
			var cell: Vector2i = cell_v
			if not _FeatureRegistry.get_feature(cell.x, cell.y).is_empty():
				continue
			_FeatureRegistry.register_feature(cell.x, cell.y, _WorldFeatureTypes.FeatureKind.VEIN, {
				"vein": true,
				"item_id": item_id,
				"rare": rare,
				"center": vein.get("origin", cell),
			})
			_FeatureRegistry.set_tile_override(cell.x, cell.y, tile, true)
			placed += 1
	for site_v in planned.get("encounters", []):
		var site: Dictionary = site_v
		var pos: Vector2i = site.get("world_pos", Vector2i.ZERO)
		if not _FeatureRegistry.get_feature(pos.x, pos.y).is_empty():
			continue
		_FeatureRegistry.register_spawn_data(pos.x, pos.y, _WorldFeatureTypes.FeatureKind.ENCOUNTER, site)
		placed += 1
	return placed


static func take_drop(wx: int, wz: int) -> String:
	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	if not bool(feat.get("vein", false)):
		return ""
	var item_id := str(feat.get("item_id", ""))
	_FeatureRegistry.clear_feature(wx, wz)
	_FeatureRegistry.clear_tile_override(wx, wz)
	return item_id


static func try_trade(inventory, wx: int, wz: int) -> bool:
	if inventory == null:
		return false
	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	if str(feat.get("encounter", "")) != "trader" or bool(feat.get("spent", false)):
		return false
	var pay_id := str(feat.get("pay_id", ""))
	var give_id := str(feat.get("give_id", ""))
	var pay_n := int(feat.get("pay_count", 0))
	var give_n := int(feat.get("give_count", 0))
	if pay_id.is_empty() or give_id.is_empty() or pay_n < 1 or give_n < 1:
		return false
	if not inventory.has_method("consume_item") or not inventory.has_method("add_item"):
		return false
	if not bool(inventory.consume_item(pay_id, pay_n)):
		return false
	if int(inventory.add_item(give_id, give_n)) != 0:
		inventory.add_item(pay_id, pay_n)
		return false
	var next := feat.duplicate()
	next["spent"] = true
	_FeatureRegistry.register_feature(wx, wz, _WorldFeatureTypes.FeatureKind.ENCOUNTER, next)
	return true


static func brain_id(encounter: String) -> StringName:
	if encounter == "trader":
		return &"wandering_trader"
	return &"ambush"


static func tint_for(encounter: String) -> Color:
	if encounter == "trader":
		return Color(0.55, 0.42, 0.28)
	return Color(0.45, 0.22, 0.18)


static func spawn_cells(site: Dictionary) -> Array[Vector2i]:
	var origin := _as_cell(site.get("world_pos", Vector2i.ZERO))
	if str(site.get("encounter", "")) == "trader":
		return [origin]
	var out: Array[Vector2i] = []
	for step_v in site.get("pack", []):
		out.append(origin + _as_cell(step_v))
	if out.is_empty():
		out.append(origin)
	return out


static func _world_cfg(world):
	if world != null and "world_config" in world and world.world_config != null:
		return world.world_config
	return _WorldGen.create_default()


static func _vein_at(world, seed_value: int, cx: int, cz: int, size: int, roll: int, rates: Dictionary, anchors: Array[Vector2i]) -> Dictionary:
	var origin := _chunk_cell(cx, cz, size, roll)
	if not _anchor_ok(world, origin, anchors):
		return {}
	var rare := _hit(_mix(seed_value, cx, cz, 3), _rare_ratio(rates))
	var item_id := "rare_ore" if rare else _COMMON[roll % _COMMON.size()]
	var tile := _tile_for(item_id)
	var step := Vector2i(1, 0) if (roll % 2) == 0 else Vector2i(0, 1)
	var cells: Array[Vector2i] = []
	for i in VEIN_LENGTH:
		var cell := origin + step * i
		if not _cell_open(world, cell):
			continue
		cells.append(cell)
	if cells.size() < VEIN_MIN:
		return {}
	return {
		"origin": origin,
		"cells": cells,
		"item_id": item_id,
		"tile": tile,
		"rare": rare,
	}


static func _wants_trader(placed: int, traders: int, share: float) -> bool:
	if share <= 0.0:
		return false
	if share >= 1.0:
		return true
	return float(traders) < float(placed + 1) * share


static func _encounter_at(world, cx: int, cz: int, size: int, roll: int, kind_roll: int, trader: bool, anchors: Array[Vector2i]) -> Dictionary:
	var origin := _chunk_cell(cx, cz, size, roll)
	if not _anchor_ok(world, origin, anchors):
		return {}
	if trader:
		var offer := _offer(kind_roll)
		return {
			"world_pos": origin,
			"encounter": "trader",
			"pay_id": offer.pay_id,
			"pay_count": offer.pay_count,
			"give_id": offer.give_id,
			"give_count": offer.give_count,
			"spent": false,
		}
	var pack: Array[Vector2i] = []
	for step in _PACK:
		var cell := origin + step
		if _cell_open(world, cell):
			pack.append(step)
	if pack.size() < 1:
		return {}
	return {
		"world_pos": origin,
		"encounter": "ambush",
		"pack": pack,
	}


static func _offer(roll: int) -> Dictionary:
	match roll % 3:
		0:
			return {"pay_id": "stone", "pay_count": 3, "give_id": "herb", "give_count": 2}
		1:
			return {"pay_id": "stone", "pay_count": 4, "give_id": "rare_ore", "give_count": 1}
		_:
			return {"pay_id": "wood", "pay_count": 3, "give_id": "stone", "give_count": 4}


static func _tile_for(item_id: String) -> int:
	match item_id:
		"wood":
			return _Voxels.TREE_TRUNK
		"herb":
			return _Voxels.BASIN
		"rare_ore":
			return _Voxels.CRYSTAL_VEIN
		_:
			return _Voxels.STONE2


static func _rare_ratio(rates: Dictionary) -> float:
	var vein := float(rates.get("surface_vein_chance", 0.0))
	if vein <= 0.0:
		return 0.0
	return float(rates.get("rare_ore_chance", 0.0)) / vein


static func _anchor_ok(world, origin: Vector2i, anchors: Array[Vector2i]) -> bool:
	if Vector2(origin).length() < ORIGIN_CLEAR:
		return false
	if not _WorldBorder.is_playable(float(origin.x), float(origin.y)):
		return false
	if not _cell_open(world, origin):
		return false
	for other in anchors:
		if Vector2(origin).distance_to(Vector2(other)) < float(MIN_SPACING):
			return false
	return true


static func _cell_open(world, cell: Vector2i) -> bool:
	if world == null or not world.has_method("get_tile_type"):
		return false
	var tile := int(world.get_tile_type(float(cell.x), float(cell.y)))
	if tile == _Voxels.RIVER or tile == _Voxels.WATER:
		return false
	var feat: Dictionary = _FeatureRegistry.get_feature(cell.x, cell.y)
	if not feat.is_empty():
		return false
	return true


static func _chunk_cell(cx: int, cz: int, size: int, roll: int) -> Vector2i:
	var lx := 2 + (roll % (size - 4))
	var lz := 2 + (int(roll / 7) % (size - 4))
	return Vector2i(cx * size + lx, cz * size + lz)


static func _hit(roll: int, chance: float) -> bool:
	if chance <= 0.0:
		return false
	if chance >= 1.0:
		return true
	return (roll % 10000) < int(round(chance * 10000.0))


static func _mix(seed_value: int, cx: int, cz: int, salt: int) -> int:
	var n: int = int(seed_value) * 374761393 + int(cx) * 668265263 + int(cz) * 2146121005 + int(salt) * 1274126177
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	if n < 0:
		n = -n
	if n < 0:
		n = 0
	return n


static func _as_cell(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO
