extends SceneTree

const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _FacePick = preload("res://player/face_pick.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

var _world
var _fails := 0
var _checks := 0


func _init() -> void:
	call_deferred("_run")


func _top(c: Vector2i) -> float:
	return _ActionTargeting._walkable_top(_world, null, float(c.x) + 0.5, float(c.y) + 0.5)


func _check(label: String, origin: Vector3, dir: Vector3, want_col: Vector2i, want_face_y: float, want_normal: Vector3i) -> void:
	_checks += 1
	var scale: float = _WorldSettings.get_active().voxel_scale
	var hit: Dictionary = _FacePick.pick(_world, origin, dir, origin / scale, 999.0)
	if not bool(hit.get("hit", false)):
		_fails += 1
		print("FAIL %s miss" % label)
		return
	var cell: Vector3i = hit.cell
	var point: Vector3 = origin + dir.normalized() * float(hit.t)
	var col_ok := Vector2i(cell.x, cell.z) == want_col and Vector3i(hit.normal) == want_normal
	var box_top := float(cell.y + 1) * scale
	var ok := col_ok
	if want_normal.y > 0:
		ok = ok and absf(point.y - want_face_y) < 0.01 and absf(box_top - want_face_y) < 0.01
	else:
		ok = ok and point.y <= _top(want_col) + 0.01 and point.y >= box_top - scale - 0.01 and point.y <= box_top + 0.01
	if not ok:
		_fails += 1
	print("%s %s cell=%s normal=%s hit_y=%.2f box_top=%.2f render_top=%.2f" % ["OK" if ok else "FAIL", label, cell, hit.normal, point.y, box_top, _top(want_col)])


func _run() -> void:
	_world = _InfiniteNoiseWorld.new()
	_world.world_seed = 7
	root.add_child(_world)
	await process_frame
	var scale: float = _WorldSettings.get_active().voxel_scale
	for c in [Vector2i(3, 2), Vector2i(5, 5), Vector2i(8, 9)]:
		var top := _top(c)
		var target := Vector3((c.x + 0.5) * scale, top, (c.y + 0.5) * scale)
		for d in [Vector3(0, -1, 0), Vector3(0.3, -1, 0.2), Vector3(1, -1, 0), Vector3(-1, -0.6, 0.4)]:
			var dir: Vector3 = d.normalized()
			_check("down%s col=%s" % [d, c], target - dir * 9.0, dir, c, top, Vector3i(0, 1, 0))
	var side_found := 0
	for x in range(0, 30):
		for z in range(0, 30):
			if side_found >= 4:
				break
			var a := Vector2i(x, z)
			var b := Vector2i(x + 1, z)
			if _top(b) < _top(a) + scale - 0.01:
				continue
			var y0 := _top(a) + scale * 0.25
			var x0 := (a.x + 0.5) * scale
			_check("up-slope a=%s b=%s" % [a, b], Vector3(x0, y0, (a.y + 0.5) * scale), Vector3(1, 0.15, 0), b, 0.0, Vector3i(-1, 0, 0))
			_check("flat-slope a=%s b=%s" % [a, b], Vector3(x0, y0 + 0.4, (a.y + 0.5) * scale), Vector3(1, -0.05, 0), b, 0.0, Vector3i(-1, 0, 0))
			side_found += 1
	if side_found == 0:
		_fails += 1
		print("FAIL no slope column found")
	if _fails == 0:
		print("All highlight block under cursor tests OK (%d checks)" % _checks)
		quit(0)
	else:
		print("Highlight block under cursor FAILED %d/%d" % [_fails, _checks])
		quit(1)
