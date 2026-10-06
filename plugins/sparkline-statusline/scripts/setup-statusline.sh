#!/usr/bin/env bash
# SessionStart / UserPromptSubmit hook: register statusline command in user settings
set -euo pipefail

# Desktop on Windows has no statusline and may lack jq
command -v jq >/dev/null 2>&1 || exit 0

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

# Sessions started before a plugin update keep running the old version's hook.
# Never let them point statusLine back to an older installed version.
version_of() {
  [[ "$1" =~ /sparkline-statusline/([0-9]+(\.[0-9]+)*)/scripts/statusline\.py$ ]] && echo "${BASH_REMATCH[1]}"
}
MINE=$(version_of "$STATUSLINE_CMD" || true)
THEIRS=$(version_of "${CURRENT%%$'\t'*}" || true)
if [ -n "$MINE" ] && [ -n "$THEIRS" ] && [ "$MINE" != "$THEIRS" ] \
  && [ "$(printf '%s\n%s\n' "$MINE" "$THEIRS" | sort -V | tail -1)" = "$THEIRS" ]; then
  exit 0
fi

# Merge statusLine config into settings.json
TEMP_FILE=$(mktemp)
jq --arg cmd "$STATUSLINE_CMD" --argjson interval "$REFRESH_INTERVAL" \
  '.statusLine = {"type": "command", "command": $cmd, "refreshInterval": $interval}' "$SETTINGS_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$SETTINGS_FILE"
