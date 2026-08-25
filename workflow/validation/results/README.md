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
scorer_version: <git blob hash of scripts/lib/paragraph_similarity.py>
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

`scorer_version` is `git hash-object scripts/lib/paragraph_similarity.py`,
not a commit SHA — a content hash so an uncommitted local edit to the
scorer is caught too, not just a merged one. It is a **content identity
check, not a timestamp**: it tells you whether a result was produced by
today's scoring logic, not how long ago that was.

There is deliberately no pass/fail verdict field. With 446 known near-certain
findings outstanding across the corpus as of #719's baseline, every day would
read "fail" — a permanently red signal nobody reads. Record the numbers and
let a diff across runs be the signal instead.

## Staleness

[`scripts/check-validation-staleness.sh`](../../../scripts/check-validation-staleness.sh),
run in CI by
[`.github/workflows/validation-staleness.yml`](../../../.github/workflows/validation-staleness.yml),
compares each file's `scorer_version` against the current
`scripts/lib/paragraph_similarity.py`. It needs no PDFs — the source PDFs
are gitignored (`.gitignore:13`) and exist only on the maintainer's machine,
so this check is deliberately scoped to what *is* verifiable without them:
whether a recorded result was produced by the scoring logic as it exists
right now. A mismatch means the scorer changed since that day was last
validated, not that the day's transcription itself regressed — re-run
`./scripts/validate-transcription.sh <day-number>` (or `--appendix <slug>`)
locally and commit the refreshed result file.

## Adding or refreshing a result

Nothing to do by hand: run the validator for the day or appendix in
question and commit whichever `results/*.yml` file it wrote or updated.
