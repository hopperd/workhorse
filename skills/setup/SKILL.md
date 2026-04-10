---
name: setup
description: Interactive wizard to create or update .claude/workspace.json for the current project. Detects project type, gitignored secrets, formatters, and proposes a configuration.
---

# Workhorse Setup

Create or update the `.claude/workspace.json` configuration for the current project.

## Process

1. **Detect project type** — scan the project root for:
   - `pom.xml` → Java/Maven project
   - `package.json` → Node.js project (check for Vue, React, etc.)
   - `pubspec.yaml` → Flutter/Dart project
   - `Cargo.toml` → Rust project
   - `pyproject.toml` → Python project

2. **Find gitignored config files** — run:
   ```bash
   git ls-files --others --ignored --exclude-standard
   ```
   Filter for common secret/config patterns: `.env*`, `*local-override*`, `*.local.*`, `*secret*`, `*.key`, `*.p8`, `*.jks`

3. **Detect formatters** — check for:
   - `.prettierrc` or prettier in `package.json` → Prettier
   - `spotless-maven-plugin` in any `pom.xml` → Spotless
   - `pubspec.yaml` → `dart format`
   - `rustfmt.toml` → rustfmt
   - `pyproject.toml` with ruff/black → ruff/black

4. **Propose configuration** — present a complete `.claude/workspace.json` based on detection:
   - `worktree.copyFiles`: list the gitignored config files found
   - `worktree.copyPatterns`: suggest patterns based on what was found
   - `worktree.installDeps`: default `true`
   - `formatting.overrides`: only if auto-detection won't work (e.g., Spotless needs explicit config)
   - `git.protectedBranches`: default `["main"]`
   - `git.requireWorktree`: ask the user
   - `git.commitPattern`: ask the user if they want one

5. **Confirm with user** — show the proposed JSON and ask if it looks right. Adjust based on feedback.

6. **Write the file** — save to `.claude/workspace.json`

7. **Gitignore check** — if `.claude/workspace.json` is not in `.gitignore`, ask if it should be added. Recommend yes if it reveals sensitive file paths.

8. **Clear formatter cache** — remove `/tmp/workhorse-fmt-*.json` so detection picks up the new config.
