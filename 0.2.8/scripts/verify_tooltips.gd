extends SceneTree
## Headless checks that weapon, armor, and relic tooltips read live defs.


const _TooltipText = preload("res://ui/tooltip_text.gd")
const _TooltipPanel = preload("res://ui/tooltip_panel.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _RelicRegistry = preload("res://relics/relic_registry.gd")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _run() -> void:
	await process_frame
	_ItemTypes.ensure_builtins()
	_RelicRegistry.ensure_builtins()
	_check_item("wooden_sword")
	_check_item("leather_armor")
	_check_relic("crystal_ward")
	await _check_panel()
	_TooltipPanel.hide_tip()
	if _failed:
		quit(1)
	else:
		print("All tooltip checks OK")
		quit(0)


func _check_item(item_id: String) -> void:
	var def = _ItemTypes.get_item_def(item_id)
	if def == null:
		_fail("missing item def %s" % item_id)
		return
	var text := _TooltipText.for_item(item_id)
	_expect_lines(text, item_id, str(def.display_name), str(def.description), float(def.damage), float(def.attack_range), float(def.cooldown), float(def.crystal_damage), float(def.damage_reduction))
	if not text.contains("Effects:"):
		_fail("%s tooltip missing Effects" % item_id)


func _check_relic(relic_id: String) -> void:
	var def = _RelicRegistry.get_def(StringName(relic_id))
	if def == null:
		_fail("missing relic def %s" % relic_id)
		return
	var text := _TooltipText.for_relic(relic_id)
	_expect_lines(text, relic_id, str(def.display_name), str(def.description), 0.0, 0.0, 0.0, float(def.crystal_damage_aura), 0.0)
	if not text.contains("Effects:"):
		_fail("%s tooltip missing Effects" % relic_id)
	if not text.contains("crystal flow"):
		_fail("%s tooltip missing relic flow effect" % relic_id)
	if str(def.description) == "" or not text.contains(str(def.description)):
		_fail("%s tooltip missing relic description" % relic_id)


func _expect_lines(text: String, item_id: String, display_name: String, description: String, damage: float, attack_range: float, cooldown: float, crystal_damage: float, reduction: float) -> void:
	if not text.contains("Name: %s" % display_name):
		_fail("%s tooltip missing name %s" % [item_id, display_name])
	if not text.contains("Damage: %s" % _TooltipText.format_num(damage)):
		_fail("%s tooltip missing damage" % item_id)
	if not text.contains("Range: %s" % _TooltipText.format_num(attack_range)):
		_fail("%s tooltip missing range" % item_id)
	if not text.contains("Cooldown: %s" % _TooltipText.format_num(cooldown)):
		_fail("%s tooltip missing cooldown" % item_id)
	if not text.contains("Crystal damage: %s" % _TooltipText.format_num(crystal_damage)):
		_fail("%s tooltip missing crystal damage" % item_id)
	if not text.contains("Armor reduction: %s" % _TooltipText.format_num(reduction)):
		_fail("%s tooltip missing armor reduction" % item_id)
	if description != "" and not text.contains(description):
		_fail("%s tooltip missing description" % item_id)


func _check_panel() -> void:
	_TooltipPanel.show_item(self, "wooden_sword")
	await process_frame
	var tip := _TooltipPanel._inst
	if tip == null:
		_fail("tooltip panel was not created")
		return
	var shown := tip.current_text()
	var expected := _TooltipText.for_item("wooden_sword")
	if shown != expected:
		_fail("tooltip panel text does not match TooltipText.for_item")
	var body := tip.get_node_or_null("Tip/Body") as Label
	if body == null or body.text != expected:
		_fail("tooltip Body label missing the weapon text")
	_TooltipPanel.show_relic(self, "crystal_ward")
	if not tip.current_text().contains("Crystal Ward"):
		_fail("tooltip panel did not show the relic name")
	if not tip.current_text().contains("Effects:"):
		_fail("tooltip panel relic text missing Effects")
