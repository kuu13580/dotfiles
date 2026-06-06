#!/usr/bin/env bash
# SessionStart hook: register statusline command in user settings
set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
STATUSLINE_CMD="${CLAUDE_PLUGIN_ROOT}/scripts/statusline.py"

# Ensure settings file exists
if [ ! -f "$SETTINGS_FILE" ]; then
  echo '{}' > "$SETTINGS_FILE"
fi

# Check if statusLine is already pointing to this plugin
CURRENT_CMD=$(jq -r '.statusLine.command // ""' "$SETTINGS_FILE" 2>/dev/null || echo "")
if [ "$CURRENT_CMD" = "$STATUSLINE_CMD" ]; then
  exit 0
fi

# Merge statusLine config into settings.json
TEMP_FILE=$(mktemp)
jq --arg cmd "$STATUSLINE_CMD" '.statusLine = {"type": "command", "command": $cmd}' "$SETTINGS_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$SETTINGS_FILE"
