# Validation results — per-day/appendix provenance records

This directory answers three questions that were previously unanswerable
without re-running `scripts/validate-transcription.sh` and hoping someone
remembered the last result: when was Day N (or an appendix) last checked
against its source PDF, against which revision of that PDF, and what did it
find? See [#720](https://github.com/lddurbin/twelve_days_to_deming/issues/720).

## Why this layout

One file per day/appendix, not a shared file, for the same reason
[`docs/changesets/README.md`](../../../docs/changesets/README.md) and
[`docs/deviations/README.md`](../../../docs/deviations/README.md) already
use that shape: two validation runs landing in the same week would otherwise
collide on positional edits to one shared file. A result file is additive —
running the validator for Day 4 only ever touches `day-04.yml`.

## Format

`scripts/validate-transcription.sh` writes this file itself at the end of
every run — a human never hand-transcribes these numbers, so the record
can't drift from what was actually checked. Day files are named
`day-NN.yml` (zero-padded); appendix files are named `appendix-<slug>.yml`,
matching the existing `day-NN-manifest.yml` / `appendix-<slug>-manifest.yml`
naming one directory up.

```yaml
day: 4                        # or `appendix: <slug>` for appendix runs
validated_at: 2026-08-25      # local date the run completed
source_pdf: G.Day.4.09Jan20.pdf
source_sha256: <sha-256 of the source PDF>   # catches a silent re-export
scorer_version: <content hash of the comparison pipeline — see below>
thresholds:
  missing: 0.40
  altered: 0.98
  unsourced: 0.25
counts:
  pdf_paragraphs: 137
  qmd_paragraphs: 135
  matched_cleanly: 48
  altered: 76
  flagged_sentences: 130
  near_certain: 45
  missing: 13
  unsourced: 5
  unsourced_sentences: 5
```

`source_sha256` hashes the PDF's bytes, not just its filename — Neave's
source PDFs have been re-exported before with the same name, and a filename
match alone wouldn't catch that the content underneath had changed.

`scorer_version` is a content hash, not a commit SHA — so an uncommitted
local edit to the pipeline is caught too, not just a merged one. It is a
**content identity check, not a timestamp**: it tells you whether a result
was produced by today's comparison logic, not how long ago that was.

It covers *every* file that can change what a run reports, listed as
`SCORER_VERSION_FILES` in
[`scripts/lib/scorer-version.sh`](../../../scripts/lib/scorer-version.sh) —
currently `scripts/lib/paragraph_similarity.py` and
`scripts/validate-transcription.sh`. Until
[#737](https://github.com/lddurbin/twelve_days_to_deming/issues/737) it hashed
the scorer alone, which understated the pipeline: PDF text extraction, QMD
stripping, and the paragraph-length filters all live in the shell script, and
a behaviour-changing edit to any of them produced results the staleness check
happily called fresh.

The value is a hash of a sorted `<path> <blob-hash>` manifest, so it is
independent of the order the files are listed in, and moves when a file joins
or leaves the list. `scorer-version.sh` deliberately does not list *itself*:
it is the file that computes the value, so any edit there that could change
the result already does, and listing it would only invalidate every recorded
result on a comment edit.

That one definition is `source`d by both the script that writes these files
and the script that checks them, so the two cannot drift apart about what
"fresh" means. `tests/test_scorer_version.py` pins that, along with the
requirement that every hashed file also appears in the staleness workflow's
`paths:` filter — a file that is hashed but not filtered is a check that
never fires on the edit it was added to catch.

There is deliberately no pass/fail verdict field. With 446 known near-certain
findings outstanding across the corpus as of #719's baseline, every day would
read "fail" — a permanently red signal nobody reads. Record the numbers and
let a diff across runs be the signal instead.

## Staleness

[`scripts/check-validation-staleness.sh`](../../../scripts/check-validation-staleness.sh),
run in CI by
[`.github/workflows/validation-staleness.yml`](../../../.github/workflows/validation-staleness.yml),
compares each file's `scorer_version` against the same value recomputed from
the pipeline's current contents. It needs no PDFs — the source PDFs are
gitignored (`.gitignore:13`) and exist only on the maintainer's machine, so
this check is deliberately scoped to what *is* verifiable without them:
whether a recorded result was produced by the comparison logic as it exists
right now. A mismatch means the pipeline changed since that day was last
validated, not that the day's transcription itself regressed — re-run
`./scripts/validate-transcription.sh <day-number>` (or `--appendix <slug>`)
locally and commit the refreshed result file.

Because `validate-transcription.sh` is itself hashed, a PR that edits it
invalidates every recorded result. Make the script edits final *first*, then
re-run the days: re-running and then touching the script again just puts the
refreshed files back out of date.

## Adding or refreshing a result

Nothing to do by hand: run the validator for the day or appendix in
question and commit whichever `results/*.yml` file it wrote or updated.
