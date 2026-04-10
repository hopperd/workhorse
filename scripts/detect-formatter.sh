#!/usr/bin/env bash
# Detect the appropriate formatter for a file.
# Usage: detect-formatter.sh <filepath>
# Output: formatter command with {file} and {module} placeholders resolved, or empty if none found.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util.sh"

FILEPATH="$1"
if [[ -z "$FILEPATH" ]]; then
  exit 0
fi

ROOT="$(wh_project_root)" || exit 0
EXT="${FILEPATH##*.}"

# Compute cache file path (macOS md5 vs Linux md5sum)
if command -v md5 &>/dev/null; then
  HASH="$(echo -n "$ROOT" | md5 -q)"
elif command -v md5sum &>/dev/null; then
  HASH="$(echo -n "$ROOT" | md5sum | cut -d' ' -f1)"
else
  HASH="default"
fi
CACHE_FILE="/tmp/workhorse-fmt-${HASH}.json"

# Check cache first
if [[ -f "$CACHE_FILE" ]]; then
  cached="$(jq -r ".\"$EXT\" // empty" "$CACHE_FILE" 2>/dev/null)"
  if [[ -n "$cached" ]]; then
    # Resolve placeholders
    module="$(wh_infer_module "$FILEPATH")"
    cached="${cached//\{file\}/$FILEPATH}"
    cached="${cached//\{module\}/$module}"
    echo "$cached"
    exit 0
  fi
  # If cache has a "none" marker for this extension, skip
  none_marker="$(jq -r ".\"${EXT}_none\" // empty" "$CACHE_FILE" 2>/dev/null)"
  if [[ -n "$none_marker" ]]; then
    exit 0
  fi
fi

formatter=""

# 1. Check config overrides
config="$(wh_read_config)"
overrides="$(echo "$config" | jq -r '.formatting.overrides // {} | to_entries[] | "\(.key)|\(.value)"' 2>/dev/null)"
while IFS='|' read -r pattern cmd; do
  [[ -z "$pattern" ]] && continue
  # Match glob pattern against filename
  case "$(basename "$FILEPATH")" in
    $pattern)
      formatter="$cmd"
      break
      ;;
  esac
  # Also try matching against extension pattern like "*.java"
  case ".$EXT" in
    ${pattern#\*})
      formatter="$cmd"
      break
      ;;
  esac
done <<< "$overrides"

# 2. Auto-detect if no override matched
if [[ -z "$formatter" ]]; then
  case "$EXT" in
    ts|tsx|js|jsx|vue|json|css|html)
      # Check for prettier
      if [[ -f "$ROOT/.prettierrc" || -f "$ROOT/.prettierrc.js" || -f "$ROOT/.prettierrc.json" || -f "$ROOT/.prettierrc.yml" || -f "$ROOT/.prettierrc.yaml" || -f "$ROOT/prettier.config.js" || -f "$ROOT/prettier.config.mjs" || -f "$ROOT/prettier.config.cjs" ]]; then
        formatter="npx prettier --write {file}"
      elif [[ -f "$ROOT/package.json" ]] && jq -e '.dependencies.prettier // .devDependencies.prettier' "$ROOT/package.json" &>/dev/null; then
        formatter="npx prettier --write {file}"
      fi
      ;;
    java)
      # Check for spotless in pom.xml (search from file upward)
      module="$(wh_infer_module "$FILEPATH")"
      module_dir="$ROOT"
      [[ "$module" != "." ]] && module_dir="$ROOT/$module"
      if [[ -f "$module_dir/pom.xml" ]] && grep -q 'spotless-maven-plugin' "$module_dir/pom.xml" 2>/dev/null; then
        formatter="mvn spotless:apply -pl {module} -q"
      elif [[ -f "$ROOT/pom.xml" ]] && grep -q 'spotless-maven-plugin' "$ROOT/pom.xml" 2>/dev/null; then
        formatter="mvn spotless:apply -pl {module} -q"
      fi
      # No google-java-format fallback — only Spotless
      ;;
    dart)
      if [[ -f "$ROOT/pubspec.yaml" ]] || find "$ROOT" -maxdepth 2 -name "pubspec.yaml" -print -quit 2>/dev/null | grep -q .; then
        formatter="dart format {file}"
      fi
      ;;
    rs)
      if [[ -f "$ROOT/rustfmt.toml" || -f "$ROOT/Cargo.toml" ]]; then
        formatter="rustfmt {file}"
      fi
      ;;
    py)
      if [[ -f "$ROOT/pyproject.toml" ]] && grep -q '\[tool\.ruff\]' "$ROOT/pyproject.toml" 2>/dev/null; then
        formatter="ruff format {file}"
      elif [[ -f "$ROOT/pyproject.toml" ]] && grep -q '\[tool\.black\]' "$ROOT/pyproject.toml" 2>/dev/null; then
        formatter="black {file}"
      fi
      ;;
  esac
fi

# Update cache
if [[ -n "$formatter" ]]; then
  if [[ -f "$CACHE_FILE" ]]; then
    jq --arg ext "$EXT" --arg fmt "$formatter" '. + {($ext): $fmt}' "$CACHE_FILE" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
  else
    jq -n --arg ext "$EXT" --arg fmt "$formatter" '{($ext): $fmt}' > "$CACHE_FILE"
  fi
else
  # Cache the "no formatter" result
  if [[ -f "$CACHE_FILE" ]]; then
    jq --arg ext "${EXT}_none" '. + {($ext): "true"}' "$CACHE_FILE" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
  else
    jq -n --arg ext "${EXT}_none" '{($ext): "true"}' > "$CACHE_FILE"
  fi
  exit 0
fi

# Resolve placeholders and output
module="$(wh_infer_module "$FILEPATH")"
formatter="${formatter//\{file\}/$FILEPATH}"
formatter="${formatter//\{module\}/$module}"
echo "$formatter"
