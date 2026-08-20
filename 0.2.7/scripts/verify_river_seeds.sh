#!/usr/bin/env bash
# Verify river generation on multiple seeds. Run from project root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SEEDS=(12349 42 99991 17001)
for s in "${SEEDS[@]}"; do
  echo "--- seed $s ---"
  RIVER_VERIFY_SEED="$s" timeout 120 godot --headless --path . -s verify_river_specs.gd
done
echo "All seeds passed."