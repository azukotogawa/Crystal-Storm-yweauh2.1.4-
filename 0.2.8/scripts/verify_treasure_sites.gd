extends SceneTree

const _Ruin = preload("res://world/ruin_manager.gd")
const _WorldState = preload("res://world/world_state.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _RelicRegistry = preload("res://relics/relic_registry.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	_check_flag_and_chests()
	_check_retired_stamp()
	_check_installed_chest()
	if _failed == 0:
		print("All treasure site tests OK")
		quit(0)
	else:
		push_error("verify_treasure_sites: %d failure(s)" % _failed)
		quit(1)


func _check_flag_and_chests() -> void:
	if not _Ruin.WORLD_DENSITY:
		_fail("WORLD_DENSITY must default true")
		return
	_RelicRegistry.reset()
	_RelicRegistry.ensure_builtins()
	var pool: Array[StringName] = _RelicRegistry.ruin_loot_pool()
	if pool.is_empty():
		_fail("ruin loot pool empty")
		return
	var seen: Dictionary = {}
	for i in 6:
		var center := Vector2i(80 + i * 40, -30 - i * 15)
		var site: Dictionary = _Ruin.treasure_site(i, center)
		var again: Dictionary = _Ruin.treasure_site(i, center)
		if str(site.get("chest", {})) != str(again.get("chest", {})) or str(site.get("lore", "")) != str(again.get("lore", "")):
			_fail("treasure chest is not deterministic at %s" % center)
			return
		if not bool(site.get("treasure_site", false)):
			_fail("site %d is not a treasure site" % i)
			return
		var lore := str(site.get("lore", ""))
		var low := lore.to_lower()
		if lore.length() < 12 or lore.length() > 96 or "crystal" not in low:
			_fail("lore must be a short crystal line, got '%s'" % lore)
			return
		if "hunter" not in low and "treasure" not in low:
			_fail("lore must tie to treasure hunters, got '%s'" % lore)
			return
		var chest: Dictionary = site.get("chest", {})
		var relics: Array = chest.get("relics", [])
		if relics.is_empty() or StringName(str(relics[0])) not in pool:
			_fail("chest relic missing from the ruin pool at site %d" % i)
			return
		seen[StringName(str(relics[0]))] = true
		var resources: Dictionary = chest.get("resources", {})
		if int(resources.get("stone", 0)) < 1:
			_fail("chest must hold stone")
			return
		var kinds := 0
		for key in resources.keys():
			var n := int(resources[key])
			if n < 1 or not _ItemTypes.is_valid(str(key)):
				_fail("bad chest resource %s" % str(key))
				return
			kinds += 1
		if kinds < 2:
			_fail("chest should hold more than one resource")
			return
	if seen.size() < 2:
		_fail("treasure relics should vary across sites")
		return
	print("OK treasure chests relics=%d" % seen.size())


func _check_retired_stamp() -> void:
	var off: Dictionary = _Ruin.feature_payload({
		"center": Vector2i(1, 2),
		"name": "Ruin 1",
	}, false)
	if not bool(off.get("is_spawn_point", false)) or off.has("chest") or bool(off.get("treasure_site", false)):
		_fail("retired ruin stamp must stay a spawn site without a chest")
		return
	print("OK retired ruin stamp")


func _check_installed_chest() -> void:
	_WorldState.replace_active()
	var mgr = _Ruin.new()
	var center := Vector2i(120, 40)
	var site: Dictionary = _Ruin.treasure_site(0, center)
	mgr.install_site(site, true)
	var feat: Dictionary = _FeatureRegistry.get_feature(center.x, center.y)
	if int(feat.get("kind", -1)) != _WorldFeatureTypes.FeatureKind.RUIN:
		_fail("center is not a ruin feature")
		return
	if not bool(feat.get("treasure_site", false)) or bool(feat.get("is_spawn_point", true)):
		_fail("installed site still feeds a spawn")
		return
	var chest: Dictionary = feat.get("chest", {})
	var relics: Array = chest.get("relics", [])
	var resources: Dictionary = chest.get("resources", {})
	if relics.is_empty() or int(resources.get("stone", 0)) < 1 or str(feat.get("lore", "")) == "":
		_fail("installed chest is missing relic, stone, or lore")
		return
	if _FeatureRegistry.get_tile_override(center.x, center.y) != VoxelTypes.STONE2:
		_fail("treasure center did not stamp stone")
		return
	var edge: Dictionary = _FeatureRegistry.get_feature(center.x + 5, center.y)
	if edge.is_empty() or edge.has("chest"):
		_fail("loot chest must sit only on the site center")
		return
	if int(edge.get("kind", -1)) != _WorldFeatureTypes.FeatureKind.RUIN:
		_fail("site rim is not a ruin")
		return
	_WorldState.replace_active()
	mgr.install_site({"center": Vector2i(3, 4), "name": "Ruin 9", "radius": 5}, false)
	var old: Dictionary = _FeatureRegistry.get_feature(3, 4)
	if not bool(old.get("is_spawn_point", false)) or old.has("chest"):
		_fail("flag-off install must keep the old ruin")
		return
	print("OK installed treasure chest")
