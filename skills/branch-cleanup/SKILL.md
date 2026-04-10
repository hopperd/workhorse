---
name: branch-cleanup
description: Interactive cleanup of stale local git branches — finds branches with deleted remotes, merged branches, and inactive branches.
---

# Branch Cleanup

Clean up stale local git branches interactively.

## Process

1. **Fetch latest remote state:**
   ```bash
   git fetch --prune
   ```

2. **Find stale branches in three categories:**

   **Category A — Remote deleted (gone):**
   ```bash
   git branch -vv | grep ': gone]'
   ```
   These branches tracked a remote that no longer exists.

   **Category B — Fully merged into main:**
   ```bash
   git branch --merged main | grep -v '^\*' | grep -v 'main'
   ```
   These branches have been merged and can safely be deleted.

   **Category C — Inactive (no commits in 30+ days):**
   For each local branch, check the last commit date:
   ```bash
   git log -1 --format='%ci' <branch>
   ```
   Flag branches where the last commit is more than 30 days old.

3. **Present the results** in a categorized list:
   ```
   ## Branches to clean up

   ### Remote deleted (safe to remove)
   - ai/lg-48-some-feature (gone from origin)
   - ai/lg-53-other-feature (gone from origin)

   ### Merged into main (safe to remove)
   - fix/typo-in-readme

   ### Inactive (30+ days, review before removing)
   - experiment/old-idea (last commit: 2026-02-15)
   ```

4. **Ask for confirmation** — present the full list and ask which categories to delete, or let the user pick individual branches.

5. **Delete confirmed branches:**
   ```bash
   git branch -d <branch>  # safe delete (refuses if not merged)
   ```
   Use `-D` only if the user explicitly confirms for unmerged branches.

6. **Prune worktrees:**
   ```bash
   git worktree prune
   ```

7. **Report results** — show what was deleted and what remains.
