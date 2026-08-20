class_name WorldManager
extends RefCounted
## Player-facing world catalog. Does not open or delete .chk files.
## Bake packages are inspected/removed only through WorldBakeService.

const _WorldBakeService = preload("res://world/world_bake_service.gd")

const CATALOG_VERSION := 1
const DEFAULT_CATALOG_PATH := "user://worlds/catalog.json"

static var catalog_path: String = DEFAULT_CATALOG_PATH
static var pending_launch: Dictionary = {}
static var launched_from_catalog: bool = false
static var return_to_select: bool = false


static func reset_paths() -> void:
	catalog_path = DEFAULT_CATALOG_PATH


static func _catalog_abs() -> String:
	return ProjectSettings.globalize_path(catalog_path)


static func _ensure_dir() -> void:
	var dir := catalog_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))


static func _read_catalog() -> Dictionary:
	if not FileAccess.file_exists(catalog_path):
		return {"version": CATALOG_VERSION, "worlds": []}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	if parsed == null or not parsed is Dictionary:
		return {"version": CATALOG_VERSION, "worlds": []}
	var data: Dictionary = parsed
	if not data.has("worlds") or not data.worlds is Array:
		data["worlds"] = []
	return data


static func _write_catalog(data: Dictionary) -> bool:
	_ensure_dir()
	data["version"] = CATALOG_VERSION
	var f := FileAccess.open(catalog_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


static func _row_from(raw: Dictionary) -> Dictionary:
	var seed: int = int(raw.get("seed", 12349))
	var bake: Dictionary = _WorldBakeService.inspect_disk_status(seed)
	var packages: int = int(bake.get("packages", 0))
	var expected: int = int(bake.get("expected", 16384))
	var valid: bool = bool(bake.get("valid", false))
	var progress := "Not generated"
	if valid:
		progress = "Ready"
	elif packages > 0:
		progress = "Generating %d / %d" % [packages, expected]
	return {
		"id": str(raw.get("id", "")),
		"name": str(raw.get("name", "World")),
		"seed": seed,
		"created_unix": int(raw.get("created_unix", 0)),
		"last_played_unix": int(raw.get("last_played_unix", 0)),
		"bake_valid": valid,
		"bake_packages": packages,
		"bake_expected": expected,
		"bake_incomplete": bool(bake.get("incomplete", true)),
		"progress": progress,
	}


static func list_worlds() -> Array:
	var data: Dictionary = _read_catalog()
	var out: Array = []
	for raw_v in data.get("worlds", []):
		if raw_v is Dictionary:
			out.append(_row_from(raw_v))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("last_played_unix", 0)) > int(b.get("last_played_unix", 0))
	)
	return out


static func get_world(world_id: String) -> Dictionary:
	var data: Dictionary = _read_catalog()
	for raw_v in data.get("worlds", []):
		if raw_v is Dictionary and str(raw_v.get("id", "")) == world_id:
			return _row_from(raw_v)
	return {}


static func create_world(world_name: String, seed: int) -> Dictionary:
	var name := world_name.strip_edges()
	if name.is_empty():
		return {"ok": false, "error": "name_required"}
	var data: Dictionary = _read_catalog()
	var worlds: Array = data.get("worlds", [])
	var id := "w_%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	var now := int(Time.get_unix_time_from_system())
	var rec := {
		"id": id,
		"name": name,
		"seed": int(seed),
		"created_unix": now,
		"last_played_unix": 0,
	}
	worlds.append(rec)
	data["worlds"] = worlds
	if not _write_catalog(data):
		return {"ok": false, "error": "write_failed"}
	var row: Dictionary = _row_from(rec)
	row["ok"] = true
	return row


static func rename_world(world_id: String, new_name: String) -> Dictionary:
	var name := new_name.strip_edges()
	if name.is_empty():
		return {"ok": false, "error": "name_required"}
	var data: Dictionary = _read_catalog()
	var found := false
	for i in (data.get("worlds", []) as Array).size():
		var raw: Dictionary = data.worlds[i]
		if str(raw.get("id", "")) == world_id:
			raw["name"] = name
			data.worlds[i] = raw
			found = true
			break
	if not found:
		return {"ok": false, "error": "not_found"}
	if not _write_catalog(data):
		return {"ok": false, "error": "write_failed"}
	var row: Dictionary = get_world(world_id)
	row["ok"] = true
	return row


static func delete_world(world_id: String, confirmed: bool = false) -> Dictionary:
	if not confirmed:
		return {"ok": false, "error": "confirmation_required"}
	var data: Dictionary = _read_catalog()
	var worlds: Array = data.get("worlds", [])
	var kept: Array = []
	var removed: Dictionary = {}
	for raw_v in worlds:
		if raw_v is Dictionary and str(raw_v.get("id", "")) == world_id:
			removed = raw_v
		else:
			kept.append(raw_v)
	if removed.is_empty():
		return {"ok": false, "error": "not_found"}
	data["worlds"] = kept
	if not _write_catalog(data):
		return {"ok": false, "error": "write_failed"}
	var bake = _WorldBakeService.ensure_active()
	if bake and bake.has_method("delete_bake"):
		bake.delete_bake(int(removed.get("seed", 0)), -1)
	return {"ok": true, "id": world_id}


static func load_world(world_id: String) -> Dictionary:
	var row: Dictionary = get_world(world_id)
	if row.is_empty():
		return {"ok": false, "error": "not_found"}
	var data: Dictionary = _read_catalog()
	var now := int(Time.get_unix_time_from_system())
	for i in (data.get("worlds", []) as Array).size():
		var raw: Dictionary = data.worlds[i]
		if str(raw.get("id", "")) == world_id:
			raw["last_played_unix"] = now
			data.worlds[i] = raw
			break
	_write_catalog(data)
	pending_launch = {
		"id": world_id,
		"seed": int(row.get("seed", 12349)),
		"name": str(row.get("name", "World")),
	}
	launched_from_catalog = true
	row["ok"] = true
	row["last_played_unix"] = now
	return row


static func take_pending_launch() -> Dictionary:
	var out: Dictionary = pending_launch.duplicate(true)
	pending_launch = {}
	return out


static func request_return_to_select() -> void:
	return_to_select = true
	launched_from_catalog = false


static func consume_return_to_select() -> bool:
	var v := return_to_select
	return_to_select = false
	return v
