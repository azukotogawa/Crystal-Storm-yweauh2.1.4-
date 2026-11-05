extends RefCounted
## Region-file pack (default ON as of Cole t550s2516 / Nov 5). Packs the v122
## per-chunk .chk files 8x8 to a region: 16,384 chunk files become 256
## region files. Each chunk blob is stored byte-for-byte, so the v122 chunk
## format and BAKE_VERSION are unchanged and loose .chk files stay readable.
##
## Layout: "CSRG" | u32 version | u32 slots (64) | slots x (u64 offset, u32 len)
## | blobs. len 0 = chunk absent.

const MAGIC := "CSRG"
const VERSION := 1
const SIDE := 8
const SLOTS := SIDE * SIDE
const HEADER := 12
const ENTRY := 12

static var _index_cache: Dictionary = {}


static func enabled() -> bool:
	# Default ON. Opt out with CRYSTALSTORM_BAKE_REGION=0 (empty/unset = on).
	var raw := OS.get_environment("CRYSTALSTORM_BAKE_REGION").strip_edges().to_lower()
	if raw == "0" or raw == "false" or raw == "off" or raw == "no":
		return false
	return true


static func region_of(coord: Vector2i) -> Vector2i:
	return Vector2i(floori(float(coord.x) / SIDE), floori(float(coord.y) / SIDE))


static func slot_of(coord: Vector2i) -> int:
	var lx := posmod(coord.x, SIDE)
	var lz := posmod(coord.y, SIDE)
	return lz * SIDE + lx


static func region_path(regions_dir: String, r: Vector2i) -> String:
	return regions_dir.path_join("r_%d_%d.reg" % [r.x, r.y])


## Pack every <cx>_<cz>.chk in chunks_dir into regions_dir. Returns stats.
static func pack_dir(chunks_dir: String, regions_dir: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(regions_dir))
	var by_region: Dictionary = {}
	var da := DirAccess.open(chunks_dir)
	if da == null:
		return {"ok": false, "error": "no chunks dir"}
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if not da.current_is_dir() and n.ends_with(".chk"):
			var parts := n.get_basename().split("_")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				var c := Vector2i(int(parts[0]), int(parts[1]))
				var r := region_of(c)
				if not by_region.has(r):
					by_region[r] = []
				(by_region[r] as Array).append(c)
		n = da.get_next()
	da.list_dir_end()
	var chunks := 0
	var bytes := 0
	for r_v in by_region.keys():
		var r: Vector2i = r_v
		var blobs: Array = []
		blobs.resize(SLOTS)
		for c_v in by_region[r]:
			var c: Vector2i = c_v
			blobs[slot_of(c)] = FileAccess.get_file_as_bytes(chunks_dir.path_join("%d_%d.chk" % [c.x, c.y]))
		var tmp := region_path(regions_dir, r) + ".tmp"
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		if f == null:
			return {"ok": false, "error": "write " + tmp}
		f.store_buffer(MAGIC.to_utf8_buffer())
		f.store_32(VERSION)
		f.store_32(SLOTS)
		var off := HEADER + SLOTS * ENTRY
		for i in SLOTS:
			var b = blobs[i]
			var ln: int = (b as PackedByteArray).size() if b is PackedByteArray else 0
			f.store_64(off if ln > 0 else 0)
			f.store_32(ln)
			off += ln
		for i in SLOTS:
			var b = blobs[i]
			if b is PackedByteArray and (b as PackedByteArray).size() > 0:
				f.store_buffer(b)
				chunks += 1
				bytes += (b as PackedByteArray).size()
		f.close()
		var fin := region_path(regions_dir, r)
		if FileAccess.file_exists(fin):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(fin))
		DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(fin))
		_index_cache.erase(fin)
	return {"ok": true, "regions": by_region.size(), "chunks": chunks, "bytes": bytes}


static func _index(path: String) -> PackedInt64Array:
	if _index_cache.has(path):
		return _index_cache[path]
	var idx := PackedInt64Array()
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null and f.get_buffer(4).get_string_from_utf8() == MAGIC and int(f.get_32()) == VERSION:
		var slots := int(f.get_32())
		idx.resize(slots * 2)
		for i in slots:
			idx[i * 2] = int(f.get_64())
			idx[i * 2 + 1] = int(f.get_32())
		f.close()
	_index_cache[path] = idx
	return idx



## All chunk coords present across region files (len>0 slots).
static func inventory_coords(regions_dir: String) -> Array:
	var out: Array = []
	var abs_dir := ProjectSettings.globalize_path(regions_dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return out
	var da := DirAccess.open(regions_dir)
	if da == null:
		return out
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if not da.current_is_dir() and n.begins_with("r_") and n.ends_with(".reg"):
			var stem := n.substr(0, n.length() - 4) # r_X_Y
			var parts: PackedStringArray = stem.split("_")
			if parts.size() == 3 and parts[1].is_valid_int() and parts[2].is_valid_int():
				var r := Vector2i(int(parts[1]), int(parts[2]))
				var path := region_path(regions_dir, r)
				var idx := _index(path)
				for s in range(SLOTS):
					if idx.size() > s * 2 + 1 and idx[s * 2 + 1] > 0:
						var lx := s % SIDE
						var lz := int(s / SIDE)
						out.append(Vector2i(r.x * SIDE + lx, r.y * SIDE + lz))
		n = da.get_next()
	da.list_dir_end()
	return out

static func has_chunk(regions_dir: String, coord: Vector2i) -> bool:
	var idx := _index(region_path(regions_dir, region_of(coord)))
	var s := slot_of(coord)
	return idx.size() > s * 2 + 1 and idx[s * 2 + 1] > 0


## Raw v122 .chk bytes for coord, or empty when absent.
static func read_chunk_bytes(regions_dir: String, coord: Vector2i) -> PackedByteArray:
	var path := region_path(regions_dir, region_of(coord))
	var idx := _index(path)
	var s := slot_of(coord)
	if idx.size() <= s * 2 + 1 or idx[s * 2 + 1] <= 0:
		return PackedByteArray()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	f.seek(idx[s * 2])
	var out := f.get_buffer(idx[s * 2 + 1])
	f.close()
	return out


static func clear_cache() -> void:
	_index_cache.clear()

## FileAccess-shaped reader over one chunk blob, so the v122 parser runs
## unchanged on region data.
class ChunkReader:
	extends RefCounted
	var _b := StreamPeerBuffer.new()

	func _init(bytes: PackedByteArray) -> void:
		_b.data_array = bytes

	func get_buffer(n: int) -> PackedByteArray:
		var r: Array = _b.get_data(n)
		return r[1] if int(r[0]) == OK else PackedByteArray()

	func get_32() -> int:
		return _b.get_u32()

	func get_64() -> int:
		return _b.get_64()

	func get_float() -> float:
		return _b.get_float()

	func get_var(allow_objects: bool = false):
		return _b.get_var(allow_objects)

	func close() -> void:
		pass
