---
name: sync-main
description: Switch to main, pull latest, delete stale local feature branches
disable-model-invocation: true
---

Perform these git operations in order:

1. `git checkout main`
2. `git pull origin main`
3. Prune remote-tracking references that no longer exist on the remote: `git fetch --prune`
4. Delete local branches whose upstream tracking branch is gone (i.e. merged and deleted on remote). Use `git branch -vv` to identify branches marked `[gone]`, then delete them. Warn before deleting any branch that has unmerged commits.
