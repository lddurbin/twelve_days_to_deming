# Emphasis — what the source sets in bold or italic, and what the site does

`results/` records what the paragraph comparator found. It works on *stripped*
text, so emphasis is invisible to it by construction: a paragraph that drops
every italic Neave set still scores a perfect match. Wave 2 kept finding those
losses by eye — 29 on Day 9 alone, half of Day 5's audit findings — and spike
[#825](https://github.com/lddurbin/twelve_days_to_deming/issues/825) concluded
they are mechanically detectable after all. This directory holds that check's
records. See [#846](https://github.com/lddurbin/twelve_days_to_deming/issues/846)
and [`docs/emphasis-detection-spike.md`](../../../docs/emphasis-detection-spike.md).

One file per record, `day-NN.yml` or `<manifest>.yml`, named to match
`results/`. Written by `scripts/check-emphasis.py`, never by hand.

```sh
./scripts/check-emphasis.py 5                  # one day
./scripts/check-emphasis.py appendix-main      # one named manifest
./scripts/check-emphasis.py --all              # every record, ~45s
./scripts/check-emphasis.py 3 --json out.json  # findings, explained ones included
```

## How it works

| side | extraction | what it gives |
|---|---|---|
| PDF | `pdftohtml -xml` | each run already wrapped `<b>`/`<i>` from the embedded font's own descriptor |
| site | pandoc JSON AST (`quarto pandoc -t json`) | `Strong`/`Emph`, headers, divs with their classes, links, tables |

The two word streams are aligned with `difflib`, and every aligned word whose
emphasis disagrees is grouped into a run. The calibration problem #825 was
opened to solve turned out not to exist — poppler reads the style from the font
itself, so no per-PDF mapping of subset tags to weights is needed.

Three kinds of run, **counted separately**:

| kind | means | standing |
|---|---|---|
| `lost` | emphasised in the PDF, plain on the site | the fix backlog. Precision measured at 40/40 on a seeded random sample checked against page images (#825) |
| `added` | plain in the PDF, emphasised on the site | noisier; often the site over-extending a span by a word |
| `swapped` | bold on one side, italic on the other | its own class **because it has never been sampled systematically** and must not inflate `lost`, whose precision is measured |

## Colour is never emphasis

Decided in #846. Neave's red and blue text is read (it is available as
`fontspec color`) but it may only ever *explain away* an `added` run — the blue
Deming quotations the site sets in italics via `.deming_quote`. It never
creates a finding, and it never explains a `lost` one: #823's `in America` is
both blue and bold and is a genuine loss.

**Colour-only emphasis stays out of scope**, because what the site's equivalent
of one of Neave's colours should be is an editorial question, and the site has
its own conventions (`deming_blue`, `text-highlight-red`) that a mechanical
rule would fight. It is one of the blind spots the human auditor still covers —
see [`../audits/README.md`](../audits/README.md).

## The convention allowlist

A disagreement is only a defect if the site is not *already* rendering that
word the way Neave set it. These are the ways it does so with no markup in the
`.qmd`, and a run explained by one of them is reported as explained and kept
out of the counts. The list lives in `STYLED_CLASSES` and `explain()` in
[`scripts/lib/emphasis.py`](../../../scripts/lib/emphasis.py).

| reason | applies to | why it is not a defect |
|---|---|---|
| `css:<class>` | all | the class already sets `font-weight` or `font-style` in `main.css` |
| `header` | `lost`, `swapped` | headings are bold by design |
| `table-header` | `lost`, `swapped` | `th` cells render bold |
| `neave-note-aside` | `lost`, `added` | Neave's long italic asides are carried by the `neave_note` class rather than by italics. Only for runs of 5+ words, so short emphasis *inside* an aside still reports |
| `math` | all | MathJax italicises `$n$` without the `.qmd` saying so, and the source sets the same variable in an italic font. **The largest single class in the corpus** — 285 of Optional Extras' 379 raw `lost` runs |
| `checklist-label` | `added` | the site's own `**POINT 7.**` / `**DISEASE 3.**` scaffolding in the Activity 10A/10B/11A/11B lists |
| `deming-quote-colour` | `added` | Deming's quotations: blue and upright in the source, italic on the site |
| `page-furniture` | all | a run of nothing but page numbers |

**Adding a class to `STYLED_CLASSES` is a one-line change, and that is
deliberate** — a new CSS rule that styles text would otherwise turn every word
it covers into a false `lost` finding. Check first that it really does set
`font-weight` or `font-style`: `tests/test_emphasis.py` asserts that every
listed class does, because an unjustified entry silently suppresses real
findings, which is the more expensive mistake. `neave_note` is deliberately
*not* in the list — it styles the block, not the words, which is why it needs
the separate long-run rule.

## The first full run (2026-09-22, `emphasis_version` 19a930c)

Six of these eighteen records had never been run at all: the spike covered only
the twelve days.

| record | aligned | runs | explained | lost (words) | added | swapped |
|---|---:|---:|---:|---:|---:|---:|
| `day-01` | 97% | 85 | 47 | **36** (51) | 2 | 0 |
| `day-02` | 90% | 26 | 21 | **3** (22) | 2 | 0 |
| `day-03` | 86% | 275 | 70 | **183** (321) | 18 | 4 |
| `day-04` | 94% | 88 | 40 | **39** (61) | 5 | 4 |
| `day-05` | 94% | 39 | 32 | **7** (7) | 0 | 0 |
| `day-06` | 93% | 49 | 40 | **8** (12) | 1 | 0 |
| `day-07` | 93% | 126 | 40 | **79** (231) | 5 | 2 |
| `day-08` | 92% | 90 | 22 | **59** (96) | 7 | 2 |
| `day-09` | 96% | 60 | 32 | **20** (34) | 7 | 1 |
| `day-10` | 96% | 99 | 86 | **7** (10) | 2 | 4 |
| `day-11` | 96% | 193 | 154 | **20** (31) | 8 | 11 |
| `day-12` | 94% | 43 | 39 | **3** (9) | 1 | 0 |
| `appendix-main` | 98% | 155 | 130 | **11** (18) | 13 | 1 |
| `appendix-optional-extras` | 95% | 481 | 353 | **88** (142) | 33 | 7 |
| `appendix-contributions-balaji-reddie` | 99% | 68 | 47 | **10** (13) | 8 | 3 |
| `appendix-references` | 94% | 11 | 5 | **6** (9) | 0 | 0 |
| `index` | 68% | 61 | 16 | **43** (55) | 1 | 1 |
| `welcome` | 84% | 16 | 8 | **7** (20) | 1 | 0 |
| **all 18** | **93%** | **1965** | **1182** | **629** (1142) | **114** | **40** |

Reading the table:

- **`index`'s 68% alignment is the lowest, and its 43 findings should be read
  with that in mind.** It transcribes `A.PLEASE.START.HERE`, whose PDF carries
  11,164 words against the page's 7,994 — the site does not reproduce all of
  it, by design (#802). Low alignment means less was checked, not that more
  was wrong.
- **Day 3's 183 is the largest day backlog** and was the spike's finding too
  (182). Its 86% alignment is also the lowest of the twelve.
- **Day 2's 3 is low because its Wave 2 pass (#822) restored 25 emphasis runs
  by hand.** Day 5's 7 is the spike's 9 less the two PR #824 fixed. Those two
  agreements are the closest thing to a recall check this tool has against work
  done without it.
- `appendix-optional-extras` is 88 rather than the 379 a naive run reports,
  because it is the mathematics appendix and 285 of those were `math`. That is
  the same root cause #744's triage found dominating its near-certain band on
  the similarity side (93 of 221).

## Staleness

`scripts/check-validation-staleness.sh` checks this directory alongside
`results/`, each against its own version: `emphasis_version` here,
`scorer_version` there. It needs no PDFs, which is why it can run in CI at all
(they are gitignored and local-only — see [#734](https://github.com/lddurbin/twelve_days_to_deming/issues/734)).

The two versions are kept apart deliberately. Neither pipeline can change what
the other reports, so folding them into one would mean every emphasis-checker
edit restaling all eighteen paragraph records — and under `main`'s
`strict: true` protection with no merge queue, that staleness is a real
merge-ordering cost, not a compute one. `tests/test_scorer_version.py` asserts
the two file lists never overlap, so the coupling cannot come back by the back
door.

## What this does not cover

The blind spots are #825's, unchanged, and they are what is left for a human
auditor:

1. **Synthetic oblique** — slanted text that is an upright font skewed by the
   text matrix rather than an italic font. Mainly the blue Comic Sans dialogue
   on Days 2, 10 and 11. Poppler's XML does not expose the skew.
2. **Underline** — drawn as a line, not a font property, so it never reaches
   the text layer at all. Neave underlines words inside Comic Sans passages
   (Day 11 `natural`, `big`).
3. **Emphasis by colour alone** — see above.
4. **Unaligned text** — 7% of PDF words corpus-wide, 14% on Day 3 and 32% on
   `index`. Figure labels, tables rebuilt as images, reflowed lists and
   genuinely differing text. Emphasis in it is not checked.

Figures and tables carried as images are out of scope entirely, and owned by
spike [#725](https://github.com/lddurbin/twelve_days_to_deming/issues/725).

## The fix backlog is not this tool's job

629 `lost` runs is a backlog, not a result. `AGENTS.md` requires the user to
verify transcription, so it goes through the generated review-page flow
(`/wave-2-pass` shape), one record at a time with Day 3 first — issues created
lazily, the way Wave 2's were. `added` and `swapped` runs go on the same pages,
marked lower-confidence.
