extends SceneTree

const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _Builder = preload("res://helpers/chunk_surface_mesh_builder.gd")
const _TerrainSurfaceCache = preload("res://helpers/terrain_surface_cache.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var data := ChunkData.new(Vector2i(0, 0), null)
	var top_quad: Dictionary = {
		"x": 0, "y": 4.0, "z": 0,
		"dim_x": 2.0, "dim_y": 1.0, "dim_z": 3.0,
		"uv_w": 2.0, "uv_h": 3.0,
		"type": 10, "face_code": 0,
	}
	var side_quad: Dictionary = {
		"x": 0, "y": 3.0, "z": 0,
		"dim_x": 2.0, "dim_y": 1.0, "dim_z": 1.0,
		"uv_w": 2.0, "uv_h": 1.0,
		"type": 10, "face_code": 3,
	}
	var quads: Array = [top_quad, side_quad]

	var built := _Builder.build_surface_arrays(data, quads)
	var mesh := _Builder.build_array_mesh(built)
	if mesh.get_surface_count() != 1 or int(built.triangle_count) != 4:
		_ProbeExit.finish_tree(self, 1, "surface mesh builder unit FAILED basic mesh")
		return

	var full_cache := _TerrainSurfaceCache.build_from_quads(data, quads)
	if int(full_cache.face_keys[0]) != _TerrainSurfaceCache.quad_key(top_quad):
		_ProbeExit.finish_tree(self, 1, "surface mesh builder unit FAILED face key from quads")
		return
	if int(full_cache.face_keys[0]) == 0:
		_ProbeExit.finish_tree(self, 1, "surface mesh builder unit FAILED sequential face keys")
		return

	# Replace: y changes → old key dropped, new key in patch only (no orphan growth).
	var replaced_top: Dictionary = top_quad.duplicate()
	replaced_top["y"] = 3.5
	var patched_replace: Dictionary = _TerrainSurfaceCache.patch_region(
		full_cache, data, [replaced_top], [side_quad]
	)
	var full_after_replace: Dictionary = _TerrainSurfaceCache.build_from_quads(
		data, [side_quad, replaced_top]
	)
	if int(patched_replace.triangle_count) != int(full_after_replace.triangle_count):
		_ProbeExit.finish_tree(self, 1, "surface mesh builder unit FAILED replace triangle parity")
		return
	if patched_replace.vertices.size() != full_after_replace.vertices.size():
		_ProbeExit.finish_tree(self, 1, "surface mesh builder unit FAILED replace vertex parity")
		return

	# Remove: empty patch rect quads → face count drops.
	var patched_remove: Dictionary = _TerrainSurfaceCache.patch_region(
		full_cache, data, [], [side_quad]
	)
	var full_after_remove: Dictionary = _TerrainSurfaceCache.build_from_quads(data, [side_quad])
	if int(patched_remove.triangle_count) != int(full_after_remove.triangle_count):
		_ProbeExit.finish_tree(self, 1, "surface mesh builder unit FAILED remove triangle parity")
		return
	if int(patched_remove.triangle_count) != 2:
		_ProbeExit.finish_tree(self, 1, "surface mesh builder unit FAILED remove expected 1 face")
		return

	# Append within patch: new key added, matches full rebuild.
	var new_top: Dictionary = {
		"x": 2, "y": 4.0, "z": 0,
		"dim_x": 1.0, "dim_y": 1.0, "dim_z": 1.0,
		"uv_w": 1.0, "uv_h": 1.0,
		"type": 10, "face_code": 0,
	}
	var patched_append: Dictionary = _TerrainSurfaceCache.patch_region(
		full_cache, data, [new_top], quads
	)
	var append_quads: Array = quads.duplicate()
	append_quads.append(new_top)
	var full_with_append: Dictionary = _TerrainSurfaceCache.build_from_quads(data, append_quads)
	if int(patched_append.triangle_count) != int(full_with_append.triangle_count):
		_ProbeExit.finish_tree(self, 1, "surface mesh builder unit FAILED append triangle parity")
		return

	print(
		"OK surface cache unit replace=%d remove=%d append=%d"
		% [
			int(patched_replace.triangle_count),
			int(patched_remove.triangle_count),
			int(patched_append.triangle_count),
		]
	)
	_ProbeExit.finish_tree(self, 0, "surface mesh builder unit OK")