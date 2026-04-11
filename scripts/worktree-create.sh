#!/usr/bin/env bash
# WorktreeCreate hook: copy gitignored config/secrets into new worktrees

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util.sh"

wh_read_stdin

WORKTREE_PATH="$(echo "$WH_INPUT" | jq -r '.worktree_path // empty')"
if [[ -z "$WORKTREE_PATH" ]]; then
  exit 0
fi

MAIN_ROOT="$(wh_project_root)" || exit 0

# Default patterns when no config exists
DEFAULT_PATTERNS=('.env' '.env.local' '.env.*.local' '**/application-local-override.yml' '**/*.local.*')

copied_files=()

# 1. Copy explicit files from config
while IFS= read -r relpath; do
  [[ -z "$relpath" ]] && continue
  src="$MAIN_ROOT/$relpath"
  dst="$WORKTREE_PATH/$relpath"
  if [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst" 2>/dev/null && copied_files+=("$relpath")
  fi
done < <(wh_get_config_array '.worktree.copyFiles')

# 2. Copy files matching patterns
# Build pattern list: config patterns or defaults
config_patterns="$(wh_read_config | jq -r '.worktree.copyPatterns // empty')"
if [[ -n "$config_patterns" && "$config_patterns" != "null" ]]; then
  patterns=()
  while IFS= read -r p; do
    [[ -n "$p" ]] && patterns+=("$p")
  done < <(echo "$config_patterns" | jq -r '.[]' 2>/dev/null)
  [[ ${#patterns[@]} -eq 0 ]] && patterns=("${DEFAULT_PATTERNS[@]}")
else
  patterns=("${DEFAULT_PATTERNS[@]}")
fi

# Find gitignored files in the main repo and match against patterns
if [[ ${#patterns[@]} -gt 0 ]]; then
  while IFS= read -r ignored_file; do
    [[ -z "$ignored_file" ]] && continue
    for pattern in "${patterns[@]}"; do
      # Use bash pattern matching via case statement
      case "$ignored_file" in
        $pattern)
          src="$MAIN_ROOT/$ignored_file"
          dst="$WORKTREE_PATH/$ignored_file"
          if [[ -f "$src" ]]; then
            # Skip if already copied by explicit copyFiles
            already_copied=false
            for already in "${copied_files[@]+"${copied_files[@]}"}"; do
              [[ "$already" == "$ignored_file" ]] && already_copied=true && break
            done
            if [[ "$already_copied" == false ]]; then
              mkdir -p "$(dirname "$dst")"
              cp "$src" "$dst" 2>/dev/null && copied_files+=("$ignored_file")
            fi
          fi
          break
          ;;
      esac
    done
  done < <(cd "$MAIN_ROOT" && git ls-files --others --ignored --exclude-standard 2>/dev/null)
fi

# Output result
count=${#copied_files[@]}
if [[ $count -gt 0 ]]; then
  file_list="$(printf '%s, ' "${copied_files[@]}")"
  file_list="${file_list%, }"
  wh_context "WorktreeCreate" "Copied $count config file(s) to worktree: $file_list"
else
  exit 0
fi
