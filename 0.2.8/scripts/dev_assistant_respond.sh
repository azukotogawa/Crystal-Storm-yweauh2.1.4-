#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPLY="${*:-Acknowledged.}"
godot --headless --path "$ROOT" -s "$ROOT/scripts/dev_assistant_respond.gd" -- "$REPLY"