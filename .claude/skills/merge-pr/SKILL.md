---
name: merge-pr
description: Merge the current branch's PR into main after confirming it is approved
---

Perform these steps in order:

1. **Find the PR**: Use `gh pr view` to find the open PR for the current branch. If there is no open PR, tell the user and stop.

2. **Check approval status**: Use `gh pr status` or `gh pr view` to verify the PR has been approved and all checks pass. If not approved or checks are failing, tell the user what's blocking the merge and stop.

3. **Merge**: Merge the PR using `gh pr merge` with the `--squash` flag and `--delete-branch` to clean up the remote branch.

4. **Sync local**: After merging, switch to main and pull latest. `gh pr merge --delete-branch` usually removes the local feature branch too (when run from its checkout), so only run `git branch -D <name>` if `git branch --list <name>` still shows it — otherwise skip silently.

5. **Confirm**: Tell the user the PR has been merged and the local repo is synced.
