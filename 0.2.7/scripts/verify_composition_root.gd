extends SceneTree
## Composition root: registry DI, stages, config precedence, cycles, shutdown.
## Usage: godot --headless -s scripts/verify_composition_root.gd

const _ServiceRegistry = preload("res://systems/service_registry.gd")
const _RuntimeConfigResolver = preload("res://systems/runtime_config_resolver.gd")
const _CompositionRoot = preload("res://systems/composition_root.gd")
const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")
const _GameConfig = preload("res://config/game_config.gd")


var _failed: int = 0


func _init() -> void:
	_run()
	if _failed == 0:
		print("OK composition root unit contracts")
		quit(0)
	else:
		push_error("verify_composition_root: %d failure(s)" % _failed)
		quit(1)


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_test_registry_di_and_missing()
	_test_cycle_detection()
	_test_config_precedence()
	_test_shutdown_order()
	_test_stage_names()


func _test_registry_di_and_missing() -> void:
	var reg = _ServiceRegistry.new()
	var a := Node.new()
	a.name = "ServiceA"
	var b := Node.new()
	b.name = "ServiceB"
	reg.register(&"service_a", a, [])
	reg.register(&"service_b", b, [&"service_a"])
	if reg.resolve(&"service_a") != a:
		_fail("resolve must return registered instance")
	if reg.require(&"service_b") != b:
		_fail("require must return registered instance")
	if reg.resolve(&"missing") != null:
		_fail("missing resolve should be null")
	var val: Dictionary = reg.validate_dependencies()
	if not bool(val.get("ok", false)):
		_fail("deps should be ok when service_a present")
	reg.unregister(&"service_a")
	val = reg.validate_dependencies()
	if bool(val.get("ok", true)):
		_fail("missing dependency must fail validation")
	else:
		print("OK DI registration + missing dep detection")
	a.free()
	b.free()


func _test_cycle_detection() -> void:
	var reg = _ServiceRegistry.new()
	var a := Node.new()
	var b := Node.new()
	reg.register(&"a", a, [&"b"])
	reg.register(&"b", b, [&"a"])
	var cyc: Dictionary = reg.detect_cycles()
	if bool(cyc.get("ok", true)):
		_fail("cycle a↔b must be detected")
	elif (cyc.get("cycles", []) as Array).is_empty():
		_fail("cycles array empty")
	else:
		print("OK circular dependency detection")
	a.free()
	b.free()


func _test_config_precedence() -> void:
	var defaults = _GameConfig.create_default()
	defaults.ensure_defaults()
	var project = _GameConfig.create_default()
	project.ensure_defaults()
	if project.world_gen:
		project.world_gen.caves_enabled = true
	var quality = _PerformanceQualityConfig.apply_preset(_PerformanceQualityConfig.Preset.LOW)
	quality.caves_enabled = false
	quality.render_distance = 1
	# Platform wants even lower upload budget
	var platform := {"chunk_upload_budget_us": 1000}
	# Debug overrides win for render_distance
	var debug := {"render_distance": 9}

	var resolved: Dictionary = _RuntimeConfigResolver.resolve(
		defaults, project, quality, platform, debug
	)
	var policy: Dictionary = resolved.get("policy", {})
	if int(policy.get("render_distance", -1)) != 9:
		_fail("debug override must win render_distance (got %s)" % str(policy.get("render_distance")))
	if int(policy.get("chunk_upload_budget_us", -1)) != 1000:
		_fail("platform override must apply before debug (budget)")
	# Fold into effective quality — consumers must see debug knobs
	var eff = _RuntimeConfigResolver.fold_policy_into_quality(quality, policy)
	if int(eff.render_distance) != 9:
		_fail("fold_policy_into_quality must set render_distance=9 (got %d)" % int(eff.render_distance))
	if int(eff.chunk_upload_budget_us) != 1000:
		_fail("fold_policy_into_quality must set upload budget from platform")
	# Consumer apply: real ChunkManager must receive folded knobs
	var real_cm = load("res://chunks/chunk_manager.gd").new()
	real_cm.apply_performance_config(eff)
	if int(real_cm.RENDER_DISTANCE) != 9:
		_fail("ChunkManager must consume effective quality render_distance=9 (got %d)" % int(real_cm.RENDER_DISTANCE))
	if int(real_cm.chunk_upload_budget_us) != 1000:
		_fail("ChunkManager must consume effective upload budget")
	real_cm.free()
	# Quality caves false AND authored true → effective false (and without debug)
	var resolved2: Dictionary = _RuntimeConfigResolver.resolve(
		defaults, project, quality, {}, {}
	)
	var policy2: Dictionary = resolved2.get("policy", {})
	if bool(policy2.get("caves_enabled", true)):
		_fail("quality caves_enabled=false must yield effective false when authored true")
	# Authored world_gen must not be mutated by resolve
	if project.world_gen and not bool(project.world_gen.caves_enabled):
		_fail("resolver must not mutate authored world_gen.caves_enabled")
	var prec: Array = resolved.get("precedence", [])
	if prec.is_empty() or str(prec[0]) != "author_defaults":
		_fail("precedence list missing author_defaults first")
	if str(prec[prec.size() - 1]) != "runtime_debug_overrides":
		_fail("debug must be last in precedence")
	print("OK configuration precedence + consumer apply")


func _test_shutdown_order() -> void:
	var reg = _ServiceRegistry.new()
	var nodes: Array = []
	for i in 3:
		var n := Node.new()
		n.name = "S%d" % i
		nodes.append(n)
		reg.register(StringName("s%d" % i), n, [])
	var init_o: Array = reg.init_order()
	var shut_o: Array = reg.shutdown_order()
	if shut_o.size() != init_o.size():
		_fail("shutdown order size mismatch")
	else:
		var ok := true
		for i in init_o.size():
			if str(shut_o[i]) != str(init_o[init_o.size() - 1 - i]):
				ok = false
		if not ok:
			_fail("shutdown order must reverse init order")
		else:
			print("OK shutdown reverse order")
	for n in nodes:
		n.free()


func _test_stage_names() -> void:
	# Stage enum progression is documented on CompositionRoot
	if _CompositionRoot.Stage.CONFIGURED >= _CompositionRoot.Stage.QUALITY_APPLIED:
		_fail("CONFIGURED must precede QUALITY_APPLIED")
	if _CompositionRoot.Stage.FEATURES_SEEDED >= _CompositionRoot.Stage.CHUNKS_CREATED:
		_fail("FEATURES_SEEDED must precede CHUNKS_CREATED")
	if _CompositionRoot.Stage.CHUNKS_CREATED >= _CompositionRoot.Stage.VISUALS_COMMITTED:
		_fail("CHUNKS before VISUALS")
	print("OK stage ordering constants")
