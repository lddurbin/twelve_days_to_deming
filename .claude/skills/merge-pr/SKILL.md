---
name: merge-pr
description: Merge the current branch's PR into main after confirming it is approved (or exempt as sole-author work)
---

Perform these steps in order:

1. **Find the PR**: Use `gh pr view` to find the open PR for the current branch. If there is no open PR, tell the user and stop.

2. **Check approval status**: Gather the merge state in one call:

   ```
   gh pr view --json author,reviewDecision,reviews,reviewRequests,mergeStateStatus,statusCheckRollup
   ```

   **Checks must pass regardless of anything below.** If any check in `statusCheckRollup` is failing or still running, tell the user what's red and stop. No exemption applies to checks.

   Then, on approval:

   - `reviewDecision` is `APPROVED` → proceed to step 3.
   - `reviewDecision` is `CHANGES_REQUESTED` → stop and report. **Never exempt this**, even if the author is the only contributor. Someone asked for changes.
   - `reviewDecision` is `REVIEW_REQUIRED` → branch protection requires a review that hasn't happened. Stop and report; the merge would be refused anyway.
   - `reviewDecision` is empty (`""`) → no review exists and none is required. Apply the sole-author exemption in step 2a.

3. **Sole-author exemption (step 2a)**: GitHub does not let anyone approve their own PR, so a solo repo can never satisfy an approval gate. Treat the PR as approved when **all** of these hold:

   - `reviewDecision` is empty — not `CHANGES_REQUESTED`, not `REVIEW_REQUIRED`
   - `reviews` is empty — nobody has left a review of any kind
   - `reviewRequests` is empty — no review is pending from anyone. A requested reviewer means a review is genuinely wanted, so wait for it.
   - `mergeStateStatus` is `CLEAN` — confirms the repo has no unmet protection rule
   - The PR author equals the authenticated user: compare `author.login` against `gh api user --jq .login`

   If every condition holds, say plainly that you're merging under the sole-author exemption and continue to step 4. If any condition fails, stop and report which one.

   A passing bot review check (e.g. a `claude-review` workflow) is a *check*, not an approval — it's already covered by the checks rule above and never substitutes for this exemption.

4. **Merge**: Merge the PR using `gh pr merge` with the `--squash` flag and `--delete-branch` to clean up the remote branch.

5. **Sync local**: After merging, switch to main and pull latest. `gh pr merge --delete-branch` usually removes the local feature branch too (when run from its checkout), so only run `git branch -D <name>` if `git branch --list <name>` still shows it — otherwise skip silently.

6. **Confirm**: Tell the user the PR has been merged and the local repo is synced. If merging `main` triggers a deployment workflow, name it and link the run so the user knows a deploy is in flight.
