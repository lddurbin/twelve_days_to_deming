# Changelog entries — per-entry source files

This directory is the **source of truth** for `CHANGELOG.md` and GitHub
Release notes. Each notable, user-facing change gets its own file here,
added in the same PR as the change. At release time,
[`scripts/cut-release.sh`](../../scripts/cut-release.sh) rolls every file in
this directory into a new `CHANGELOG.md` section and removes the consumed
files.

## Why this layout

A single running `CHANGELOG.md` that every PR edits is a positional-edit
magnet: two PRs open in the same week both want to insert a line at the top
of the same file, and one hand-resolves a conflict on rebase. This project
already solved that exact problem for the deviations log (see
[`docs/deviations/README.md`](../deviations/README.md) and
[#384](https://github.com/lddurbin/twelve_days_to_deming/issues/384)) by
splitting one entry per file, which turns the operation from *positional*
to *additive* — git merges those cleanly with no conflict, no matter how
many PRs are open in parallel. Changelog entries use the same shape.

This also gives release-cutting a natural cadence: entries accumulate here
between releases, and `CHANGELOG.md` itself is only touched once, deliberately,
when a release is cut — not on every PR.

## Adding a new entry

Skip this for internal-only changes (CI tweaks, refactors, dependency
bumps with no visible effect, typo fixes in comments). Add an entry for
anything a reader or contributor of the live site would notice: new
content, new features, fixes to visible bugs, accessibility improvements,
removals.

1. Create `YYYY-MM-DD-short-slug.md` here, using today's date in New Zealand
   local time (matches the convention in `docs/deviations/`).
2. Use this template:

   ```markdown
   ## YYYY-MM-DD — Short title

   - **Section**: Accessibility
   - **What**: One or two sentences, written for a reader of the release
     notes — not an internal description of the diff.
   - **PR**: #NNN
   ```

   `What` must be a single line — `scripts/cut-release.sh` reads only the
   first line of each field, so a wrapped or multi-line value silently
   loses everything after the first line. If it doesn't fit on one line,
   shorten it.

   `Section` is free text and controls grouping in the rolled-up changelog.
   Prefer one of the sections already used in [`CHANGELOG.md`](../../CHANGELOG.md)
   (`Course Content`, `Accessibility`, `Reader Experience`,
   `Infrastructure & Quality`, `Fixed`, `Polish & Refactors`) so entries land
   in a familiar group; an unrecognised value still works and is grouped
   under its own heading at the end.

3. Commit the new entry file alongside the change it describes. Nothing else
   needs to happen until someone cuts a release.

## Ordering

Within a section, `scripts/cut-release.sh` lists entries in filename order
(oldest first). Pick slugs that sort the way you want if you care about the
order of same-day entries — the script doesn't consult anything but the
filename and the `Section`/`What`/`PR` fields.

## Cutting a release

Run:

```sh
./scripts/cut-release.sh 0.2.0
```

This groups every file in this directory by `Section`, writes a new
`## [0.2.0] - YYYY-MM-DD` section into `CHANGELOG.md` (above the previous
release, below `## [Unreleased]`), and `git rm`s the consumed entry files —
their content now lives in `CHANGELOG.md`, and the original per-PR files
remain in git history if you need the fuller context later. It leaves the
working tree staged but uncommitted so you can review the diff before
committing. The script prints the exact `git tag` / `gh release create`
commands to run next.

Use `./scripts/cut-release.sh 0.2.0 --dry-run` to preview the generated
section without touching any files.
