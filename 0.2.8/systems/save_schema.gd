class_name SaveSchema
extends RefCounted
## schema_version 3 = world_state authority block + revisions + integrity + integer water levels; older saves are refused
## Terrain overlay contract (macro/micro):
## - Persist only WorldState height_delta / build_tile (and features/channels).
## - Micro bricks are runtime-derived from overlays on generate/rebuild — never saved.

const _MicroColumnBrick = preload("res://helpers/micro_column_brick.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
## Saves written before world.playable_half existed all came from this world size.
const LEGACY_PLAYABLE_HALF: int = 1024
const WORLD_SIZE_MISMATCH_MESSAGE := "world from a different world size, create a new world"

const FORMAT_ID := "crystalstorm_save"
const CURRENT_VERSION := 3
const MIN_SUPPORTED_VERSION := 3
const OLDER_VERSION_MESSAGE := "world from an older version, create a new world"

const REQUIRED_TOP_KEYS_V2 := ["schema_version", "world_state"]
const _MICRO_PAYLOAD_KEYS: Array[String] = ["micro_bricks", "micro_grid", "micro_brick", "bricks"]
const _MICRO_DROP_KEYS: Array[String] = ["FLAG_MICRO"]


static func current_version() -> int:
	return CURRENT_VERSION


## Stored under "world" in every save.
static func world_size_header() -> Dictionary:
	return {"playable_half": _WorldBorder.PLAYABLE_HALF_X}


static func saved_playable_half(data: Dictionary) -> int:
	var w: Variant = data.get("world", {})
	if w is Dictionary and (w as Dictionary).has("playable_half"):
		return int((w as Dictionary).playable_half)
	return LEGACY_PLAYABLE_HALF


static func check_world_size(data: Dictionary, current_half: int = -1) -> Dictionary:
	var want: int = current_half if current_half > 0 else _WorldBorder.PLAYABLE_HALF_X
	var got: int = saved_playable_half(data)
	if got != want:
		return {
			"ok": false,
			"reason": "world_size_mismatch",
			"message": WORLD_SIZE_MISMATCH_MESSAGE,
			"saved_half": got,
			"current_half": want,
			"data": {},
		}
	return {"ok": true, "reason": "ok"}


static func content_hash(payload: Dictionary) -> String:
	var copy: Dictionary = payload.duplicate(true)
	copy.erase("checksum")
	copy.erase("integrity")
	var encoded := _canonical_json(copy)
	return "%08x" % int(encoded.hash())


static func _canonical_json(value: Variant) -> String:
	if value == null:
		return "null"
	if value is bool:
		return "true" if value else "false"
	if value is int:
		return str(int(value))
	if value is float:
		var f: float = float(value)
		if is_equal_approx(f, roundf(f)) and absf(f) < 1e15:
			return str(int(roundf(f)))
		return JSON.stringify(f)
	if value is String:
		return JSON.stringify(value)
	if value is Array:
		var parts: PackedStringArray = PackedStringArray()
		for item in value:
			parts.append(_canonical_json(item))
		return "[" + ",".join(parts) + "]"
	if value is Dictionary:
		var d: Dictionary = value
		var keys: Array = d.keys()
		keys.sort_custom(func(a, b) -> bool: return str(a) < str(b))
		var parts2: PackedStringArray = PackedStringArray()
		for k in keys:
			parts2.append(JSON.stringify(str(k)) + ":" + _canonical_json(d[k]))
		return "{" + ",".join(parts2) + "}"
	return JSON.stringify(value)


static func attach_integrity(payload: Dictionary) -> Dictionary:
	var out: Dictionary = payload.duplicate(true)
	out["format"] = FORMAT_ID
	out["schema_version"] = int(out.get("schema_version", CURRENT_VERSION))
	out["version"] = int(out.get("schema_version", CURRENT_VERSION))
	out["checksum"] = content_hash(out)
	return out


static func validate_and_migrate(raw) -> Dictionary:
	if raw == null or not raw is Dictionary:
		return {"ok": false, "reason": "not_object", "data": {}}
	var data: Dictionary = (raw as Dictionary).duplicate(true)
	var ver: int = int(data.get("schema_version", data.get("version", 0)))
	if ver <= 0:
		return {"ok": false, "reason": "missing_version", "data": {}}
	if ver < MIN_SUPPORTED_VERSION:
		return {"ok": false, "reason": "version_too_old_%d" % ver, "message": OLDER_VERSION_MESSAGE, "data": {}}
	if ver > CURRENT_VERSION:
		return {"ok": false, "reason": "version_too_new_%d" % ver, "data": {}}

	if data.has("checksum") or data.has("integrity"):
		var expected: String = str(data.get("checksum", data.get("integrity", "")))
		var actual: String = content_hash(data)
		if expected != "" and expected != actual:
			return {"ok": false, "reason": "checksum_mismatch", "data": {}}

	var size_check: Dictionary = check_world_size(data)
	if not bool(size_check.get("ok", false)):
		return size_check

	var structural: Dictionary = validate_structure(data)
	if not bool(structural.get("ok", false)):
		return structural

	if not _ChunkData.USE_MICRO_BRICKS:
		data = _collapse_micro_bricks_to_whole_blocks(data)

	data["schema_version"] = CURRENT_VERSION
	data["version"] = CURRENT_VERSION
	return {"ok": true, "reason": "ok", "data": data}


static func validate_structure(data: Dictionary) -> Dictionary:
	if not data.has("world_state") and not data.has("terrain_edits"):
		return {"ok": false, "reason": "missing_world_overlays", "data": {}}
	if data.has("world_state"):
		var ws: Variant = data.get("world_state", {})
		if not ws is Dictionary:
			return {"ok": false, "reason": "world_state_not_object", "data": {}}
		var wsd: Dictionary = ws
		if not wsd.has("height_delta") and not wsd.has("build_tile") and not data.has("terrain_edits"):
			pass
	return {"ok": true, "reason": "ok", "data": data}


static func _sync_flat_aliases_from_world_state(out: Dictionary) -> void:
	var ws: Dictionary = out.get("world_state", {})
	if ws.is_empty():
		return
	out["terrain_edits"] = {
		"height_delta": ws.get("height_delta", {}),
		"build_tile": ws.get("build_tile", {}),
	}
	out["features"] = {
		"tile_overrides": ws.get("tile_overrides", {}),
		"feature_cells": ws.get("feature_cells", {}),
		"towns": ws.get("towns", []),
		"entity_spawns": ws.get("entity_spawns", []),
	}
	out["channels"] = {
		"channels": ws.get("channels", {}),
	}
	out["world_state_revision"] = int(ws.get("revision", 0))
	if out.has("world") and out.world is Dictionary:
		out["world_seed"] = int(out.world.get("seed", out.get("world_seed", 0)))


static func _collapse_micro_bricks_to_whole_blocks(data: Dictionary) -> Dictionary:
	if not _payload_needs_micro_collapse(data):
		return data
	var out: Dictionary = data.duplicate(true)
	var ws: Dictionary = out.get("world_state", {}) if out.get("world_state") is Dictionary else {}
	var terrain: Dictionary = out.get("terrain_edits", {}) if out.get("terrain_edits") is Dictionary else {}
	var bricks: Dictionary = {}
	_take_micro_payload(bricks, out)
	_take_micro_payload(bricks, ws)
	_take_micro_payload(bricks, terrain)
	if ws.is_empty():
		ws = {
			"height_delta": terrain.get("height_delta", {}).duplicate(true) if terrain.get("height_delta") is Dictionary else {},
			"build_tile": terrain.get("build_tile", {}).duplicate(true) if terrain.get("build_tile") is Dictionary else {},
		}
	var hd: Dictionary = ws.get("height_delta", {}) if ws.get("height_delta") is Dictionary else {}
	var bt: Dictionary = ws.get("build_tile", {}) if ws.get("build_tile") is Dictionary else {}
	for cell_key in bricks.keys():
		_apply_collapsed_brick(hd, bt, str(cell_key), bricks[cell_key])
	_snap_height_layers(hd)
	ws["height_delta"] = hd
	ws["build_tile"] = bt
	out["world_state"] = ws
	_sync_flat_aliases_from_world_state(out)
	_drop_micro_keys(out)
	if out.get("world_state") is Dictionary:
		_drop_micro_keys(out["world_state"])
	if out.get("terrain_edits") is Dictionary:
		_drop_micro_keys(out["terrain_edits"])
	return out


static func _payload_needs_micro_collapse(data: Dictionary) -> bool:
	if _host_has_micro(data):
		return true
	if data.get("world_state") is Dictionary and _host_has_micro(data["world_state"]):
		return true
	if data.get("terrain_edits") is Dictionary and _host_has_micro(data["terrain_edits"]):
		return true
	return _host_deltas_need_snap(data.get("world_state", {})) or _host_deltas_need_snap(data.get("terrain_edits", {})) or _host_deltas_need_snap(data)


static func _host_has_micro(host: Dictionary) -> bool:
	if host.is_empty():
		return false
	for key in _MICRO_PAYLOAD_KEYS:
		if host.has(key):
			return true
	for key in _MICRO_DROP_KEYS:
		if host.has(key):
			return true
	return false


static func _host_deltas_need_snap(host: Variant) -> bool:
	if not host is Dictionary:
		return false
	var table: Dictionary = (host as Dictionary).get("height_delta", {})
	if not table is Dictionary:
		return false
	for key in table.keys():
		if not _is_whole_layer(table[key]):
			return true
	return false


static func _take_micro_payload(into: Dictionary, host: Dictionary) -> void:
	if host.is_empty():
		return
	for key in _MICRO_PAYLOAD_KEYS:
		if not host.has(key):
			continue
		var payload: Variant = host[key]
		host.erase(key)
		if not payload is Dictionary:
			continue
		var table: Dictionary = payload
		for cell_key in table.keys():
			var stored := _cell_key(cell_key)
			if into.has(stored):
				continue
			into[stored] = table[cell_key]
	_drop_micro_keys(host)


static func _drop_micro_keys(host: Dictionary) -> void:
	for key in _MICRO_PAYLOAD_KEYS:
		host.erase(key)
	for key in _MICRO_DROP_KEYS:
		host.erase(key)


static func _cell_key(cell: Variant) -> String:
	if cell is Vector2i:
		return "%d,%d" % [cell.x, cell.y]
	return str(cell)


static func _is_whole_layer(raw: Variant) -> bool:
	if raw is bool:
		return false
	if raw is int:
		return true
	if raw is float:
		return is_equal_approx(float(raw), roundf(float(raw)))
	return false


static func _whole_layer_count(raw: Variant) -> int:
	if raw is bool or not (raw is int or raw is float):
		return 0
	var value := float(raw)
	if is_zero_approx(value):
		return 0
	var layers := int(ceil(absf(value) - 0.0000001))
	return layers if value > 0.0 else -layers


static func _snap_height_layers(hd: Dictionary) -> void:
	for key in hd.keys():
		hd[key] = _whole_layer_count(hd[key])


static func _apply_collapsed_brick(hd: Dictionary, bt: Dictionary, key: String, brick: Variant) -> void:
	var dug := 0.0
	var reason := 0
	var tile := -1
	if brick is Dictionary:
		var record: Dictionary = brick
		dug = absf(float(record.get("dug_layers", record.get("layers", 0))))
		if record.has("height_delta"):
			dug = maxf(dug, absf(float(record.get("height_delta", 0))))
		reason = int(record.get("reason", 0))
		tile = int(record.get("surface_tile", record.get("build_tile", -1)))
	elif brick is int or brick is float:
		dug = absf(float(brick))
	var whole := 0
	if dug > 0.0001:
		whole = -int(ceil(dug - 0.0000001))
	if hd.has(key):
		var current := _whole_layer_count(hd[key])
		if whole < 0 and (current == 0 or current < 0):
			hd[key] = mini(current, whole) if current < 0 else whole
		else:
			hd[key] = current
	elif whole < 0:
		hd[key] = whole
	if reason == _MicroColumnBrick.REASON_BUILD and tile >= 0:
		if not bt.has(key) or int(bt.get(key, -1)) < 0:
			bt[key] = tile


static func future_extension_stubs() -> Dictionary:
	return {
		"authority": {"mode": "local_singleplayer"},
		"replay": {"seed": 0, "mutation_log": []},
		"mods": {"ids": []},
		"streaming_save": {"chunk_regions": []},
	}
