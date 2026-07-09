#!/usr/bin/env bash
# Reply to the latest in-game DevAssistant request (for Cursor / external AI workflows).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPLY="${*:-Acknowledged.}"
godot --headless --path "$ROOT" -s "$ROOT/scripts/dev_assistant_respond.gd" -- "$REPLY"