class_name ProbePaths
extends RefCounted

const DEFAULT_SCRATCH_DIR := "/tmp/grok-goal-4d59198f47c0/implementer"


static func scratch_dir() -> String:
	var env := OS.get_environment("CRYSTALSTORM_SCRATCH").strip_edges()
	if env.is_empty():
		return DEFAULT_SCRATCH_DIR
	if env.ends_with(".md") or env.ends_with(".log"):
		return env.get_base_dir()
	return env


static func manual_verification_path() -> String:
	return ProjectSettings.globalize_path("res://manual_verification.md")


static func smoke_evidence_path() -> String:
	return scratch_dir().path_join("scripted_smoke_evidence.md")


static func display_evidence_path() -> String:
	return scratch_dir().path_join("display_session_evidence.md")


static func display_log_path() -> String:
	return scratch_dir().path_join("display_session.log")