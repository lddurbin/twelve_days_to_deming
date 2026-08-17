---
name: ship-it
description: Commit changes, push branch, create PR, then remind user of review workflow
---

Perform these steps in order:

1. **Changelog entry**: If this branch's changes are user-facing (new content, features, fixes to visible bugs, accessibility improvements, removals) rather than internal-only (CI tweaks, refactors, dependency bumps, comment/typo fixes), add an entry to `docs/changesets/` following the format in `docs/changesets/README.md`. Include it in the same commit as the change.

2. **Commit**: Stage and commit all current changes on this branch. Follow the repository's commit message conventions (check recent `git log` for style). Use a concise, meaningful commit message.

3. **Push**: Push the current branch to origin with `-u` flag.

4. **Create PR**: Create a pull request using `gh pr create`. Write a clear title and body that gives the reviewer useful context:
   - Summarise what changed and why
   - Reference any related GitHub issues (check the branch name for issue numbers)
   - Include a test plan section

5. **Remind the user of next steps**: After the PR is created, print this exact block:

```
--- Next steps ---
The PR is up. When your reviewer is ready:

  1. /loop 2m /pr-feedback    <- auto-responds to review comments
  2. /merge-pr                <- merge once approved

Tip: start the loop now so it's ready when comments arrive.
------------------
```
