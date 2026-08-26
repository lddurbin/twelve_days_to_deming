---
name: wave-2-pass
description: Run one Wave 2 content pass of epic #734 — adjudicate a day's or appendix's full transcription flag list against Neave's source PDF, publish the review page for Lee's sign-off, then apply only what he accepts
---

One pass = one day or appendix, one issue, one PR. Take the argument as the pass
(`5`, `day-05`, `appendix-main`). If none is given, pick the next one in the
agreed order: Day 5 → 6 → 7, then ascending load, appendices last with Optional
Extras genuinely last.

## Three rules that are not yours to relax

1. **Lee decides every word-for-word claim.** `AGENTS.md`: *"User will always
   verify transcription accuracy."* You adjudicate and propose; you do not edit
   the `.qmd` files until his decisions come back. This is the whole shape of
   the wave — see #734's *Autonomy differs by wave*.
2. **Open the source page images, not just `pdftotext`.** The extractor discards
   every italic and bold, renders some fonts as garbage, and cannot show you
   content that was never transcribed at all. #735 was scoped from flags and
   named 2 defects; reading one page image during PR #747 found 4 more in the
   same paragraph.
3. **This runs only on Lee's machine.** `12-Days-to-Deming/` is gitignored, so
   the PDFs exist nowhere else. Cloud sessions and `isolation: "worktree"`
   subagents both fail — a worktree is a different path. Never try to
   parallelise a pass off-machine.

## Steps

### 1. Get the flag list

```
./scripts/validate-transcription.sh <n>            # ~0.5s; --appendix <slug> for an appendix
./scripts/check-validation-staleness.sh            # must be green before you trust the report
```

Read the whole report, not the ≥90% band. #734 exists because that cutoff was a
workaround for comparator noise, not a property of where defects live — a
hand-sample of Day 9's 70–89% band found real defects at the same density.
Read the **Reference mismatches** section first: it is the shortest, and it is
the one similarity scoring cannot see for you.

### 2. Adjudicate every flag

Extract the source and split it per page so you can cite precisely:

```
pdftotext -layout 12-Days-to-Deming/PDFs/<PREFIX>.pdf out.txt
```

Then, for every paragraph you would change, open its page image. They are
2550×3300, too large to read directly — crop and resize into your scratchpad
first:

```
magick 12-Days-to-Deming/PNGs/<PREFIX>_page_0NN.png -crop 2550x1900+0+0 -resize 1400x -strip out.png
```

Note the offset between PDF file page and printed page (it is fixed per day, and
the footer gives it to you) — findings cite both, and it goes in the record as
`page_offset`.

Every flag lands in exactly one bucket: **fix**, **emphasis** (invisible to the
comparator by construction), **confirmed non-defect**, or **out of scope for a
per-day pass**. "Confirmed non-defect" needs its reason stated, not asserted —
comparator artifact, front matter, a documented site-wide convention. Check a
suspected convention against the corpus before calling it one (`grep -r` over
`content/`), because a single-instance "convention" is a defect.

Watch for defects *inside* a flagged sentence that the flag itself is not
about — Day 5's `Dem-Dim` hyphen was found that way. And do not size a
false-positive class by substring presence; it overestimates by ~3x.

### 3. Write the record and publish the page

Write `workflow/validation/adjudications/<pass>.json` — format in that
directory's README. Give every finding a `pdf_page`, and a `page_pos` where two
share a page: the page opens in the source's reading order, so a finding without
a position sorts by accident. The build cross-checks `pdf_page` against the
`page` string and refuses a record where they disagree. Then:

```
python3 scripts/build-adjudication-page.py workflow/validation/adjudications/<pass>.json
```

Publish the built HTML as an Artifact (favicon 📖🔍, `capabilities: {"downloads": true}`),
and give Lee the link. Do not write a findings table into the terminal instead —
the page is the deliverable of this step, and it is what makes 20-plus
word-for-word judgements reviewable.

**Then stop.** Nothing is edited while decisions are outstanding.

### 4. Apply what came back

Merge the exported decisions into the record's `decision` / `decision_note`
fields and set `decided_at`, so the record is complete. Then apply **only** the
accepted findings — a declined one stays exactly as it is, and its record entry
is the evidence it was considered.

### 5. Close the pass

- Re-run the validator and commit the refreshed `workflow/validation/results/<pass>.yml`
  **in the same PR** — the staleness check couples them.
- Add a `docs/changesets/` entry. Content fixes are user-facing.
- Add a `docs/deviations/` entry for any material departure from Neave's text.
- `/ship-it`, then `/pr-feedback`, then `/merge-pr`.
- Tick the pass off in #734's *Children* list and update its progress table.

## Two things that are cheap, and one that isn't

Validation is ~0.5s per day, so re-running is free — never plan around it.

**Wave 2 is not serial**, unlike Wave 1: `compute_scorer_version()` hashes the
six files in `SCORER_VERSION_FILES` and no content at all, so a pass that edits
only `.qmd` files and its own results file restales nothing. Two passes can be
in flight.

The corollary binds the other way: **any edit to those six files restales all
fifteen records and invalidates the report an open pass is being adjudicated
against.** Comments and type annotations count — the hash covers file contents,
not behaviour. So a scorer change is only cheap in a window with no pass open.
