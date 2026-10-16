extends RefCounted

const _Hands = preload("res://scripts/honest_bot/honest_input.gd")
const _Progress = preload("res://systems/progression_service.gd")
const _Skills = preload("res://systems/skill_service.gd")

const CHOICE_ORDER: Array[StringName] = [
	&"dash",
	&"crystal_pulse",
	&"fighter_passive",
	&"ground_slam",
	&"miner_passive",
	&"quick_wall",
	&"builder_passive",
]

var input = _Hands.new()
var level := 1
var xp := 0
var skill_points := 0
var spent := 0
var kills := 0
var lines: PackedStringArray = PackedStringArray()
var _picked: Dictionary = {}
var _steps: Array = []
var _accept_skill := ""


func release() -> void:
	input.release_all()


func summary_line() -> String:
	return "LEVEL %d XP %d POINTS %d" % [level, xp, maxi(skill_points - spent, 0)]


func note_other(source: String) -> void:
	lines.append("SKIP %s" % source)


func note_kill(tier: int) -> void:
	var gain := _Progress.xp_for_kill(tier)
	if gain <= 0:
		lines.append("SKIP kill tier %d" % tier)
		return
	kills += 1
	xp += gain
	lines.append("KILL tier %d xp %d" % [tier, gain])
	_raise()


func read_telemetry(tree: SceneTree) -> String:
	if tree == null or tree.root == null:
		return ""
	var node := tree.root.get_node_or_null("DifficultyTelemetry")
	if node == null or not node.has_method("xp_snapshot"):
		return ""
	var snap: Dictionary = node.xp_snapshot()
	var line := "XP_RATE %.4f gained %d" % [float(snap.get("per_minute", 0.0)), int(snap.get("gained", 0))]
	lines.append(line)
	return line


func tick(_delta: float) -> void:
	input.begin_tick()
	if _steps.is_empty():
		_enqueue()
	if _steps.is_empty():
		input.release_all()
		return
	var action := String(_steps.pop_front())
	input.pulse(action)
	if action == "ui_accept" and _accept_skill != "":
		lines.append("SKILL %s" % _accept_skill)
		_accept_skill = ""


func _raise() -> void:
	var guard := 0
	while guard < 64:
		var need := _Progress.xp_to_advance(level)
		if need <= 0 or xp < need:
			break
		xp -= need
		level += 1
		skill_points += 1
		lines.append("LEVEL %d" % level)
		guard += 1


func _enqueue() -> void:
	var skill_id := _next_skill()
	if skill_id == &"":
		return
	var cell := cell_of(skill_id)
	if cell.x < 0 or cell.y < 0:
		return
	_picked[skill_id] = true
	spent += _cost(skill_id)
	_accept_skill = String(skill_id)
	_steps.append("skill_tree")
	for _i in cell.x:
		_steps.append("ui_right")
	for _j in cell.y:
		_steps.append("ui_down")
	_steps.append("ui_accept")
	_steps.append("skill_tree")


func _next_skill() -> StringName:
	var left := skill_points - spent
	for skill_id in CHOICE_ORDER:
		if _picked.has(skill_id):
			continue
		if _cost(skill_id) > left:
			continue
		if cell_of(skill_id).x < 0:
			continue
		return skill_id
	return &""


func _cost(skill_id: StringName) -> int:
	var spec: Dictionary = _Skills.CATALOG.get(skill_id, {})
	return maxi(int(spec.get("cost", 1)), 0)


static func cell_of(skill_id: StringName) -> Vector2i:
	var svc := _Skills.new()
	var col := 0
	for tree in [_Skills.TREE_FIGHTER, _Skills.TREE_MINER, _Skills.TREE_BUILDER]:
		var ids: Array = svc.tree_ids(tree)
		var row: int = ids.find(skill_id)
		if row >= 0:
			svc.free()
			return Vector2i(col, row)
		col += 1
	svc.free()
	return Vector2i(-1, -1)
