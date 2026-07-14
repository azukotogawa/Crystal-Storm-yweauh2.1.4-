#!/usr/bin/env bash
# Full headless verification suite — exit 0 when all suites pass.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export CRYSTALSTORM_SCRATCH="${CRYSTALSTORM_SCRATCH:-/tmp/grok-goal-042522dd00ca/implementer}"
mkdir -p "$CRYSTALSTORM_SCRATCH"

SUITES=(
	"res://scripts/verify_stability_perf.gd"
	"res://scripts/verify_game_visuals.gd"
	"res://scripts/verify_visual_pipeline.gd"
	"res://scripts/verify_visual_boot_order.gd"
	"res://scripts/verify_visual_texture_binding.gd"
	"res://scripts/verify_spawn_marker_visual.gd"
	"res://scripts/verify_entity_voxel_models.gd"
	"res://scripts/verify_vegetation_voxel_models.gd"
	"res://scripts/verify_vegetation_billboard_distance.gd"
	"res://scripts/verify_bootstrap_no_deadlock.gd"
	"res://scripts/verify_entity_spawn_order.gd"
	"res://scripts/verify_entity_spawn_alignment.gd"
	"res://scripts/verify_chunk_bootstrap.gd"
	"res://scripts/verify_player_jump.gd"
	"res://scripts/verify_player_collision.gd"
	"res://scripts/verify_built_wall_collision_main.gd"
	"res://scripts/verify_jump_while_moving.gd"
	"res://scripts/verify_terrain_dig.gd"
	"res://scripts/verify_terrain_build.gd"
	"res://scripts/verify_chunk_rebuild_perf.gd"
	"res://scripts/verify_chunk_incremental_scope.gd"
	"res://scripts/verify_terrain_edit_boundary_ring.gd"
	"res://scripts/verify_dug_strata_no_cap.gd"
	"res://scripts/verify_chunk_surface_zero.gd"
	"res://scripts/verify_chunk_atlas.gd"
	"res://scripts/verify_ramp_concave.gd"
	"res://scripts/verify_ramp_corner.gd"
	"res://scripts/verify_ramp_landing.gd"
	"res://scripts/verify_ramp_side_cell.gd"
	"res://scripts/verify_ramp_ridge_cardinal.gd"
	"res://scripts/verify_ramp_perpendicular.gd"
	"res://scripts/verify_ramp_flank_faces.gd"
	"res://scripts/verify_ramp_landing_corner.gd"
	"res://scripts/verify_ramp_cell_exclusive.gd"
	"res://scripts/verify_ramp_slope.gd"
	"res://scripts/verify_ramp_mesh_faces.gd"
	"res://scripts/verify_ramp_diagonal_floor.gd"
	"res://scripts/verify_ramp_wall_exclusion.gd"
	"res://scripts/verify_ramp_walk.gd"
	"res://scripts/verify_ramp_descent_walk.gd"
	"res://scripts/verify_ramp_step_corner_walk.gd"
	"res://scripts/verify_ramp_step_corner_main.gd"
	"res://scripts/verify_voxel_geometry_path.gd"
	"res://scripts/verify_target_highlight.gd"
	"res://scripts/verify_forward_highlight.gd"
	"res://scripts/verify_build_highlight_placement.gd"
	"res://scripts/verify_build_highlight_modifiers.gd"
	"res://scripts/verify_dig_highlight_placement.gd"
	"res://scripts/verify_target_facing.gd"
	"res://scripts/verify_melee_forward_targeting.gd"
	"res://scripts/verify_main_runtime_health.gd"
	"res://scripts/verify_manual_checklist_corroboration.gd"
	"res://scripts/verify_perf_preset_boot.gd"
	"res://scripts/verify_weapon_attack.gd"
	"res://scripts/verify_combat_entity_hit.gd"
	"res://scripts/verify_combat_crystal_damage.gd"
	"res://scripts/verify_item_icons.gd"
	"res://scripts/verify_entity_nav_perf.gd"
	"res://scripts/verify_visual_perf.gd"
	"res://scripts/verify_crystal_spread_limits.gd"
	"res://scripts/verify_crystal_frontier_density.gd"
	"res://scripts/verify_crystal_settling.gd"
	"res://scripts/verify_crystal_flow_mechanics.gd"
	"res://scripts/verify_crystal_live_spread.gd"
	"res://scripts/verify_full_game_loop.gd"
	"res://scripts/verify_crystal_terrain_routing.gd"
	"res://scripts/verify_voxel_fluid_engine.gd"
	"res://scripts/verify_crystal_grid_align.gd"
	"res://scripts/verify_entity_death_signal.gd"
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
	"res://scripts/verify_display_session_log.gd"
	"res://scripts/verify_dev_chat.gd"
	"res://scripts/verify_dev_tools.gd"
	"res://scripts/verify_dev_tools_input.gd"
	"res://scripts/verify_scenario_presets.gd"
)

# Main-scene probes SIGKILL on OK to avoid Godot teardown abort(134); match terminal marker not exit code.
declare -A ABRUPT_OK_MARKER=(
	["res://scripts/verify_bootstrap_no_deadlock.gd"]="All bootstrap deadlock tests OK"
	["res://scripts/verify_main_runtime_health.gd"]="All main runtime health tests OK"
	["res://scripts/verify_crystal_live_spread.gd"]="All crystal live spread tests OK"
	["res://scripts/verify_full_game_loop.gd"]="All full game loop tests OK"
	["res://scripts/verify_manual_checklist_corroboration.gd"]="Manual checklist corroboration OK"
	["res://scripts/verify_scenario_presets.gd"]="All scenario preset tests OK"
	["res://scripts/verify_melee_forward_targeting.gd"]="All melee forward targeting tests OK"
	["res://scripts/verify_chunk_rebuild_perf.gd"]="All chunk rebuild perf tests OK"
	["res://scripts/verify_entity_spawn_alignment.gd"]="All entity spawn alignment tests OK"
	["res://scripts/verify_forward_highlight.gd"]="All forward highlight tests OK"
	["res://scripts/verify_build_highlight_placement.gd"]="All build highlight placement tests OK"
	["res://scripts/verify_dig_highlight_placement.gd"]="All dig highlight placement tests OK"
	["res://scripts/verify_built_wall_collision_main.gd"]="All built wall collision main tests OK"
	["res://scripts/verify_ramp_step_corner_main.gd"]="All ramp step-corner main tests OK"
	["res://scripts/verify_smoke_quit_path.gd"]="All smoke quit-path tests OK"
)

FAILED=0
for path in "${SUITES[@]}"; do
	echo ">>> Running ${path}"
	if [[ -n "${ABRUPT_OK_MARKER[$path]:-}" ]]; then
		out="$(env CRYSTALSTORM_PROBE_ABRUPT_EXIT=1 godot --headless --path "$ROOT" -s "$path" 2>&1 || true)"
		if grep -qF "${ABRUPT_OK_MARKER[$path]}" <<<"$out"; then
			echo "    OK"
		else
			echo "    FAIL (missing OK marker)"
			printf '%s\n' "$out" | tail -8
			FAILED=1
		fi
	elif godot --headless --path "$ROOT" -s "$path" >/dev/null 2>&1; then
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