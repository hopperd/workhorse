#!/usr/bin/env bash
# WorktreeCreate hook: install dependencies in new worktrees (runs async)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util.sh"

wh_read_stdin

WORKTREE_PATH="$(echo "$WH_INPUT" | jq -r '.worktree_path // empty')"
if [[ -z "$WORKTREE_PATH" ]]; then
  exit 0
fi

# Check config — skip if installDeps is false
install_deps="$(wh_get_config '.worktree.installDeps' 'true')"
if [[ "$install_deps" == "false" ]]; then
  exit 0
fi

installed=()

# Function to install deps in a directory
install_in_dir() {
  local dir="$1"
  local reldir="${dir#$WORKTREE_PATH/}"
  [[ "$reldir" == "$dir" ]] && reldir="."

  if [[ -f "$dir/package-lock.json" ]]; then
    (cd "$dir" && npm ci --silent 2>/dev/null) && installed+=("npm ci in $reldir")
  elif [[ -f "$dir/yarn.lock" ]]; then
    (cd "$dir" && yarn install --frozen-lockfile --silent 2>/dev/null) && installed+=("yarn install in $reldir")
  elif [[ -f "$dir/pnpm-lock.yaml" ]]; then
    (cd "$dir" && pnpm install --frozen-lockfile --silent 2>/dev/null) && installed+=("pnpm install in $reldir")
  fi

  if [[ -f "$dir/pubspec.lock" ]]; then
    (cd "$dir" && flutter pub get 2>/dev/null) && installed+=("flutter pub get in $reldir")
  fi
}

# Check root level for Maven
if [[ -f "$WORKTREE_PATH/pom.xml" ]]; then
  (cd "$WORKTREE_PATH" && mvn install -DskipTests -q 2>/dev/null) && installed+=("mvn install at root")
fi

install_in_dir "$WORKTREE_PATH"

# Check one level of subdirectories for additional package managers
for subdir in "$WORKTREE_PATH"/*/; do
  [[ -d "$subdir" ]] || continue
  install_in_dir "$subdir"
  # Check two levels deep (e.g., webapp/frontend)
  for subsubdir in "$subdir"*/; do
    [[ -d "$subsubdir" ]] || continue
    install_in_dir "$subsubdir"
  done
done

count=${#installed[@]}
if [[ $count -gt 0 ]]; then
  dep_list="$(printf '%s; ' "${installed[@]}")"
  dep_list="${dep_list%; }"
  wh_log "Installed dependencies: $dep_list"
fi
