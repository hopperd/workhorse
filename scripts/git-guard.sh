#!/usr/bin/env bash
# PreToolUse hook (Bash, filtered to git commands): enforces git workflow rules
# Checks (in order): protected branch, worktree enforcement, commit message,
# foreign changes guard, pre-commit build check

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util.sh"

wh_read_stdin

CMD="$(echo "$WH_INPUT" | jq -r '.tool_input.command // empty')"
if [[ -z "$CMD" ]]; then
  exit 0
fi

# Fast path: only handle git commands
if [[ ! "$CMD" =~ ^git[[:space:]] ]]; then
  exit 0
fi

# Load config once
CONFIG="$(wh_read_config)"

# ── Helper: get config value from pre-loaded CONFIG ──
cfg() {
  local key="$1"
  local default="${2:-}"
  local val
  val="$(echo "$CONFIG" | jq -r "$key // empty" 2>/dev/null)"
  if [[ -z "$val" ]]; then
    echo "$default"
  else
    echo "$val"
  fi
}

cfg_array() {
  local key="$1"
  echo "$CONFIG" | jq -r "$key // [] | .[]" 2>/dev/null
}

# ── Detect command type ──
is_commit=false
is_destructive=false

if [[ "$CMD" =~ git[[:space:]]+commit ]]; then
  is_commit=true
fi

# Only flag branch-level destructive operations, not file-level restores
# git checkout <branch> = destructive (switching branches with uncommitted changes)
# git checkout HEAD -- <file> = safe (restoring a specific file)
# git checkout -- <file> = safe (restoring a specific file)
# git restore <file> = safe (restoring a specific file)
# git stash = destructive (hides uncommitted changes)
# git reset --hard = destructive (discards changes)
if [[ "$CMD" =~ git[[:space:]]+stash ]] || [[ "$CMD" =~ git[[:space:]]+reset[[:space:]]+--hard ]]; then
  is_destructive=true
elif [[ "$CMD" =~ git[[:space:]]+checkout ]] && [[ ! "$CMD" =~ --[[:space:]] ]] && [[ ! "$CMD" =~ git[[:space:]]+checkout[[:space:]]+(HEAD|FETCH_HEAD|ORIG_HEAD) ]]; then
  # checkout without -- is a branch switch (destructive)
  # checkout with -- or checkout HEAD is a file restore (safe)
  is_destructive=true
fi

# If neither a commit nor destructive command, nothing to check
if [[ "$is_commit" == false && "$is_destructive" == false ]]; then
  exit 0
fi

# ── Check 1: Protected branch (commit only) ──
if [[ "$is_commit" == true ]]; then
  current_branch="$(git branch --show-current 2>/dev/null)"
  # Default protected branches
  protected="$(cfg_array '.git.protectedBranches')"
  if [[ -z "$protected" ]]; then
    protected=$'main\nmaster'
  fi

  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue
    if [[ "$current_branch" == "$branch" ]]; then
      wh_block "Cannot commit directly to '$current_branch'. Use a worktree or feature branch."
      exit 0
    fi
  done <<< "$protected"
fi

# ── Check 2: Worktree enforcement (commit only) ──
if [[ "$is_commit" == true ]]; then
  require_worktree="$(cfg '.git.requireWorktree' 'false')"
  if [[ "$require_worktree" == "true" ]]; then
    git_dir="$(git rev-parse --git-dir 2>/dev/null)"
    common_dir="$(git rev-parse --git-common-dir 2>/dev/null)"

    # In a worktree, git-dir differs from common-dir
    is_worktree=false
    if [[ "$git_dir" != ".git" && "$git_dir" != "$(git rev-parse --show-toplevel 2>/dev/null)/.git" ]]; then
      is_worktree=true
    elif [[ "$common_dir" != ".git" && "$common_dir" != "$git_dir" ]]; then
      is_worktree=true
    fi

    if [[ "$is_worktree" == false ]]; then
      wh_block "Commits require a worktree. Use isolation:'worktree' or EnterWorktree."
      exit 0
    fi
  fi
fi

# ── Check 3: Commit message validation (commit only) ──
if [[ "$is_commit" == true ]]; then
  commit_pattern="$(cfg '.git.commitPattern' '')"
  if [[ -n "$commit_pattern" ]]; then
    # Extract commit message from -m "..." or -m '...'
    commit_msg=""
    if [[ "$CMD" =~ -m[[:space:]]+\"([^\"]+)\" ]]; then
      commit_msg="${BASH_REMATCH[1]}"
    elif [[ "$CMD" =~ -m[[:space:]]+\'([^\']+)\' ]]; then
      commit_msg="${BASH_REMATCH[1]}"
    elif [[ "$CMD" =~ -m[[:space:]]+\"\$\(cat ]]; then
      # HEREDOC style — try to extract first content line
      commit_msg="$(echo "$CMD" | sed -n '/^[[:space:]]*[A-Z]/p' | head -1 | sed 's/^[[:space:]]*//')"
    fi

    # Only validate if we could extract a message
    if [[ -n "$commit_msg" ]]; then
      # Strip leading whitespace
      commit_msg="$(echo "$commit_msg" | sed 's/^[[:space:]]*//')"
      if ! echo "$commit_msg" | grep -qP "$commit_pattern" 2>/dev/null; then
        # Fallback for systems without PCRE grep
        if ! echo "$commit_msg" | grep -qE "$commit_pattern" 2>/dev/null; then
          help="$(cfg '.git.commitPatternHelp' "Commit message doesn't match pattern: $commit_pattern")"
          wh_block "$help"
          exit 0
        fi
      fi
    fi
  fi
fi

# ── Check 4: Foreign changes guard (destructive commands only) ──
if [[ "$is_destructive" == true ]]; then
  changes="$(git status --porcelain 2>/dev/null)"
  if [[ -n "$changes" ]]; then
    wh_block "Uncommitted changes detected. Review before proceeding — these may be from another session."
    exit 0
  fi
fi

# ── Check 5: Pre-commit build check (commit only) ──
if [[ "$is_commit" == true ]]; then
  staged_files="$(git diff --cached --name-only 2>/dev/null)"
  if [[ -z "$staged_files" ]]; then
    exit 0
  fi

  ROOT="$(wh_project_root)" || exit 0
  build_errors=""

  # Collect unique modules to build
  declare -A modules_to_check

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    module="$(wh_infer_module "$ROOT/$file")"
    ext="${file##*.}"

    case "$ext" in
      java)
        if [[ -z "${modules_to_check[$module]+_}" || "${modules_to_check[$module]}" != *"java"* ]]; then
          modules_to_check[$module]="${modules_to_check[$module]:-} java"
        fi
        ;;
      ts|tsx|vue|js|jsx)
        if [[ -z "${modules_to_check[$module]+_}" || "${modules_to_check[$module]}" != *"ts"* ]]; then
          modules_to_check[$module]="${modules_to_check[$module]:-} ts"
        fi
        ;;
      dart)
        if [[ -z "${modules_to_check[$module]+_}" || "${modules_to_check[$module]}" != *"dart"* ]]; then
          modules_to_check[$module]="${modules_to_check[$module]:-} dart"
        fi
        ;;
    esac
  done <<< "$staged_files"

  for module in "${!modules_to_check[@]}"; do
    types="${modules_to_check[$module]}"
    module_dir="$ROOT"
    [[ "$module" != "." ]] && module_dir="$ROOT/$module"

    if [[ "$types" == *"java"* && -f "$module_dir/pom.xml" ]]; then
      output="$(cd "$ROOT" && mvn compile -pl "$module" -am -DskipTests -q 2>&1)" || {
        build_errors="${build_errors}Java build failed in $module:\n$output\n\n"
      }
    fi

    if [[ "$types" == *"ts"* ]]; then
      if [[ -f "$module_dir/tsconfig.json" ]]; then
        # Check for vue-tsc (Vue project) vs tsc
        if [[ -f "$module_dir/package.json" ]] && jq -e '.dependencies["vue"] // .devDependencies["vue"]' "$module_dir/package.json" &>/dev/null; then
          output="$(cd "$module_dir" && npx vue-tsc --noEmit 2>&1)" || {
            build_errors="${build_errors}TypeScript check failed in $module:\n$output\n\n"
          }
        else
          output="$(cd "$module_dir" && npx tsc --noEmit 2>&1)" || {
            build_errors="${build_errors}TypeScript check failed in $module:\n$output\n\n"
          }
        fi
      fi
    fi

    if [[ "$types" == *"dart"* ]]; then
      if [[ -f "$module_dir/pubspec.yaml" ]]; then
        output="$(cd "$module_dir" && flutter analyze --no-fatal-infos 2>&1)" || {
          build_errors="${build_errors}Flutter analyze failed in $module:\n$output\n\n"
        }
      fi
    fi
  done

  if [[ -n "$build_errors" ]]; then
    # Truncate to avoid huge JSON
    truncated="$(echo -e "$build_errors" | head -30)"
    wh_block "Pre-commit build check failed:\n$truncated"
    exit 0
  fi
fi

# All checks passed
exit 0
