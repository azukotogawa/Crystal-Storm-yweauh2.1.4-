class_name ItemAnim
extends RefCounted

enum Kind { NONE = 0, SWING = 1, THRUST = 2, RAISE = 3, AIM = 4 }

const _ItemTypes = preload("res://helpers/item_types.gd")


static func kind_name(kind: int) -> String:
	match kind:
		Kind.SWING:
			return "swing"
		Kind.THRUST:
			return "thrust"
		Kind.RAISE:
			return "raise"
		Kind.AIM:
			return "aim"
		_:
			return "none"


static func spec_for(item_id: String) -> Dictionary:
	var def: Dictionary = _ItemTypes.get_def(item_id)
	var kind := _derive_kind(def)
	var authored := int(def.get("anim_kind", -1))
	if authored >= Kind.NONE and authored <= Kind.AIM and def.has("anim_kind"):
		kind = authored
	var duration := float(def.get("anim_duration", 0.0))
	if duration <= 0.0:
		duration = float(def.get("cooldown", 0.0))
	if duration <= 0.0:
		duration = 0.28 if kind != Kind.NONE else 0.0
	var ratio := float(def.get("impact_ratio", -1.0))
	if ratio < 0.0:
		ratio = _default_ratio(kind)
	ratio = clampf(ratio, 0.0, 0.92)
	return {
		"item_id": item_id,
		"kind": kind,
		"duration": duration,
		"impact_ratio": ratio,
		"impact_time": duration * ratio,
	}


static func playback_for(item_id: String) -> Playback:
	var pb := Playback.new()
	pb.setup(spec_for(item_id))
	return pb


static func _derive_kind(def: Dictionary) -> int:
	if def.is_empty():
		return Kind.NONE
	var cat := int(def.get("category", -1))
	if cat == _ItemTypes.Category.ARMOR or cat == _ItemTypes.Category.MISC:
		return Kind.NONE
	if bool(def.get("throwable", false)):
		return Kind.RAISE
	if cat == _ItemTypes.Category.MATERIAL or cat == _ItemTypes.Category.CONSUMABLE:
		return Kind.RAISE
	var wk := int(def.get("weapon_kind", _ItemTypes.WeaponKind.MELEE))
	if wk == _ItemTypes.WeaponKind.RANGED:
		return Kind.AIM
	if bool(def.get("thrust", false)):
		return Kind.THRUST
	if wk == _ItemTypes.WeaponKind.DIG or wk == _ItemTypes.WeaponKind.MELEE:
		return Kind.SWING
	return Kind.NONE


static func _default_ratio(kind: int) -> float:
	match kind:
		Kind.SWING:
			return 0.42
		Kind.THRUST:
			return 0.56
		Kind.RAISE:
			return 0.50
		Kind.AIM:
			return 0.70
		_:
			return 0.0


class Playback extends RefCounted:
	var item_id: String = ""
	var kind: int = 0
	var duration: float = 0.28
	var impact_ratio: float = 0.42
	var elapsed: float = 0.0
	var impact_fired: bool = false


	func setup(spec: Dictionary) -> void:
		item_id = str(spec.get("item_id", ""))
		kind = int(spec.get("kind", Kind.NONE))
		duration = maxf(float(spec.get("duration", 0.28)), 0.001)
		impact_ratio = clampf(float(spec.get("impact_ratio", 0.42)), 0.0, 0.92)
		elapsed = 0.0
		impact_fired = false


	func impact_time() -> float:
		return duration * impact_ratio


	func unit() -> float:
		return clampf(elapsed / duration, 0.0, 1.0)


	func finished() -> bool:
		return impact_fired and elapsed >= duration - 0.0001


	func advance(dt: float) -> bool:
		if duration <= 0.0:
			return false
		if not impact_fired and impact_time() <= 0.0:
			impact_fired = true
			elapsed = 0.0
			return true
		var before := elapsed
		elapsed = minf(before + maxf(dt, 0.0), duration)
		if impact_fired:
			return false
		var at := impact_time()
		if before < at and elapsed >= at - 0.00001:
			impact_fired = true
			return true
		return false


	func snap_to_impact() -> void:
		elapsed = impact_time()
		impact_fired = true
