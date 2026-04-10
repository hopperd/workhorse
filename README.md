# Workhorse

Claude Code plugin for workspace automation.

## Features

- **Worktree lifecycle** — automatically copy gitignored config/secrets into new worktrees and install dependencies
- **Post-edit formatting** — auto-detect and run the right formatter after file edits
- **Git workflow enforcement** — protect branches, validate commit messages, enforce worktree usage, pre-commit build checks, foreign changes guard

## Installation

Add to `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "workhorse": {
      "source": {
        "source": "github",
        "repo": "hopperd/workhorse"
      }
    }
  },
  "enabledPlugins": {
    "workhorse@workhorse": true
  }
}
```

## Configuration

Create `.claude/workspace.json` in your project (optional — smart defaults apply without it):

```json
{
  "worktree": {
    "copyFiles": ["path/to/secret-config.yml"],
    "copyPatterns": [".env*"],
    "installDeps": true
  },
  "formatting": {
    "overrides": {
      "*.java": "mvn spotless:apply -pl {module} -q"
    },
    "disabled": false
  },
  "git": {
    "commitPattern": "^[A-Z]+-\\d+: .+",
    "commitPatternHelp": "Expected format: LG-42: description",
    "protectedBranches": ["main", "master"],
    "requireWorktree": true
  }
}
```

Run `/workhorse:setup` to generate this interactively.

## Skills

- `/workhorse:setup` — interactive wizard to create `.claude/workspace.json`
- `/workhorse:status` — show detected config, formatters, git rules
- `/workhorse:branch-cleanup` (or `/cleanup`) — clean up stale local branches

## Requirements

- `jq` (install with `brew install jq`)
