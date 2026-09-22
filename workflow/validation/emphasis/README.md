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

## The alignment unit, and the profile

Both sides are read **per character** and cut into words at **whitespace
only**, and each word carries a *profile*: one `(bold, italic)` pair per letter
of its folded form. Punctuation folds away, so it holds no position and cannot
style anything.

This is what makes the comparison independent of markup, and
[#850](https://github.com/lddurbin/twelve_days_to_deming/issues/850) is why it
has to be. Neave emphasises part of a word — `outcome` bold inside the printed
word `outcomes,` — and pandoc hands `*two*-minute` over as an `Emph` and a
`Str` with nothing between them. The checker originally styled a word by the
majority of its letters and cut the site's side at every inline boundary, and
so the two streams disagreed about what a word *was*:

| | site tokens | PDF tokens |
|---|---:|---:|
| site **has** the emphasis (`*two*-minute`) | 2 | 1 |
| site **lost** it (plain `outcomes,`) | 1 | 1 |

One PDF token faced two site tokens wherever the site's markup was *correct*,
which is how correct markup came to punch a hole in the comparison. And a
partial emphasis was rounded to whichever half was longer, so a minority
italic — `*two*-minute`, 3 letters of 9 — was reported as upright, matched the
site's upright word, and never surfaced at all.

**Splitting the PDF word at the style boundary instead was built and measured,
and regresses.** It fixes the first row and breaks the second: `difflib` then
matches neither `outcome` nor `s` against the site's `outcomes`, and the word
leaves the comparison entirely. That trades the blind spot for its mirror
image. The measurement is on #850.

A profile leaves both token streams alone and makes a partial emphasis a
mismatch on the letters it actually covers.

## Partial findings

A finding whose disagreement covers only part of a word is flagged `partial`,
noted `partial-word`, and carries a `marked` field naming the letters:

```
p 57 12-rules-3-and-4-of-the-funnel  pdf=b   qmd=-   partial-word     | «outcome»s,
p 12 03-theory-of-knowledge          pdf=bi  qmd=-   partial-word     | PD«S»A
```

`pdf_style` and `qmd_style` describe **the letters that disagree**, not the
whole word — for a minority italic the word is mostly upright, and reporting
`pdf=-` on a `lost` run would contradict itself. `marked` equals the plain text
unless the finding is partial, so the marks appear only where they carry
information. Guillemets rather than brackets because 59 of the corpus's finding
texts contain a square bracket of Neave's own (`[law-]suits`, `[my italics]`).

Most partials are Neave pointing emphasis at a prefix or one element of a
compound — `«dis»incentives`, `«non»-existence`, `«left»-hand`, `«un»learn` —
and `PD«S»A`, where the bold-italic `S` is the whole point Deming was making
about *Study*. A few are the source's italic span stopping a glyph early
(`bus-shelte«r»!)`); they are reported honestly rather than suppressed, because
any rule short enough to remove them also removes `PD«S»A`.

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

## The first full run (2026-09-22, `emphasis_version` fd73b5c)

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

## After the profile refactor (2026-09-23, `emphasis_version` f1fb003)

Re-recorded when #850 made the alignment unit markup-independent. **Bold is a
record whose count moved.** `partial` counts the open findings that cover only
part of a word — the class that was invisible before.

| record | aligned | lost | added | swapped | partial |
|---|---:|---:|---:|---:|---:|
| `day-01` | 97% | 36 → 36 | 2 → 2 | 0 → 0 |  |
| `day-02` | 90% | 3 → 3 | 2 → 2 | 0 → 0 |  |
| `day-03` | 86% | 1 → 1 | 0 → **1** | 2 → 2 | 2 |
| `day-04` | 94% | 39 → **41** | 5 → 5 | 4 → 4 | 2 |
| `day-05` | 94% | 7 → 7 | 0 → 0 | 0 → 0 |  |
| `day-06` | 93% | 8 → 8 | 1 → 1 | 0 → 0 |  |
| `day-07` | 93% | 79 → **83** | 5 → 5 | 2 → 2 | 7 |
| `day-08` | 92% | 59 → **64** | 7 → 7 | 2 → 2 | 7 |
| `day-09` | 96% | 20 → 20 | 7 → 7 | 1 → 1 |  |
| `day-10` | 96% | 7 → 7 | 2 → 2 | 4 → 4 |  |
| `day-11` | 96% | 20 → **21** | 8 → 8 | 11 → **10** | 1 |
| `day-12` | 94% | 3 → 3 | 1 → 1 | 0 → 0 |  |
| `appendix-main` | 98% | 11 → 11 | 13 → 13 | 1 → 1 |  |
| `appendix-optional-extras` | 95% | 88 → **93** | 33 → **35** | 7 → 7 | 7 |
| `appendix-contributions-balaji-reddie` | 99% | 10 → 10 | 8 → 8 | 3 → 3 |  |
| `appendix-references` | 94% | 6 → 6 | 0 → 0 | 0 → 0 |  |
| `index` | 68% | 43 → 43 | 1 → 1 | 1 → 1 |  |
| `welcome` | 84% | 7 → **8** | 1 → 1 | 0 → 0 | 1 |
| **all 18** | **93%** | 447 → **465** | 96 → **99** | 38 → **37** | **27** |

Reading the table:

- **One finding disappeared corpus-wide, and 21 arrived.** The one that went is
  `day-11` p12 `Study`, swapped — an artefact of the old tokenisation. The site
  writes `Plan-Do-*Study*-Act`, which used to split into three site tokens
  against the PDF's one; it now joins, aligns, and agrees. The same page's real
  finding surfaced in its place: `PD«S»A`, where Neave sets the `S` bold-italic
  and the site has it plain.
- **Every one of the 21 is `partial`** — `«dis»incentives`, `«non»-existence`,
  `«un»learn`, `«A»’s`. That is the class #850 was opened for, and it is the
  check that the refactor did what it was for.
- **Five findings that were already reported now have the right extent**, and
  they are the same five the abandoned option-1 split removed: `day-03` p57
  `«outcome»s,`, `day-07` p30 `one-«seventieth»)` and `«right»-hand`, `day-08`
  p7 `«single»-sided` and p16 `dis«advantageous»`. The first is card `E3-F19`
  from #849, adjudicated by hand and kept deliberately
  ([`docs/deviations/2026-09-22-day-03-emphasis-differences-kept.md`](../../../docs/deviations/2026-09-22-day-03-emphasis-differences-kept.md),
  item 2). Splitting the PDF word stopped reporting all five; the profile
  reports them and says which letters they are about.
- **PDF tokenisation is byte-identical on all 18 records** — the site's side is
  the only one that changed, by joining what has no space between it.
- **Corpus alignment is flat** (92.98% → 92.97%, 22 words). It rises slightly on
  eleven records and falls on `appendix-optional-extras` by 39 words, where the
  site's `$\bar{X}$-chart` now correctly joins into one token but poppler
  splits the printed `X̄-chart` into two. That is a PDF-side tokenisation
  question, untouched here, and those words are `math`-explained anyway.
- #850's own estimate of **179 invisible losses was a generous upper bound**, as
  the abandoned option-1 measurement already suggested. The real number, with
  both sides agreeing on what a word is, is 27 open partial findings.

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
