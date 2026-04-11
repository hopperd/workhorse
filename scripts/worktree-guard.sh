#!/usr/bin/env bash
# PreToolUse hook (Write|Edit): warn when editing files on protected branches
# without a worktree. Warns but does NOT block — agents should course-correct,
# humans can ignore safely.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util.sh"

wh_read_stdin

# Extract file path
FILEPATH="$(echo "$WH_INPUT" | jq -r '.tool_input.file_path // empty')"
if [[ -z "$FILEPATH" ]]; then
  exit 0
fi

# Only enforce in git repos
git rev-parse --git-dir &>/dev/null || exit 0

# Check config
CONFIG="$(wh_read_config)"
require_worktree="$(echo "$CONFIG" | jq -r '.git.requireWorktree // empty' 2>/dev/null)"
if [[ "$require_worktree" != "true" ]]; then
  exit 0
fi

# Check if we're in a worktree
git_dir="$(git rev-parse --git-dir 2>/dev/null)"
common_dir="$(git rev-parse --git-common-dir 2>/dev/null)"

is_worktree=false
if [[ "$git_dir" != ".git" && "$git_dir" != "$(git rev-parse --show-toplevel 2>/dev/null)/.git" ]]; then
  is_worktree=true
elif [[ "$common_dir" != ".git" && "$common_dir" != "$git_dir" ]]; then
  is_worktree=true
fi

if [[ "$is_worktree" == true ]]; then
  exit 0
fi

# Check if on a protected branch
current_branch="$(git branch --show-current 2>/dev/null)"
protected="$(echo "$CONFIG" | jq -r '.git.protectedBranches // ["main","master"] | .[]' 2>/dev/null)"

while IFS= read -r branch; do
  [[ -z "$branch" ]] && continue
  if [[ "$current_branch" == "$branch" ]]; then
    wh_log "WARNING: You are editing files on '$current_branch' without a worktree. If you are an agent doing implementation work, STOP and use EnterWorktree or isolation:'worktree' before continuing."
    exit 0
  fi
done <<< "$protected"

exit 0
