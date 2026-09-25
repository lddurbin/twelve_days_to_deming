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

## After excluding undecodable text (2026-09-23, `emphasis_version` e3f220e)

Re-recorded when [#852](https://github.com/lddurbin/twelve_days_to_deming/issues/852)
stopped text poppler cannot decode from entering the PDF stream. Some subset
fonts come out as a substitution cipher — `1"20,+*3$4552".*"6*3$…` is Day 7's
running banner — and until this run those tokens sat in the stream as words
that aligned against nothing. `scripts/lib/undecodable_fonts.py` identifies the
fonts; `pdf_words()` drops their characters. Both columns below are on the same
content, old checker against new, so the only thing that moved is the
extraction. **Bold is a record whose count moved.**

| record | PDF words | aligned | lost | added | swapped |
|---|---:|---:|---:|---:|---:|
| `day-01` | 23781 → 23685 | 97% | 36 | 2 | 0 |
| `day-02` | 14774 → 14689 | 90% → 91% | 3 | 2 | 0 |
| `day-03` | 25766 → 25519 | 86% | 1 | 1 | 2 |
| `day-04` | 9689 → 9598 | 94% → 95% | 41 | 5 | 4 |
| `day-05` | 4972 → 4931 | 94% → 95% | 7 | 0 | 0 |
| `day-06` | 11886 → 11769 | 93% → 94% | 8 → **10** | 1 | 0 |
| `day-07` | 15384 → 14928 | 93% → 96% | 83 | 5 | 2 |
| `day-08` | 9282 → 9238 | 92% → 93% | 64 → **66** | 7 | 2 |
| `day-09` | 14798 → 14720 | 96% → 97% | 20 | 7 | 1 |
| `day-10` | 8349 → 8259 | 96% → 97% | 7 | 2 | 4 |
| `day-11` | 8538 → 8490 | 96% → 97% | 21 | 8 | 10 |
| `day-12` | 9783 → 9661 | 94% → 95% | 3 | 1 | 0 |
| `appendix-main` | 24745 → 24697 | 98% | 11 | 13 | 1 |
| `appendix-optional-extras` | 45801 → 45586 | 95% | 93 | 35 | 7 |
| `appendix-contributions-balaji-reddie` | 22350 → 22295 | 99% | 10 → **9** | 8 | 3 |
| `appendix-references` | 1054 → 1049 | 94% | 6 | 0 | 0 |
| `index` | 11164 → 11140 | 68% → 69% | 43 | 1 | 1 |
| `welcome` | 4482 | 84% | 8 | 1 | 0 |
| **all 18** | 266598 → **264736** | 92.97% → **93.62%** | 465 → **468** | 99 | 37 |

Reading the table:

- **1,862 PDF "words" left the stream, and four more words align.** The
  alignment rise is almost entirely the denominator shrinking — ciphertext that
  was being counted as checked-and-different is now counted as not read. That
  is the point of the change: the percentage now describes text the checker
  could actually see.
- **Day 7 moves most** (93% → 96%), because it carries the most undecodable
  text: its running banner on every page, and a whole page of Hansard
  transcript (p21, printed page 17) — see *What this does not cover* below.
- **The three new `lost` runs are alignment shifts, not new defects.** With the
  ciphertext gone, difflib pairs the PDF's bold table labels with the site's
  captions at slightly different points: `day-06` p19 `BEFORE`/`AFTER`, and
  `day-08` pp19–21 `TABLE THREE`/`FOUR`/`FIVE` arrive while `TABLE TWO` (p18)
  leaves. `appendix-contributions-balaji-reddie` p19 `Prelude C: Understanding
  Learning.` drops out to unaligned. All six sit in the heading and caption
  class the adjudication passes already handle.

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
the two file lists share only what is named in its `SHARED_FILES`, so the
coupling cannot come back by the back door. The one shared file is
`scripts/lib/undecodable_fonts.py` (#852), which decides what text *both*
pipelines read — leaving it out of either list would let that directory's
records call themselves fresh after a behaviour change.

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
4. **Unaligned text** — 6% of PDF words corpus-wide, 14% on Day 3 and 31% on
   `index`. Figure labels, tables rebuilt as images, reflowed lists and
   genuinely differing text. Emphasis in it is not checked.
5. **Undecodable text** — set in subset fonts poppler cannot map back to
   Unicode, and excluded from the stream since #852 rather than read as
   words. Mostly running banners and footers, but not all of it: see the
   audits README for the pages where it is body prose, including Day 7's
   Hansard page, whose italic speaker names no tool can see.

Figures and tables carried as images are out of scope entirely, and owned by
spike [#725](https://github.com/lddurbin/twelve_days_to_deming/issues/725).

## The residual after epic #848 (2026-09-25, `emphasis_version` e3f220e)

[#848](https://github.com/lddurbin/twelve_days_to_deming/issues/848) worked
the backlog one record or batch at a time, each through a decision record in
[`../adjudications/`](../adjudications/) (`<record>-emphasis.json`) checked
against the source page images. Every record was re-recorded in the same PR as
its pass, and a full `--all` run on 2026-09-25 reproduced all eighteen
committed files with no change except one `checked_at` date.

**This is what fidelity statements should cite for emphasis.** Of the 629 lost
runs the first run found, 54 remain open in the records, with 15 added and
3 swapped. **None of the 72 is a defect waiting to be fixed.** Every one was
read against the page image and left as it is, for one of these reasons:

| class | lost | added | swapped | what it is | cards |
|---|---:|---:|---:|---|---|
| comparator artifact | 27 | 1 | 0 | text the PDF sets in bold (table captions, labels inside figures) aligned against unrelated site text, usually an image's caption or its *Describe this table* text | `AP-C03`–`C10`, `E1-C01`, `E1-C06`, `E6-C01`–`C02`, `E7-C01`, `E8-C01`–`C09`, `E8-C11`, `E12-C01`–`C02`, `WL-C01`–`C02`, and Day 8 p23 `of` (below) |
| site convention | 12 | 10 | 1 | `neave_note` asides are set upright, so titles inside them are italicised to stay distinct; workbook references are `[*WB* nnn]` site-wide; Deming's blue text is italic | `E1-C03`–`C05`, `E3-C02`, `E10-C01`–`C04`, `E11-C01`–`C14`, `E11-C16` |
| site-authored or adapted text | 10 | 2 | 0 | the site's own glossary, image descriptions, and the web-adapted printing and page-reference guidance in `index` (#802) | `AP-C01`–`C02`, `E2-C01`, `E4-C01`–`C02`, `E11-C15`, `E12-C03`, `I-C01`–`C05` |
| styled with inline HTML | 4 | 0 | 0 | bold or italic set with a `style` attribute, which the checker's pandoc reading cannot see. Rendered, it matches the source | `E2-C02`–`C03`, `E8-C10`, `E12-C04` |
| source typesetting | 0 | 2 | 2 | slips or glyph quirks in Neave's own setting: an upright `of` in a bold-italic line, an upright superscript, a script face poppler cannot read as italic, an italic span stopping one glyph early | `E1-C02`, `E3-C01`, `AP-C11`, and Day 3 p5 `bus-shelte«r»!)` (see *Partial findings* above) |
| kept deliberately | 1 | 0 | 0 | Day 3's bold `«outcome»s`, a distinction the site's colour-free funnel activity does not carry | `E3-F19`, [deviation entry](../../../docs/deviations/2026-09-22-day-03-emphasis-differences-kept.md) |
| **total** | **54** | **15** | **3** | | |

Two runs have no card of their own. Day 8's `of` on PDF p23 is part of
the bold header *Effects of Options*, set inside a table that is an image on
the site. It is the same artifact as `E8-C04`, which cleared `Options` beside
it, but the pass's run numbering folded the `of` into edit card `E8-27` on p22.
Day 3's `bus-shelter` partial was already explained under *Partial findings*
before the pass began.

### What this does and does not verify

It verifies that, **wherever the checker can align the site's words with the
PDF's**, the site carries Neave's bold and italic or has a recorded reason
not to. That is 93.6% of the source's decodable words (247,904 of 264,736).

It says nothing about the blind spots under *What this does not cover*, and
the residual touches three of them:

- **Synthetic oblique and underline (1, 2).** `AP-C11` is the Foreman's
  script-face remarks in the main Appendix. Its slant comes from the face, and
  its underline never reaches the text layer. The page image shows both, and
  the site matches it, but that was checked by eye, not by the tool. Elsewhere
  the Comic Sans dialogue on Days 2, 10 and 11 is still unchecked by the tool.
- **Colour (3).** `E3-F19` is the one run where bold carries a distinction the
  site's colour-free rendering drops. Colour-only emphasis is out of scope.
- **Unaligned and undecodable text (4, 5).** 6.4% of the source's decodable
  words did not align, including 14% of Day 3 and 31% of `index`, whose
  unaligned text is mostly source material the site does not reproduce
  (#802). Emphasis in that text has not been compared.

### The course title

[#813](https://github.com/lddurbin/twelve_days_to_deming/issues/813) was settled
alongside the residual. Neave italicises *12 Days to Deming* in running text
(for example `index` printed p5, and the Balaji Reddie contributions), and the
site now does too everywhere outside metadata: the site's own pages were
normalised, and *The Deming Dimension* heading on Day 1 page 11 now carries the
italic its source heading has. Two occurrences stay as they are. The Balaji
Reddie introduction's italic line quotes the title in quotation marks, as its
source does. Day 8's `*Day 8 of 12 Days to Deming*` line is a running page header
that was transcribed into the prose by mistake, and is left for its own fix. `pagetitle` and
`description` metadata carries the title plain, as #813 required, to leave
#497's hand-written metadata alone.
