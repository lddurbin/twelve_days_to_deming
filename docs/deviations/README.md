# Deviations log — per-entry source files

This directory holds the **source of truth** for the project's deviations log.
The stitched view at [`../deviations-from-source.md`](../deviations-from-source.md)
is a build artifact regenerated from the files here.

## Why this layout

Previously every deviation was a top-of-file insertion into a single 71 KB
Markdown monolith. Two PRs landing in the same week reliably collided on
`docs/deviations-from-source.md` because both were editing the same first line
of the same file — a positional conflict that had to be hand-resolved on every
rebase. Splitting one entry per file turns the operation from a *positional*
edit into an *additive* one, which git merges cleanly.

## Adding a new entry

1. Create `YYYY-MM-DD-short-slug.md` here. Use today's date in New Zealand
   local time (UTC+12 NZST in winter, UTC+13 NZDT in daylight-saving months);
   the project records dates in that timezone for consistency with the
   maintainer's location. The file starts with a `## YYYY-MM-DD — title`
   heading and contains the standard fields documented in `_preamble.md`:
   **What**, **Where**, **Source reference**, **Why**, **Decided in**,
   **Landed in**.
2. Run `Rscript scripts/build-deviations-log.R` from the repo root.
3. Commit both the new entry file and the regenerated `docs/deviations-from-source.md`.

When a Pending entry lands, bump its "Landed in" field to the merge commit /
PR number in the per-entry file, then re-run the build script.

## Ordering

The build script sorts entry files by filename descending. The `YYYY-MM-DD`
prefix produces newest-first chronological order across days; within the same
date, entries fall in alphabetical order by slug. If you care about preserving
the merge order of multiple same-day entries, pick slugs that sort in the order
you want (the build script does not consult anything other than the filename).

## Why a stitched file at all

The stitched `docs/deviations-from-source.md` is what
[`changes-from-source.qmd`](../../changes-from-source.qmd) links to for readers
who want the single-document view. Keeping that file in git (rather than
gitignoring it) means GitHub's web UI renders the full log on one page and
external links keep working. The cost is one mechanical regen step per PR —
much smaller than the positional-conflict tax it replaces.
