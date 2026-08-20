#!/usr/bin/env bash
# Capture gameplay frame-time profile report to scratch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export CRYSTALSTORM_SCRATCH="${CRYSTALSTORM_SCRATCH:-/tmp/grok-goal-59b157a7ebbb/implementer}"
export PROFILE_SESSION_SEC="${PROFILE_SESSION_SEC:-45}"
mkdir -p "$CRYSTALSTORM_SCRATCH"
godot --headless --path "$ROOT" -s scripts/profile_gameplay.gd 2>&1 | tee "$CRYSTALSTORM_SCRATCH/profile_gameplay.log"
echo "Report: $CRYSTALSTORM_SCRATCH/gameplay_profile_report.md"