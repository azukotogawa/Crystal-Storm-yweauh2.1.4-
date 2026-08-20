#!/usr/bin/env bash
# Regenerate assets/tiles/Cube.png from scripts/regenerate_cube_atlas.py
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 scripts/regenerate_cube_atlas.py
echo "Run: godot --headless --path . -s scripts/verify_terrain_atlas_style.gd"