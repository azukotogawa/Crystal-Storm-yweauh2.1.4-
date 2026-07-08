#!/usr/bin/env bash
# Full headless verification suite — exit 0 when all suites pass.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SUITES=(
	"res://scripts/verify_stability_perf.gd"
	"res://scripts/verify_game_visuals.gd"
	"res://scripts/verify_visual_pipeline.gd"
	"res://scripts/verify_entity_spawn_order.gd"
	"res://scripts/verify_chunk_bootstrap.gd"
	"res://scripts/verify_player_jump.gd"
	"res://scripts/verify_terrain_dig.gd"
	"res://scripts/verify_weapon_attack.gd"
	"res://scripts/verify_entity_nav_perf.gd"
	"res://scripts/verify_visual_perf.gd"
	"res://scripts/verify_crystal_spread_limits.gd"
	"res://scripts/verify_loaded_chunk_bounds.gd"
	"res://scripts/verify_topographical_map.gd"
	"res://scripts/verify_vegetation_perf.gd"
	"res://scripts/verify_main_thread_relief.gd"
	"res://scripts/verify_combat_parse.gd"
	"res://scripts/verify_spawn_goal.gd"
	"res://scripts/verify_maze_phase.gd"
	"res://scripts/verify_ruin_centers.gd"
	"res://scripts/verify_save_terrain.gd"
	"res://scripts/verify_save_slot_main.gd"
	"res://scripts/verify_evidence_split.gd"
	"res://scripts/verify_manual_pristine_after_probe.gd"
	"res://scripts/verify_display_probe_contract.gd"
	"res://scripts/verify_smoke_contract.gd"
	"res://scripts/verify_smoke_quit_path.gd"
	"res://scripts/verify_smoke_gameplay.gd"
)

FAILED=0
for path in "${SUITES[@]}"; do
	echo ">>> Running ${path}"
	if godot --headless --path "$ROOT" -s "$path" >/dev/null 2>&1; then
		echo "    OK"
	else
		echo "    FAIL (exit $?)"
		FAILED=1
	fi
done

if [[ $FAILED -eq 0 ]]; then
	echo ""
	echo "=== ALL VERIFY SUITES PASSED (${#SUITES[@]}) ==="
	exit 0
fi
exit 1