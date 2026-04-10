#!/usr/bin/env bash
# PostToolUse hook (Write|Edit): auto-format the edited file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util.sh"

wh_read_stdin

# Check if formatting is disabled
disabled="$(wh_get_config '.formatting.disabled' 'false')"
if [[ "$disabled" == "true" ]]; then
  exit 0
fi

# Extract file path from hook input
FILEPATH="$(echo "$WH_INPUT" | jq -r '.tool_input.file_path // .tool_response.filePath // empty')"
if [[ -z "$FILEPATH" || ! -f "$FILEPATH" ]]; then
  exit 0
fi

# Detect formatter
formatter_cmd="$("$SCRIPT_DIR/detect-formatter.sh" "$FILEPATH")"
if [[ -z "$formatter_cmd" ]]; then
  exit 0
fi

# Run formatter — suppress all output, never fail
eval "$formatter_cmd" >/dev/null 2>&1 || true
