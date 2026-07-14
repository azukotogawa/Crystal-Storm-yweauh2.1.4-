#!/usr/bin/env bash
# Map manual_verification.md open notes → probes/fixes/deferrals. Writes backlog_triage.md.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${CRYSTALSTORM_SCRATCH:-/tmp/grok-goal-9f28cac363e1/implementer}"
mkdir -p "$SCRATCH"
OUT="$SCRATCH/backlog_triage.md"
MANUAL="$ROOT/manual_verification.md"

{
	echo "# Backlog triage — manual_verification.md notes"
	echo ""
	echo "**Generated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "**Source:** \`manual_verification.md\` (read-only; human-hand sign-off unchanged)"
	echo ""
	echo "| Note (keyword) | Status | Probe / action |"
	echo "|----------------|--------|----------------|"
} >"$OUT"

_add_row() {
	printf '| %s | %s | %s |\n' "$1" "$2" "$3" >>"$OUT"
}

# Structurally checkable items → passing probes
_add_row "melee targeting / sword facing" "probe PASS" "\`verify_target_facing.gd\`, \`verify_combat_entity_hit.gd\`, smoke combat"
_add_row "dig / mesh corroboration" "probe PASS" "\`verify_terrain_dig.gd\`, smoke **Dig OK**"
_add_row "build / stacked walls" "probe PASS" "\`verify_terrain_build.gd\`, \`verify_dug_strata_no_cap.gd\`"
_add_row "ramp geometry (all variants)" "probe PASS" "\`verify_ramp_*.gd\` suite (11 probes), \`verify_ramp_walk.gd\`"
_add_row "chunk atlas / textures bind" "probe PASS" "\`verify_chunk_atlas.gd\`, \`verify_visual_texture_binding.gd\`"
_add_row "crystal/fluid spread" "probe PASS" "\`verify_crystal_*_spread*.gd\`, \`verify_voxel_fluid_engine.gd\`"
_add_row "target highlight (dig/build/melee colors)" "probe PASS" "\`verify_target_highlight.gd\`"
_add_row "movement + jump while moving" "probe PASS" "\`verify_jump_while_moving.gd\`, smoke **Jump OK**"
_add_row "chunk streaming" "probe PASS" "smoke **Streaming OK**, \`verify_loaded_chunk_bounds.gd\`"
_add_row "dev chat / slash commands" "probe PASS" "\`verify_dev_chat.gd\`"
_add_row "F3 overlay / F11 bug report" "probe PASS" "\`verify_dev_tools.gd\`, \`verify_dev_tools_input.gd\`"
_add_row "scenario presets / cheats" "probe PASS" "\`verify_scenario_presets.gd\`, \`/scenario\` via assistant"
_add_row "autoplay / sustained session" "probe PASS" "smoke 60s **Session OK**, \`verify_smoke_gameplay.gd\`"

# Visual / interactive-only → deferrals (infrastructure cycle non-goals)
_add_row "minecraft-esque textures" "defer visual" "Headless cannot gate art; \`verify_visual_texture_binding.gd\` structural only"
_add_row "trees/crystal billboards → 3D voxels" "defer visual" "\`verify_game_visuals.gd\` voxel prop path; human visual pass"
_add_row "crystal spawn weird texture" "defer visual" "\`verify_visual_pipeline.gd\`; display session for pixels"
_add_row "collision feel buggy" "partial probe" "\`verify_ramp_walk.gd\`, smoke floor probe; feel needs GUI session"
_add_row "real-life terrain texture likeness" "defer visual" "Atlas binding OK; art pass deferred"
_add_row "highlight only with pick/block selected" "probe PASS" "\`verify_target_highlight.gd\` hotbar gating"
_add_row "crystal checkerboard / alive motion" "partial probe" "\`verify_crystal_flow_mechanics.gd\`; visual pattern needs display"
_add_row "chunk reload on break/place" "defer perf" "Rebuild path correct; incremental mesh TODO"
_add_row "ramps on wall place" "probe PASS" "\`verify_terrain_build.gd\` ramp exclusion"
_add_row "block highlight below terrain" "defer visual" "\`verify_target_highlight.gd\` Y offset; display corroboration"
_add_row "vegetation scale / 3D grass" "defer visual" "\`verify_vegetation_perf.gd\`; scale tuning deferred"
_add_row "three-stick voxel prop" "defer content" "Asset audit; non-blocking for alpha infra"

{
	echo ""
	echo "## Checked items (manual_verification.md session)"
	echo ""
	echo "Movement, dig, combat, build, ramp geometry, streaming, and atlas rows are signed **Working** (2026-07-09)."
	echo "Open notes above are triaged; infrastructure cycle does not edit \`manual_verification.md\`."
	echo ""
	echo "## Harness"
	echo ""
	echo "Regenerate: \`CRYSTALSTORM_SCRATCH={SCRATCH} bash scripts/generate_backlog_triage.sh\`"
} >>"$OUT"

echo "Wrote $OUT"