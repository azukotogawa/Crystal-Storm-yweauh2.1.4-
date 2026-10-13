class_name ServiceRegistry
extends RefCounted
## Typed service registration for the Composition Root.
## Services are registered by StringName id; optional dependency edges enable
## validation and cycle detection without scene-tree search.

signal service_registered(id: StringName, instance: Object)
signal service_unregistered(id: StringName)

var _services: Dictionary = {}  # StringName -> Object
var _deps: Dictionary = {}  # StringName -> Array[StringName] (required peer ids)
var _init_order: Array = []  # registration / init order
var _shutdown_order: Array = []


func clear() -> void:
	_services.clear()
	_deps.clear()
	_init_order.clear()
	_shutdown_order.clear()


func register(id: StringName, instance: Object, depends_on: Array = []) -> void:
	if instance == null:
		push_error("ServiceRegistry: cannot register null for %s" % str(id))
		return
	_services[id] = instance
	var deps: Array = []
	for d in depends_on:
		deps.append(StringName(str(d)))
	_deps[id] = deps
	if id not in _init_order:
		_init_order.append(id)
	# Shutdown is reverse of first registration order.
	_shutdown_order = _init_order.duplicate()
	_shutdown_order.reverse()
	service_registered.emit(id, instance)


func unregister(id: StringName) -> void:
	_services.erase(id)
	_deps.erase(id)
	_init_order.erase(id)
	_shutdown_order = _init_order.duplicate()
	_shutdown_order.reverse()
	service_unregistered.emit(id)


func has_service(id: StringName) -> bool:
	return _services.has(id) and _services[id] != null


func resolve(id: StringName):
	if not _services.has(id):
		return null
	return _services[id]


## Resolve required service or push_error + return null.
func require(id: StringName):
	var inst = resolve(id)
	if inst == null:
		push_error("ServiceRegistry: missing required service '%s'" % str(id))
	return inst


func all_ids() -> Array:
	return _services.keys()


func init_order() -> Array:
	return _init_order.duplicate()


func shutdown_order() -> Array:
	return _shutdown_order.duplicate()


func dependency_edges() -> Dictionary:
	return _deps.duplicate(true)


## Validate that every declared dependency is registered. Returns {ok, missing: [{service, missing_dep}]}
func validate_dependencies() -> Dictionary:
	var missing: Array = []
	for id_variant in _deps.keys():
		var id: StringName = id_variant
		if not _services.has(id):
			continue
		for dep_variant in _deps[id]:
			var dep: StringName = dep_variant
			if not has_service(dep):
				missing.append({"service": str(id), "missing_dep": str(dep)})
	return {"ok": missing.is_empty(), "missing": missing}


## Detect cycles in the dependency graph. Returns {ok, cycles: Array[Array]}
func detect_cycles() -> Dictionary:
	var cycles: Array = []
	var visiting: Dictionary = {}
	var visited: Dictionary = {}
	var stack: Array = []

	for id_variant in _services.keys():
		var id: StringName = id_variant
		if visited.has(id):
			continue
		_dfs_cycle(id, visiting, visited, stack, cycles)
	return {"ok": cycles.is_empty(), "cycles": cycles}


func _dfs_cycle(
	id: StringName,
	visiting: Dictionary,
	visited: Dictionary,
	stack: Array,
	cycles: Array
) -> void:
	if visiting.has(id):
		var cycle: Array = []
		var started := false
		for s in stack:
			if s == id:
				started = true
			if started:
				cycle.append(str(s))
		cycle.append(str(id))
		cycles.append(cycle)
		return
	if visited.has(id):
		return
	visiting[id] = true
	stack.append(id)
	for dep_variant in _deps.get(id, []):
		var dep: StringName = dep_variant
		if _services.has(dep) or _deps.has(dep):
			_dfs_cycle(dep, visiting, visited, stack, cycles)
	stack.pop_back()
	visiting.erase(id)
	visited[id] = true


func dump() -> Dictionary:
	return {
		"services": _services.keys().map(func(k): return str(k)),
		"init_order": _init_order.map(func(k): return str(k)),
		"shutdown_order": _shutdown_order.map(func(k): return str(k)),
		"deps": _deps_as_strings(),
		"validation": validate_dependencies(),
		"cycles": detect_cycles(),
	}


func _deps_as_strings() -> Dictionary:
	var out := {}
	for id_variant in _deps.keys():
		var arr: Array = []
		for d in _deps[id_variant]:
			arr.append(str(d))
		out[str(id_variant)] = arr
	return out
