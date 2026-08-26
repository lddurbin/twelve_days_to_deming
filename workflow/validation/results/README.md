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

Day 4's record, as written on 2026-08-26 — a real file rather than an
invented one, so the magnitudes are the ones a reader will actually meet:

```yaml
day: 4                        # or `appendix: <slug>` for appendix runs
validated_at: 2026-08-26      # local date the run completed
source_pdf: G.Day.4.09Jan20.pdf
source_sha256: <sha-256 of the source PDF>   # catches a silent re-export
scorer_version: <content hash of the comparison pipeline — see below>
thresholds:
  missing: 0.4
  altered: 0.98
  unsourced: 0.25
  reference: 0.85
counts:
  pdf_paragraphs: 127
  qmd_paragraphs: 127
  matched_cleanly: 72
  altered: 41
  flagged_sentences: 78
  near_certain: 8
  missing: 14
  unsourced: 4
  unsourced_sentences: 4
  reference_mismatches: 2
  short_checked: 52
  short_matched: 40
  short_unmatched: 5
  short_unjudged: 7
blocks:                       # where every block read ended up — see below
  pdf:
    total: 229                # blocks read, before any filter or rejoining
    unreadable: 35            # rejected as page furniture
    rejoined: 15              # merged into the block before them
    short: 52                 # readable, still under the 40-byte floor
    compared: 127             # what similarity scoring actually saw
  qmd:
    total: 178
    unreadable: 0
    rejoined: 17
    short: 34
    compared: 127
```

`reference_mismatches` ([#738](https://github.com/lddurbin/twelve_days_to_deming/issues/738))
is deliberately **not** part of the missing/altered/matched arithmetic, and
overlaps all three. It counts sentence pairs, scoring at or above the
`reference` threshold, whose page/day/chapter numbers or bare numerals
disagree — most of which are *also* clean matches, because one wrong digit in
a fifty-word sentence scores 0.98 and classifies as faithful. Track it as its
own series: it moving is a different event from `near_certain` moving.

The four `short_*` counts ([#742](https://github.com/lddurbin/twelve_days_to_deming/issues/742))
are the other population — the blocks that never reach similarity scoring at
all, because they fall under `paragraphs.py`'s 40-byte floor. `short_checked`
is all of them; the other three partition it exactly, so
`matched + unmatched + unjudged == checked` every time. `short_matched` means
the wording was found in the QMD — as a heading, a short paragraph, a chapter
title, or verbatim inside a longer paragraph — and nothing more than that: at
these lengths a similarity score cannot distinguish a substituted word from a
rewording, so this pass reports presence and never fidelity. `short_unjudged`
is residue set aside with a stated reason (a table row `pdftotext` read twice
across two columns, a contents-page entry, a fragment of under two words), and
`short_unmatched` is what is left for a human: 86 lines corpus-wide when it
was added, 63 distinct wordings of them. Read it beside `short_unjudged` — a
day whose unmatched count jumps because a table stopped being recognised has
not lost any content.

`blocks` ([#743](https://github.com/lddurbin/twelve_days_to_deming/issues/743))
is the residue accounting: what a run did **not** check, stated beside what it
did. Every count above describes content that entered one comparison or
another, so a reader of Day 3's `pdf_paragraphs: 288` had no way to know that
592 blocks were read to arrive at it, nor that 181 of them were discarded
unread. `blocks` closes that gap for both sides, and its five numbers
partition exactly:

```
total == unreadable + rejoined + short + compared
```

- **`total`** is the count *before* assembly — blank-line-delimited blocks,
  not paragraphs. Since #741 that distinction is real rather than pedantic:
  `join_continuations()` merges blocks the text itself says are one passage,
  so "how many blocks were read" and "how many units were compared" are
  separated by more than the two filters.
- **`unreadable`** is what the 40%-letter filter rejected — `pdftotext`'s
  rendering of this course's symbol-font page headers, 760 blocks corpus-wide.
  The validator prints this as "Unreadable blocks (furniture)". It is residue
  in the strict sense: unmatchable by construction, and nothing downstream
  looks at it. Watch it for *movement*, not for its value — a day whose
  furniture count halves has had its extraction change underneath it.
- **`rejoined`** is the benign one. Those blocks are not missing from the
  comparison; they are *inside* the paragraph before them. It is the count
  #741 made necessary and the reason `pdf_paragraphs` fell corpus-wide that
  run without anything going unchecked.
- **`short`** is the population the four `short_*` counts above describe, and
  the two are measured independently — `blocks.pdf.short` from
  `paragraphs.sift()`, `short_checked` from the pass that consumes it. They
  agree everywhere in the current corpus. They can only diverge if a block
  survives the readability filter and still normalises to no words at all, in
  which case the difference is the finding.
- **`compared`** equals `counts.pdf_paragraphs` / `counts.qmd_paragraphs` by
  construction; the validator refuses to write a result where it doesn't,
  since a disagreement would mean the paragraph stream and the accounting had
  stopped describing the same run.

Read the QMD side for a different question than the PDF side. There, `short`
and `unreadable` are content of the *site* that the reverse pass (`unsourced`)
never examined — the QMD's own filter residue — so a large `qmd.short` is a
statement about the limits of fabrication detection, not about the source.
`qmd.unreadable` is near-zero by nature (13 blocks across the twelve days, all
of them accounted for: Day 2's Red Beads data rows, Day 3's LaTeX display
maths and its two lookup strips, Day 7's five `...` continuation lines) —
the symbol-font furniture the filter exists for is a `pdftotext` artifact, and
the site has none of it. A day where that number climbs has had something
change in `qmd_strip.py`, not in its content.

Corpus-wide, as of the run that added this section: the PDF side read 3,526
blocks and compared 1,992 of them — 760 furniture, 198 rejoined into the block
before them, 576 under the floor. The QMD side read 2,779 and compared 2,110.

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
currently `scripts/lib/paragraph_similarity.py`, `scripts/lib/paragraphs.py`,
`scripts/lib/pdf_callouts.py`, `scripts/lib/qmd_strip.py`,
`scripts/lib/short_content.py` and `scripts/validate-transcription.sh`. Until
[#737](https://github.com/lddurbin/twelve_days_to_deming/issues/737) it hashed
the scorer alone, which understated the pipeline: PDF text extraction, QMD
stripping, and the paragraph-length filters all lived in the shell script, and
a behaviour-changing edit to any of them produced results the staleness check
happily called fresh. `qmd_strip.py` joined the list in
[#739](https://github.com/lddurbin/twelve_days_to_deming/issues/739), when
markup stripping moved out of that script into tested Python, and
`paragraphs.py` in
[#741](https://github.com/lddurbin/twelve_days_to_deming/issues/741), when
paragraph assembly did, `short_content.py` in
[#742](https://github.com/lddurbin/twelve_days_to_deming/issues/742), and
`pdf_callouts.py` in
[#755](https://github.com/lddurbin/twelve_days_to_deming/issues/755), when the
PDF side gained a footnote-callout rule to match the one the QMD side already
had — the widening was designed so that each move cost one line here. A file belongs on
that list whether it changes what gets *flagged* or only what gets *reported*:
both change what a recorded result says.

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

`thresholds.reference` records `REFERENCE_PAIR_THRESHOLD`, which is 0.85
rather than the 0.90 the other near-certain machinery uses. The enriched
cross-reference links write a descriptor into the link text ("page 18, the
guidance for the Second Project"), which costs 12-20% similarity on its own
and lands those pairs at 0.86-0.89 — a 0.90 floor would have excluded the
exact population the check exists for. The measured findings-per-floor table
is in `scripts/lib/paragraph_similarity.py` beside the constant.

`counts.pdf_paragraphs` can move without the source PDF changing, and did in
#739: stripping the PDF's `[WB NN]` workbook citations shortens the paragraph
that carried one, and ten short table-of-contents lines fell under
`MIN_PARA_LEN` (40 bytes) as a result and left the checked corpus. Eight
were contents-page entries. Two were real, if slight: Day 3's "So off you go
to Stage 6 on page 44." and "(Move on to the table on page 54.)", both now
36 and 34 characters. That is the honest cost of removing 176 citations'
worth of guaranteed-unmatched text.

#742 revisited that floor and left it where it is. It is a floor on
*similarity scoring*, which is the one thing a four-word string cannot
support, so lowering it would buy coverage in the currency of noise. What
changed instead is that everything below it is now accounted for by the
short-content pass rather than discarded — including those two Day 3
sentences, which the pass reports as absent from the QMD by name.

It moved again in #741, downward on both sides and for a different reason:
paragraph assembly now rejoins blocks that a blank line split but that the
text says are one passage — a sentence broken across a PDF page boundary, a
blockquote separated from the lead-in that introduces it, a lettered list
rendered one item per block. 152 PDF blocks and 144 QMD blocks stopped being
counted as paragraphs of their own because they are part of the paragraph
before them. Read `pdf_paragraphs` as "units compared", not "units in the
book"; the clean-match *rate* is the comparable number across that change,
and it went from 64% to 67% while the flagged-sentence count fell from 987 to
879.

`counts.matched_cleanly` can rise without the transcription changing, and did
in #761: the QMD's sub-floor blocks became match candidates, gated at the
altered threshold so they compete only where they would be classified clean
anyway. The site sets its short cross-reference pointers as standalone
paragraphs — `*(See [Appendix page 24](...).)*` strips to 23 bytes — so
`MIN_PARA_LEN` kept them out of the pool entirely, while the PDF's copy of the
same words sat in a full paragraph and was duly scored against a pool the
counterpart had been filtered out of. Day 5 carried eleven of these and lost
37% of its flag list to the fix; corpus-wide it is 25 more paragraphs matching
cleanly, 42 fewer flagged sentences and 4 fewer "missing" — the last of those
being paragraphs that were reported absent from the site while being present
on it. `pdf_paragraphs` is unchanged on all fifteen records, which is the
check that matters: the scored population is the same one, so every delta is a
suppressed false positive rather than a change of subject.

#760 rode along in the same PR, being the other scorer change waiting on a
window with no content pass open. It removes a chart tick numeral that fell
between the halves of a hyphenated line wrap, which defeated #740's joiner. Its
measured effect is much smaller than #744's triage implied — 7 flagged
sentences corpus-wide, 5 of them near-certain — because that triage counted
flags whose sentences carry *other* `-layout` damage as well, and removing the
numeral alone does not clear those.

`counts.missing` can rise while everything around it improves, and did in
#740: joining a hyphenated word into a single token shortens *both* sides'
token streams, so a paragraph already scoring near the 40% missing floor —
never a credible match to begin with — can slip under it. Two Day 3
paragraphs did (41% and 40%, both PDF layout debris the site restructured),
against a corpus-wide 27 more paragraphs matching cleanly and 32 fewer
near-certain flags. Read a small `missing` rise beside `matched_cleanly` in
the same run before treating it as a regression.

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
