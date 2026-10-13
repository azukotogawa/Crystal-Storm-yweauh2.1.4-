#!/usr/bin/env bash
# Terrain representation A/B benchmark (legacy MultiMesh vs surface ArrayMesh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SCRATCH="${CRYSTALSTORM_SCRATCH:-/tmp/grok-goal-67c05d4c55ed/implementer}"
mkdir -p "$SCRATCH"
export CRYSTALSTORM_SCRATCH="$SCRATCH"
export CRYSTALSTORM_PERF_PRESET="${CRYSTALSTORM_PERF_PRESET:-medium}"
LOG="$SCRATCH/terrain_surface_benchmark.log"
: >"$LOG"

echo "=== terrain surface representation verify ===" | tee -a "$LOG"
godot --headless --path "$ROOT" -s scripts/verify_terrain_surface_representation.gd 2>&1 \
  | tee "$SCRATCH/terrain_surface_verify.log" | tee -a "$LOG"

echo "=== incremental patch (surface mode) ===" | tee -a "$LOG"
godot --headless --path "$ROOT" -s scripts/verify_chunk_incremental_patch.gd 2>&1 \
  | tee "$SCRATCH/terrain_incremental_patch.log" | tee -a "$LOG"

echo "DONE artifacts in $SCRATCH"