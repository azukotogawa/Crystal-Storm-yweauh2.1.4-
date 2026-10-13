extends SceneTree
## Town Rally PE: threatened town is readable; player arrival restores health + militia
## via LivingWorldDirector production path (try_rally / harness places player).
## Usage: godot --headless -s scripts/verify_town_rally.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("main missing")
		_ProbeExit.finish_tree(self, 1, "Town rally FAILED")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)

	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while compose and not bool(compose.get("_boot_done")) and frames < 2400:
		await process_frame
		frames += 1

	var lwd = get_first_node_in_group("living_world_director")
	var tdm = get_first_node_in_group("town_defense_manager")
	var em = get_first_node_in_group("entity_manager")
	var overlay_src := ""
	var overlay_script = load("res://ui/game_overlay.gd") as GDScript
	if overlay_script:
		overlay_src = overlay_script.source_code

	if lwd == null or tdm == null:
		_fail("LivingWorldDirector or TownDefenseManager missing")
		_ProbeExit.finish_tree(self, 1, "Town rally FAILED")
		return

	# Structural: HUD and rally surfaces present in production overlay.
	if "get_town_hud_line" not in overlay_src and "town_line" not in overlay_src:
		_fail("game_overlay must surface town HUD line")
	else:
		print("OK overlay town HUD wiring present")
	if "town_rallied" not in overlay_src:
		_fail("game_overlay must listen for town_rallied")
	else:
		print("OK overlay town_rallied wiring present")

	if not lwd.has_method("try_rally_at_player_column") or not lwd.has_method("rally_town_at"):
		_fail("LivingWorldDirector must expose try_rally_at_player_column + rally_town_at")
		_ProbeExit.finish_tree(self, 1, "Town rally FAILED")
		return
	if not tdm.has_method("restore_health") or not tdm.has_method("force_threat_state"):
		_fail("TownDefenseManager must expose restore_health + force_threat_state")
		_ProbeExit.finish_tree(self, 1, "Town rally FAILED")
		return

	var towns: Array = _FeatureRegistry.get_towns()
	if towns.is_empty():
		_fail("no towns seeded")
		_ProbeExit.finish_tree(self, 1, "Town rally FAILED")
		return

	var town: Dictionary = towns[0]
	var center: Vector2i = town.get("center", Vector2i.ZERO)
	print("town=%s center=%s" % [town.get("name", "?"), center])

	# Priority report / HUD before threat.
	var report_safe: Dictionary = lwd.get_priority_town_report()
	if report_safe.is_empty():
		_fail("priority town report empty with towns present")
	else:
		print("OK priority report name=%s state=%s dist=%.0f" % [
			report_safe.get("name"), report_safe.get("state_label"), float(report_safe.get("distance", -1))
		])
	var hud_safe: String = str(lwd.get_town_hud_line())
	if hud_safe == "":
		_fail("town HUD line empty")
	else:
		print("OK town HUD: %s" % hud_safe)

	# Force ALERT + damaged health; measure restore + militia via real harness path.
	tdm.force_threat_state(center, 1, 40.0)
	var hp_before: float = float(tdm.get_town_health(center))
	if hp_before > 45.0:
		_fail("force_threat_state did not set damaged health (%.1f)" % hp_before)
	else:
		print("OK threat HP before rally=%.1f" % hp_before)

	var report_threat: Dictionary = lwd.get_priority_town_report()
	if str(report_threat.get("state_label", "")) != "ALERT":
		_fail("priority report should prefer ALERT town got=%s" % report_threat.get("state_label"))
	else:
		print("OK priority prefers ALERT HUD=%s" % lwd.get_town_hud_line())

	var agents_before: int = em.get_active_entity_count() if em and em.has_method("get_active_entity_count") else 0
	var result: Dictionary = lwd.harness_rally_nearest_threatened_town()
	if result.is_empty():
		_fail("harness_rally returned empty — player proximity rally failed")
		_ProbeExit.finish_tree(self, 1, "Town rally FAILED")
		return
	print("OK rally result %s" % result)

	var hp_after: float = float(tdm.get_town_health(center))
	var restored: float = float(result.get("health_restored", 0.0))
	if restored <= 0.0 or hp_after <= hp_before:
		_fail("rally must restore town health %.1f→%.1f restored=%.1f" % [hp_before, hp_after, restored])
	else:
		print("OK town health %.1f → %.1f (+%.1f)" % [hp_before, hp_after, restored])

	var agents_after: int = em.get_active_entity_count() if em else agents_before
	if agents_after < agents_before + 1:
		_fail("rally must spawn militia agents %d → %d" % [agents_before, agents_after])
	else:
		print("OK militia agents %d → %d" % [agents_before, agents_after])

	if int(lwd.get_rallied_town_count()) < 1:
		_fail("rallied town count not tracked")
	else:
		print("OK rallied towns=%d" % lwd.get_rallied_town_count())

	# Idempotent: second rally same town must no-op.
	var again: Dictionary = lwd.try_rally_at_player_column()
	if not again.is_empty():
		_fail("second rally must be idempotent empty got=%s" % again)
	else:
		print("OK rally idempotent")

	# Double-grant health blocked by rally once (health unchanged on second).
	var hp_mid: float = float(tdm.get_town_health(center))
	lwd.rally_town_at(center)
	if absf(float(tdm.get_town_health(center)) - hp_mid) > 0.01:
		_fail("rally_town_at idempotent must not re-heal")
	else:
		print("OK rally_town_at no double heal")

	if _failed == 0:
		print("All town rally tests OK")
		_ProbeExit.finish_tree(self, 0, "All town rally tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "Town rally FAILED")
