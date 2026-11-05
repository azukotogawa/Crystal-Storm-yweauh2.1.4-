extends SceneTree
## Column pass identity: get_column_worker (fused path) must match the reference
## path (get_column_worker_ref = separate height + tile + biome evaluation) bit for bit.
## Also prints per-chunk column timings (TIMING lines).
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const SIZE := 16

var fails := 0
var checked := 0

func _init() -> void:
	call_deferred("_run")

func _cmp(w, wx: float, wz: float, d: float, bt: int, ft: int, tag: String) -> void:
	var a: Array = w.get_column_worker(wx, wz, d, bt, ft)
	var b: Array = w.get_column_worker_ref(wx, wz, d, bt, ft)
	checked += 1
	if a[0] != b[0] or a[1] != b[1]:
		fails += 1
		if fails <= 20:
			print("FAIL column %s at %.1f,%.1f d=%.2f bt=%d ft=%d fused=%s ref=%s" % [tag, wx, wz, d, bt, ft, str(a), str(b)])

func _identity(seed: int) -> void:
	var w = _InfiniteNoiseWorld.new(seed)
	var temps := [w.MapTemperature.MILD, w.MapTemperature.COLD, w.MapTemperature.MILD_COLD, w.MapTemperature.HOT, w.MapTemperature.HOT_MILD]
	var ti := 0
	# Chunks across playable area, transition band, and deep border.
	for cx in range(-92, 93, 9):
		for cz in range(-92, 93, 9):
			w.map_temperature = temps[ti % temps.size()]
			ti += 1
			for x in range(0, SIZE, 3):
				for z in range(0, SIZE, 3):
					var wx := float(cx * SIZE + x)
					var wz := float(cz * SIZE + z)
					_cmp(w, wx, wz, 0.0, -1, -1, "s%d" % seed)
			var bx := float(cx * SIZE)
			var bz := float(cz * SIZE)
			_cmp(w, bx + 1.0, bz + 2.0, 1.5, -1, -1, "delta")
			_cmp(w, bx + 2.0, bz + 1.0, -2.0, -1, -1, "delta")
			_cmp(w, bx + 3.0, bz + 3.0, 0.0, 5, -1, "build")
			_cmp(w, bx + 4.0, bz + 5.0, 0.0, -1, 7, "feature")
	# Dense full chunks near spawn river and the playable edge.
	var sc: Vector2 = w.spawn_river_center()
	var dense := [Vector2i(floori(sc.x / SIZE), floori(sc.y / SIZE)), Vector2i(63, 0), Vector2i(64, 10), Vector2i(-65, -64), Vector2i(0, 0), Vector2i(10, -20)]
	w.map_temperature = w.MapTemperature.MILD
	for c in dense:
		for x in SIZE:
			for z in SIZE:
				_cmp(w, float(c.x * SIZE + x), float(c.y * SIZE + z), 0.0, -1, -1, "dense")

func _med(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2]) / 1000.0

func _timing(seed: int) -> void:
	var w = _InfiniteNoiseWorld.new(seed)
	var has_ref: bool = w.has_method("get_column_worker_ref")
	var th: Array = []
	var tb: Array = []
	var tr: Array = []
	var tf: Array = []
	for i in 30:
		var c := Vector2i(i - 15, 3)
		var t0 := Time.get_ticks_usec()
		var hs: Array = []
		for x in SIZE:
			for z in SIZE:
				hs.append(w.get_surface_height_uncached(float(c.x * SIZE + x), float(c.y * SIZE + z)))
		th.append(Time.get_ticks_usec() - t0)
		t0 = Time.get_ticks_usec()
		var k := 0
		for x in SIZE:
			for z in SIZE:
				w._get_biome_compute(float(c.x * SIZE + x), 0.0, float(c.y * SIZE + z), float(hs[k]))
				k += 1
		tb.append(Time.get_ticks_usec() - t0)
		if has_ref:
			t0 = Time.get_ticks_usec()
			for x in SIZE:
				for z in SIZE:
					w.get_column_worker_ref(float(c.x * SIZE + x), float(c.y * SIZE + z), 0.0, -1, -1)
			tr.append(Time.get_ticks_usec() - t0)
		t0 = Time.get_ticks_usec()
		for x in SIZE:
			for z in SIZE:
				w.get_column_worker(float(c.x * SIZE + x), float(c.y * SIZE + z), 0.0, -1, -1)
		tf.append(Time.get_ticks_usec() - t0)
	var ref_s := "%.2f" % _med(tr) if has_ref else "na"
	print("TIMING seed=%d chunks=30 med_ms height=%.2f biome=%.2f column_ref=%s column=%.2f" % [seed, _med(th), _med(tb), ref_s, _med(tf)])

func _run() -> void:
	var probe = _InfiniteNoiseWorld.new(77123)
	if not probe.has_method("get_column_worker_ref"):
		print("FAIL get_column_worker_ref missing (no fused column path to check)")
		_timing(77123)
		quit(1)
		return
	for s in [77123, 424242]:
		_identity(s)
	_timing(77123)
	_timing(424242)
	if fails == 0:
		print("PASS column fused identity checked=%d" % checked)
	else:
		print("FAIL column fused identity fails=%d checked=%d" % [fails, checked])
	quit(0 if fails == 0 else 1)
