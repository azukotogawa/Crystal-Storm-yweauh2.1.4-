#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SCRATCH="${CRYSTALSTORM_SCRATCH:-/tmp/grok-goal-d95151e877bc/implementer}"
mkdir -p "$SCRATCH"

export CRYSTALSTORM_SCRATCH="$SCRATCH"
export CRYSTALSTORM_GPU_PROBE_HEADLESS=1
export CRYSTALSTORM_PERF_PRESET=medium
export CRYSTALSTORM_PROBE_ABRUPT_EXIT=1

echo "=== crystal render baseline (legacy) ==="
CRYSTALSTORM_CRYSTAL_RENDERER=legacy godot --headless --path . -s scripts/crystal_render_benchmark.gd

echo "=== crystal render after (procedural) ==="
CRYSTALSTORM_CRYSTAL_RENDERER=procedural godot --headless --path . -s scripts/crystal_render_benchmark.gd

echo "=== crystal render compare ==="
godot --headless --path . -s scripts/verify_crystal_renderer_perf.gd