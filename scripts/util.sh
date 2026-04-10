#!/usr/bin/env bash
# Workhorse shared utilities — sourced by all scripts

set -euo pipefail

# Check jq dependency
if ! command -v jq &>/dev/null; then
  echo '{"continue":false,"stopReason":"workhorse: jq is required but not found. Install with: brew install jq"}' >&1
  exit 0
fi

# Read stdin JSON (call once, store in WH_INPUT)
WH_INPUT=""
wh_read_stdin() {
  WH_INPUT="$(cat)"
}

# Get the git root of the main repo (not a worktree)
wh_project_root() {
  local toplevel
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1

  # Check if this is a worktree — if so, find the main repo
  local common_dir
  common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || { echo "$toplevel"; return 0; }

  # If common_dir is absolute and differs from .git, we're in a worktree
  if [[ "$common_dir" != ".git" && "$common_dir" != "$(git rev-parse --git-dir 2>/dev/null)" ]]; then
    # common_dir is like /path/to/main-repo/.git — strip /.git
    echo "${common_dir%/.git}"
  else
    echo "$toplevel"
  fi
}

# Read .claude/workspace.json from project root, returns {} if not found
wh_read_config() {
  local root
  root="$(wh_project_root)" || { echo "{}"; return 0; }
  local config_file="$root/.claude/workspace.json"
  if [[ -f "$config_file" ]]; then
    cat "$config_file"
  else
    echo "{}"
  fi
}

# Get a config value with fallback default
# Usage: wh_get_config '.worktree.installDeps' 'true'
wh_get_config() {
  local key="$1"
  local default="${2:-null}"
  local config
  config="$(wh_read_config)"
  local val
  val="$(echo "$config" | jq -r "$key // empty" 2>/dev/null)"
  if [[ -z "$val" ]]; then
    echo "$default"
  else
    echo "$val"
  fi
}

# Get a config array as newline-separated values
# Usage: wh_get_config_array '.worktree.copyFiles'
wh_get_config_array() {
  local key="$1"
  local config
  config="$(wh_read_config)"
  echo "$config" | jq -r "$key // [] | .[]" 2>/dev/null
}

# Infer module from a file path by walking up to find nearest pom.xml/package.json/pubspec.yaml
# Returns relative path from project root (e.g., "service", "webapp/frontend")
wh_infer_module() {
  local filepath="$1"
  local root
  root="$(wh_project_root)" || return 1

  local dir
  dir="$(dirname "$filepath")"

  while [[ "$dir" != "$root" && "$dir" != "/" && "$dir" != "." ]]; do
    if [[ -f "$dir/pom.xml" || -f "$dir/package.json" || -f "$dir/pubspec.yaml" ]]; then
      # Return relative path from root
      local rel="${dir#$root/}"
      echo "$rel"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  # No module found — might be at root
  echo "."
}

# Output JSON to block an action
wh_block() {
  local reason="$1"
  echo "{\"continue\":false,\"stopReason\":\"workhorse: $reason\"}"
}

# Output JSON system message (visible to user)
wh_log() {
  local message="$1"
  echo "{\"systemMessage\":\"workhorse: $message\"}"
}

# Output JSON to allow with context
wh_context() {
  local event="$1"
  local context="$2"
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"$event\",\"additionalContext\":\"$context\"}}"
}
