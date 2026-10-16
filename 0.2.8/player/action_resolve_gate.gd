class_name ActionResolveGate
extends RefCounted

const DISTINCT_GAP := 0.15

static var owner_ref: WeakRef = null
static var owner_id := ""
static var session := 0.0
static var last_id := ""
static var last_t := -1.0
static var resolves: Array[Dictionary] = []


static func reset() -> void:
	owner_ref = null
	owner_id = ""
	session = 0.0
	last_id = ""
	last_t = -1.0
	resolves = []


static func advance(delta: float) -> void:
	if delta > 0.0:
		session += delta


static func blocked(who: RefCounted) -> bool:
	var owner := _owner()
	if owner == null:
		return false
	if not owner.has_method("pacing_blocks") or not bool(owner.pacing_blocks()):
		return false
	return owner != who


static func claim(who: RefCounted, id: String) -> bool:
	if blocked(who):
		return false
	owner_ref = weakref(who)
	owner_id = id
	return true


static func _owner() -> RefCounted:
	if owner_ref == null:
		return null
	var who = owner_ref.get_ref()
	if who == null or not is_instance_valid(who):
		owner_ref = null
		owner_id = ""
		return null
	return who as RefCounted


static func wind_for(id: String, telegraph: float) -> float:
	var need := maxf(telegraph, 0.0)
	if last_id != "" and last_id != id and last_t >= 0.0:
		need = maxf(need, DISTINCT_GAP - (session - last_t))
	return need


static func mark(id: String) -> void:
	resolves.append({"id": id, "t": session})
	last_id = id
	last_t = session


static func distinct_fault() -> String:
	for i in resolves.size():
		for j in range(i + 1, resolves.size()):
			var left: Dictionary = resolves[i]
			var right: Dictionary = resolves[j]
			if str(left.get("id", "")) == str(right.get("id", "")):
				continue
			var gap := absf(float(right.get("t", 0.0)) - float(left.get("t", 0.0)))
			if gap + 0.0001 < DISTINCT_GAP:
				return "%s %.3f / %s %.3f" % [str(left.get("id", "")), float(left.get("t", 0.0)), str(right.get("id", "")), float(right.get("t", 0.0))]
	return ""
