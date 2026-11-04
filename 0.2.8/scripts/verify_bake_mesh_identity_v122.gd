extends SceneTree
## Mesh plans for a small bake must match hashes saved from the v122 format,
## where plans were stored in each chunk package. From v123 the plan is built
## at load from the stored columns. Set CS_WRITE_V122_HASHES=1 on a v122 tree
## to write the fixture.

const _WorldState = preload("res://world/world_state.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const SEED := 919191
const RADIUS := 1
const FIXTURE := "res://scripts/fixtures/bake_v122_plan_hashes.txt"

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "1")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", str(RADIUS))
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL: %s" % msg)


static func plan_hash(plan: Array) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for q_variant in plan:
		var q: Dictionary = q_variant
		var keys: Array = q.keys()
		keys.sort()
		var parts := PackedStringArray()
		for k in keys:
			parts.append("%s=%s" % [str(k), var_to_str(q[k])])
		ctx.update(("|".join(parts) + "\n").to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)


func _run() -> void:
	_WorldState.replace_active()
	_WorldBakeService.clear_active()
	var world = _InfiniteNoiseWorld.new(SEED)
	var host = _ChunkManager.new()
	var bake: _WorldBakeService = _WorldBakeService.ensure_active()
	bake.delete_bake(SEED, RADIUS)
	var built: Dictionary = bake.bake_world(world, RADIUS, host)
	if not bool(built.get("ok", false)):
		_fail("bake_world failed: %s" % str(built.get("error", "")))
		_finish(null)
		return
	bake.save_bake()
	_WorldBakeService.clear_active()
	var loaded: _WorldBakeService = _WorldBakeService.ensure_active()
	if not loaded.load_bake(SEED, RADIUS):
		_fail("load_bake failed: %s" % loaded.last_error)
		_finish(loaded)
		return
	loaded.ensure_mesh_plans(host, world)
	var lines := PackedStringArray()
	for cz in range(-RADIUS, RADIUS + 1):
		for cx in range(-RADIUS, RADIUS + 1):
			var c := Vector2i(cx, cz)
			var t0 := Time.get_ticks_usec()
			var plan: Array = loaded.get_mesh_plan(c)
			var us := Time.get_ticks_usec() - t0
			print("PLAN %d,%d qn=%d us=%d" % [cx, cz, plan.size(), us])
			lines.append("%d,%d %d %s" % [cx, cz, plan.size(), plan_hash(plan)])
	if OS.get_environment("CS_WRITE_V122_HASHES") == "1":
		var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
		f.store_string("# bake v%d plan hashes seed=%d radius=%d: cx,cz quads sha256[0:16]\n" % [_WorldBakeService.BAKE_VERSION, SEED, RADIUS])
		f.store_string("\n".join(lines) + "\n")
		f.close()
		print("WROTE %s (%d chunks)" % [FIXTURE, lines.size()])
		_finish(loaded)
		return
	if not FileAccess.file_exists(FIXTURE):
		_fail("missing fixture %s" % FIXTURE)
		_finish(loaded)
		return
	var want := PackedStringArray()
	for ln in FileAccess.get_file_as_string(FIXTURE).split("\n"):
		if ln.strip_edges().is_empty() or ln.begins_with("#"):
			continue
		want.append(ln.strip_edges())
	if want.size() != lines.size():
		_fail("chunk count got=%d want=%d" % [lines.size(), want.size()])
	for i in mini(want.size(), lines.size()):
		if want[i] != lines[i]:
			_fail("plan differs: got '%s' want '%s'" % [lines[i], want[i]])
		elif lines[i].split(" ")[1] == "0":
			_fail("empty plan %s" % lines[i])
		else:
			print("OK %s" % lines[i])
	_finish(loaded)


func _finish(bake) -> void:
	if bake != null:
		bake.delete_bake(SEED, RADIUS)
	if _failed > 0:
		_ProbeExit.finish_tree(self, 1, "BAKE_MESH_IDENTITY FAIL %d" % _failed)
	else:
		_ProbeExit.finish_tree(self, 0, "BAKE_MESH_IDENTITY PASS")
