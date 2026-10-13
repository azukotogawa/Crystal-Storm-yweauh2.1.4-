class_name SaveSchema
extends RefCounted
## Versioned save schema: validate, migrate, integrity hash.
## schema_version 1 = legacy flat terrain_edits/features/channels
## schema_version 2 = world_state authority block + revisions + integrity
##
## Terrain overlay contract (macro/micro):
## - Persist only WorldState height_delta / build_tile (and features/channels).
## - Micro bricks are runtime-derived from overlays on generate/rebuild — never saved.
## - v1→v2 migration lifts flat terrain_edits into world_state; load rebuild re-derives micro.

const FORMAT_ID := "crystalstorm_save"
const CURRENT_VERSION := 2
const MIN_SUPPORTED_VERSION := 1

const REQUIRED_TOP_KEYS_V2 := ["schema_version", "world_state"]


static func current_version() -> int:
	return CURRENT_VERSION


## Content hash for corruption detection (order-independent canonical form).
static func content_hash(payload: Dictionary) -> String:
	var copy: Dictionary = payload.duplicate(true)
	copy.erase("checksum")
	copy.erase("integrity")
	var encoded := _canonical_json(copy)
	return "%08x" % int(encoded.hash())


## Deterministic JSON: object keys sorted; arrays keep order; ints normalized.
static func _canonical_json(value: Variant) -> String:
	if value == null:
		return "null"
	if value is bool:
		return "true" if value else "false"
	if value is int:
		return str(int(value))
	if value is float:
		# Prefer int form when whole to survive JSON number parsing.
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


## Returns { "ok": bool, "reason": String, "data": Dictionary migrated to current }
static func validate_and_migrate(raw) -> Dictionary:
	if raw == null or not raw is Dictionary:
		return {"ok": false, "reason": "not_object", "data": {}}
	var data: Dictionary = (raw as Dictionary).duplicate(true)
	# Legacy files used "version" only.
	var ver: int = int(data.get("schema_version", data.get("version", 0)))
	if ver <= 0:
		return {"ok": false, "reason": "missing_version", "data": {}}
	if ver < MIN_SUPPORTED_VERSION:
		return {"ok": false, "reason": "version_too_old_%d" % ver, "data": {}}
	if ver > CURRENT_VERSION:
		return {"ok": false, "reason": "version_too_new_%d" % ver, "data": {}}

	# Integrity check when present (v2+ saves).
	if data.has("checksum") or data.has("integrity"):
		var expected: String = str(data.get("checksum", data.get("integrity", "")))
		var actual: String = content_hash(data)
		if expected != "" and expected != actual:
			return {"ok": false, "reason": "checksum_mismatch", "data": {}}

	if ver < CURRENT_VERSION:
		var migrated: Dictionary = migrate(data, ver, CURRENT_VERSION)
		if migrated.is_empty():
			return {"ok": false, "reason": "migration_failed_%d_to_%d" % [ver, CURRENT_VERSION], "data": {}}
		data = migrated

	var structural: Dictionary = validate_structure(data)
	if not bool(structural.get("ok", false)):
		return structural

	data["schema_version"] = CURRENT_VERSION
	data["version"] = CURRENT_VERSION  # alias for older readers of top-level version
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
			# Empty world is valid (fresh).
			pass
	return {"ok": true, "reason": "ok", "data": data}


static func migrate(data: Dictionary, from_ver: int, to_ver: int) -> Dictionary:
	var cur: Dictionary = data.duplicate(true)
	var v: int = from_ver
	while v < to_ver:
		match v:
			1:
				cur = _migrate_v1_to_v2(cur)
			_:
				return {}
		v += 1
		if cur.is_empty():
			return {}
	return cur


static func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	out["schema_version"] = 2
	out["format"] = FORMAT_ID
	out["version"] = 2
	# Build world_state from flat overlay fields if missing.
	if not out.has("world_state") or not out.world_state is Dictionary:
		var terrain: Dictionary = out.get("terrain_edits", {})
		var features: Dictionary = out.get("features", {})
		var channels_wrap: Dictionary = out.get("channels", {})
		out["world_state"] = {
			"revision": int(out.get("world_state_revision", 0)),
			"terrain_revision": 0,
			"feature_revision": 0,
			"feature_tile_revision": 0,
			"channel_revision": 0,
			"height_delta": terrain.get("height_delta", {}),
			"build_tile": terrain.get("build_tile", {}),
			"tile_overrides": features.get("tile_overrides", {}),
			"feature_cells": features.get("feature_cells", {}),
			"towns": features.get("towns", []),
			"entity_spawns": features.get("entity_spawns", []),
			"channels": channels_wrap.get("channels", channels_wrap),
		}
	if not out.has("world"):
		out["world"] = {
			"seed": int(out.get("world_seed", 0)),
			"metadata": {},
		}
	else:
		var w: Dictionary = out.world if out.world is Dictionary else {}
		if not w.has("seed"):
			w["seed"] = int(out.get("world_seed", 0))
		out["world"] = w
	# Keep flat aliases for consumers that still read them.
	_sync_flat_aliases_from_world_state(out)
	return out


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


## Structural readiness keys for future multiplayer / replay / mods (not full product).
static func future_extension_stubs() -> Dictionary:
	return {
		"authority": {"mode": "local_singleplayer"},
		"replay": {"seed": 0, "mutation_log": []},
		"mods": {"ids": []},
		"streaming_save": {"chunk_regions": []},
	}
