---
name: status
description: Show current workhorse plugin state — detected config, formatters, git rules, and worktree copy list for debugging.
---

# Workhorse Status

Show the current workhorse configuration and detection state for this project.

## Process

1. **Read config** — check if `.claude/workspace.json` exists in the project root. If yes, read it. If no, report "using defaults".

2. **Show worktree settings:**
   - `copyFiles` list (or "none configured")
   - `copyPatterns` list (or show defaults)
   - `installDeps` value

3. **Detect and show formatters** — for each common extension (`.ts`, `.java`, `.dart`, `.vue`, `.py`, `.rs`), run the detection logic and report:
   ```
   .ts   → npx prettier --write {file}  (detected: .prettierrc)
   .java → mvn spotless:apply -pl {module}  (configured: workspace.json override)
   .dart → dart format {file}  (detected: pubspec.yaml)
   .vue  → npx prettier --write {file}  (detected: .prettierrc)
   .py   → (no formatter detected)
   ```

4. **Show git rules:**
   - Protected branches list
   - Worktree enforcement: on/off
   - Commit pattern: the regex and help text, or "none"

5. **Show cache status** — check if `/tmp/workhorse-fmt-*.json` exists for this project and report its contents.

Present everything in a clean, readable table format.
