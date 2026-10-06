#!/usr/bin/env bash
# SessionStart hook: register statusline command in user settings
set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
STATUSLINE_CMD="${CLAUDE_PLUGIN_ROOT}/scripts/statusline.py"
REFRESH_INTERVAL=60

# Ensure settings file exists
if [ ! -f "$SETTINGS_FILE" ]; then
  echo '{}' > "$SETTINGS_FILE"
fi

# Check if statusLine is already configured for this plugin
CURRENT=$(jq -r '"\(.statusLine.command // "")\t\(.statusLine.refreshInterval // "")"' "$SETTINGS_FILE" 2>/dev/null || echo "")
if [ "$CURRENT" = "$STATUSLINE_CMD"$'\t'"$REFRESH_INTERVAL" ]; then
  exit 0
fi

# Merge statusLine config into settings.json
TEMP_FILE=$(mktemp)
jq --arg cmd "$STATUSLINE_CMD" --argjson interval "$REFRESH_INTERVAL" \
  '.statusLine = {"type": "command", "command": $cmd, "refreshInterval": $interval}' "$SETTINGS_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$SETTINGS_FILE"
