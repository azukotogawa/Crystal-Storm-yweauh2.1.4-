class_name Inventory
extends RefCounted

const _ItemTypes = preload("res://helpers/item_types.gd")

signal changed
signal hotbar_changed(index: int)

const HOTBAR_SIZE := 8
const BAG_SIZE := 24
const TOTAL_SLOTS := HOTBAR_SIZE + BAG_SIZE

var _slots: Array = []


func _init() -> void:
	_slots.resize(TOTAL_SLOTS)
	for i in TOTAL_SLOTS:
		_slots[i] = null


func get_slot(index: int) -> Variant:
	if index < 0 or index >= TOTAL_SLOTS:
		return null
	return _slots[index]


func set_slot(index: int, item_id: String, count: int = 1) -> void:
	if index < 0 or index >= TOTAL_SLOTS:
		return
	if item_id.is_empty() or count <= 0:
		_slots[index] = null
	else:
		_slots[index] = {"id": item_id, "count": count}
	changed.emit()
	if index < HOTBAR_SIZE:
		hotbar_changed.emit(index)


func clear_slot(index: int) -> void:
	set_slot(index, "", 0)


func add_item(item_id: String, count: int = 1) -> int:
	if not _ItemTypes.is_valid(item_id) or count <= 0:
		return count

	var remaining := count
	if _ItemTypes.is_stackable(item_id):
		for i in TOTAL_SLOTS:
			var slot = _slots[i]
			if slot != null and slot.id == item_id:
				var max_s := _ItemTypes.max_stack_for(item_id)
				var space := max_s - int(slot.count)
				if space > 0:
					var add := mini(remaining, space)
					slot.count += add
					remaining -= add
					if remaining <= 0:
						changed.emit()
						return 0

	for i in TOTAL_SLOTS:
		if _slots[i] != null:
			continue
		var place := mini(remaining, _ItemTypes.max_stack_for(item_id))
		_slots[i] = {"id": item_id, "count": place}
		remaining -= place
		if remaining <= 0:
			changed.emit()
			return 0

	changed.emit()
	return remaining


func remove_from_slot(index: int, count: int = 1) -> bool:
	var slot = get_slot(index)
	if slot == null:
		return false
	slot.count -= count
	if slot.count <= 0:
		_slots[index] = null
	changed.emit()
	if index < HOTBAR_SIZE:
		hotbar_changed.emit(index)
	return true


func get_hotbar_item(index: int) -> Variant:
	if index < 0 or index >= HOTBAR_SIZE:
		return null
	return get_slot(index)


func set_hotbar_index(from_bag_index: int, hotbar_index: int) -> void:
	if from_bag_index < 0 or from_bag_index >= TOTAL_SLOTS:
		return
	if hotbar_index < 0 or hotbar_index >= HOTBAR_SIZE:
		return
	var tmp = _slots[hotbar_index]
	_slots[hotbar_index] = _slots[from_bag_index]
	_slots[from_bag_index] = tmp
	changed.emit()
	hotbar_changed.emit(hotbar_index)


func swap_slots(a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= TOTAL_SLOTS or b >= TOTAL_SLOTS:
		return
	var tmp = _slots[a]
	_slots[a] = _slots[b]
	_slots[b] = tmp
	changed.emit()
	if a < HOTBAR_SIZE:
		hotbar_changed.emit(a)
	if b < HOTBAR_SIZE:
		hotbar_changed.emit(b)


func count_item(item_id: String) -> int:
	var total := 0
	for slot in _slots:
		if slot != null and slot.id == item_id:
			total += int(slot.count)
	return total


func consume_item(item_id: String, count: int = 1) -> bool:
	if count_item(item_id) < count:
		return false
	var remaining := count
	for i in TOTAL_SLOTS:
		if remaining <= 0:
			break
		var slot = _slots[i]
		if slot == null or slot.id != item_id:
			continue
		var take := mini(remaining, int(slot.count))
		slot.count -= take
		remaining -= take
		if slot.count <= 0:
			_slots[i] = null
	changed.emit()
	return remaining <= 0


func to_dict() -> Dictionary:
	var out: Array = []
	for slot in _slots:
		if slot == null:
			out.append(null)
		else:
			out.append({"id": slot.id, "count": slot.count})
	return {"slots": out}


func load_from_dict(data: Dictionary) -> void:
	var slots: Array = data.get("slots", [])
	for i in mini(slots.size(), TOTAL_SLOTS):
		var entry = slots[i]
		if entry == null:
			_slots[i] = null
		else:
			_slots[i] = {"id": str(entry.get("id", "")), "count": int(entry.get("count", 1))}
	changed.emit()