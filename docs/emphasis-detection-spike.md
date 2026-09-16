# Can lost emphasis be detected mechanically? — spike outcome

**Issue:** [#825](https://github.com/lddurbin/twelve_days_to_deming/issues/825) (part of epic [#734](https://github.com/lddurbin/twelve_days_to_deming/issues/734))
**Status:** Recommendation. No production code ships from this document.
**Date:** 2026-09-16
**Script:** [`scripts/archive/emphasis-spike-825.py`](../scripts/archive/emphasis-spike-825.py) — throwaway, kept only so the numbers below can be reproduced
**Measured against:** `main` at `a12c977`, before PR #824's Day 5 fixes landed

---

## Answer

**Yes: build it.** Emphasis can be checked mechanically across the whole
corpus, with high precision and no per-PDF calibration. The first full run
also shows this is not a small problem to estimate by sampling but a large
one to fix: **about 480 runs (~700 words) of Neave's emphasis are missing
from the site**, across all 12 days. Day 3 accounts for 182 of those runs.

Wave 3 should **stop auditing for emphasis**, apart from the blind spots
listed [below](#blind-spots), and put its sampling budget into the defect
classes that genuinely need a human to read.

| Measure | Result |
|---|---|
| Precision, "lost" runs (seeded random sample of 40, checked on page images) | **40 / 40** real (95% Wilson lower bound 91%) |
| Recall against Wave 2's human fixes (tool run on each pre-fix commit) | **328 / 344** restored words flagged (95%) |
| Day 5: the two known emphasis losses (#823) | **2 / 2** caught, plus 7 more the 17-paragraph sample never reached |
| Runtime | ~1.5 s per day |

## Question 1 — calibration: not needed

The issue assumed font ids would have to be sorted into regular, bold and
italic using the `.qmd`'s existing emphasis. They don't.
`pdftohtml -xml` already wraps each run in `<b>`/`<i>`, taken from the
embedded font's own name and descriptor. `pdffonts` shows the real names
(`RRCLGY+HelveticaNeue-Italic`, `NPRFFU+Cambria-Bold`). The XML's
`family` attribute is just a shortened form, which is why it looked as though
there was nothing to go on.

Evidence that the tags can be trusted:

- **Each font id always gets the same tag** in 11 of the 12 Day PDFs (Day 10
  has 3 mixed ids out of 33). That holds for every face: Cambria, BookmanOldStyle,
  HelveticaNeue, Helvetica, Arial and Courier.
- **The tags agree with the site where the site has emphasis.** Of 9,303
  emphasised `.qmd` words that align to the PDF, 8,215 (88%) are tagged
  emphasised there too. Leaving out Days 3, 8 and 11, it is 97%. On Day 5 it
  is 482 of 482.
- **Where they disagree, the PDF tag was right every time we checked.**
  Day 3's 58% agreement looked like a calibration failure. On the page images
  it turned out to be the site's fault: italic spans shifted by a word or two
  (source: *opposite* direction by that same distance *from its current
  position*; site: opposite direction *by that same distance from its current
  position*).

One parsing trap for whoever builds this: a single `<text>` element can mix
styles (`<i>DemDim</i> Chapter 18 provides…`). Styles have to be read
per character, not per element.

## Question 2 — word-level alignment: yes, and simpler than expected

There's no need for `scripts/lib/paragraphs.py`. The script flattens each
side of a day into a word stream: the PDF from `pdftohtml`, and the `.qmd`
from the **pandoc JSON AST** (`quarto pandoc -t json`). Pandoc gives
`Strong`/`Emph`, headers, divs with their classes, links and tables without
any markdown parsing of our own. The script then aligns the two streams with
`difflib.SequenceMatcher`. Each report names the exact words and the PDF
page:

```
* p26 03-the-deadly-diseases pdf=i qmd=- | …reflect their appraisal system that is there to [help] the individual…
```

Across the 12 days, 92% of PDF words align (Day 3 is lowest at 83%). The
alignment is order-tolerant enough that page headers, figures and code
cells don't break it.

Two preprocessing details matter:

- `` ```{ojs} `` fences are not valid pandoc attribute syntax, so pandoc reads
  the code as prose. Rewrite them to plain `` ``` `` first.
- Raw inline HTML `<em>`/`<strong>` is used in places (Day 11) and has to be
  read as emphasis.

## Question 3 — false positives

Every disagreement falls into one of three kinds of run. The table shows what
separates real findings from site conventions.

### "Lost": emphasised in the PDF, plain on the site

887 raw runs. The following are site conventions and are filtered out
automatically:

| Filter | Why it isn't a defect |
|---|---|
| Inside a `Header` | Headings are bold by design |
| Inside a class whose CSS already sets bold or italic (`principle_callout`, `deming_quote`, `foreman-remark`, `activity_afterthought`, …) | The emphasis comes from the stylesheet |
| Table header cells | Rendered bold |
| Runs of 5+ words inside `neave_note` | Neave's long italic asides are carried by the `neave_note` class instead of italics |

**477 runs (697 words) are left, and the 40-run random sample was all real.**
Blue text in the PDF is *not* a convention for this class. "The crippling
disease **in America**" (#823) is both blue and bold, and it is a genuine loss.

### "Added": plain in the PDF, emphasised on the site

These are noisier, for reasons the checker needs to know about:

| Source | Treatment |
|---|---|
| `**POINT n.**` / `**DISEASE n.**` labels in the Activity 10A/10B/11A/11B checklists | Site convention, so filter it |
| Blue Deming quotations the site sets in italics or bold | Site convention, so filter it |
| Synthetic-oblique Comic Sans (the slanted blue dialogue on Days 2, 10 and 11) | A tool blind spot, see below. Poppler reports it as upright |
| Italic spans over-extended by a word (`*the difference*` where only *the* is italic in the source) | **Real** |

Sample of 20: 8 real, 10 convention, 2 blind spot. With the two convention
filters applied, **70 runs remain** (264 words; Day 3 has 156 of those words,
from its shifted spans).

### "Swapped": bold on one side, italic on the other

29 runs remain after filtering. Mostly real (`**If Yes**` where the source has
If *Yes*), but not sampled systematically.

## Question 4 — hits on real records

**Day 5** (audited in #823): 9 runs.

- Both known losses: `in America`, `same`.
- Seven new ones: `two`, `look`, `system` (×2), `help`, `appraisal`,
  `single-sided`. All seven are set in the same font id as the site's existing
  *Wrong!*, and `system`/`help`/`appraisal`/`single-sided` were confirmed on
  the page images.
- Zero "added" runs.

**Day 4** (Wave 2 adjudicated in #815): 39 "lost" runs remain on `main`.
Examples: `dissatisfied`/`satisfied`/`delighted` ×3, `capable`, `compete`,
`optimisation`. Wave 2's paragraph comparator couldn't see these.

**Recall on Wave 2's human fixes.** Emphasis that Wave 2 passes restored by
hand gives a ground truth that doesn't depend on the tool. Running the script
on each pass's *parent* commit (Days 1, 4–12, plus #823):

This is recall on the emphasis *people found*, not corpus-wide recall.
Emphasis that both Wave 2 and the tool missed can't appear in it, and is
likely to sit in the same places the tool is blind (see [below](#blind-spots)),
so the true figure is probably lower than 95%.

| | Words | Flagged | Missed |
|---|---|---|---|
| Emphasis a human restored | 344 | 328 | Day 11 underlines in Comic Sans (`big`, `natural`, `effort`, `rating`), a handful of Day 4 words (including heading text), one Day 8 word |
| Emphasis a human removed | 68 | 52 | Mostly one Day 10 sentence ("a system is not a theorem…") that *is* italic in the source — the fix restyled it rather than dropping emphasis, so not flagging it was correct |

### Corpus-wide candidates (after filters)

| Day | PDF words aligned | Lost runs (words) | Added runs (words) | Swapped runs |
|---|---|---|---|---|
| 1 | 97% | 33 (46) | 2 (2) | 0 |
| 2 | 89% | 30 (34) | 4 (20) | 2 |
| 3 | 83% | 182 (280) | 21 (156) | 3 |
| 4 | 94% | 39 (61) | 5 (6) | 4 |
| 5 | 94% | 9 (10) | 0 (0) | 0 |
| 6 | 93% | 8 (12) | 1 (1) | 0 |
| 7 | 93% | 74 (88) | 11 (26) | 2 |
| 8 | 92% | 59 (96) | 7 (11) | 2 |
| 9 | 96% | 20 (34) | 7 (12) | 1 |
| 10 | 96% | 5 (6) | 2 (4) | 4 |
| 11 | 96% | 15 (21) | 9 (18) | 11 |
| 12 | 94% | 3 (9) | 1 (8) | 0 |
| **Total** | **92%** | **477 (697)** | **70 (264)** | **29** |

## Blind spots

These are what a checker built on `pdftohtml` cannot see. They are also the
only emphasis questions left for Wave 3's human auditors:

1. **Synthetic oblique.** Some slanted text is an upright font skewed by the
   text matrix, not an italic font. This is mainly the blue Comic Sans
   dialogue on Days 2, 10 and 11. Poppler's XML doesn't expose the skew.
   PyMuPDF's per-character matrix would, but it isn't installed and wasn't
   tried.
2. **Underline.** Neave underlines words inside Comic Sans passages (Day 11
   `natural`, `big`). Underline is drawn as a line, not a font property, so it
   never reaches the text layer.
3. **Emphasis by colour alone.** Red `results` on Day 3 page 52, and blue
   Deming quotations generally. Colour is available (`fontspec color`), but
   what the site's equivalent should be is an editorial call, not a mechanical
   one.
4. **Unaligned text.** 8% of PDF words overall (17% on Day 3) don't align.
   That covers figure labels, tables rebuilt as images, reflowed lists and
   genuinely differing text. Emphasis in that text isn't checked.
5. **Appendices and the front matter.** Not run. The script only reads Day
   manifests, but the approach carries over unchanged.

## Recommendation

1. **Build the checker as a separate, sized piece of work.** Put it in
   `scripts/lib/`, alongside the paragraph comparator, reusing the manifest
   and content-dir conventions of `validate-transcription.sh`. It should cover
   the filters above as an explicit, documented allowlist (so a new CSS class
   that styles text is a one-line change) and all manifests, not just the 12
   days. Output should go to `results/`, with a clean-run count so drift is
   visible in CI.
2. **Treat the ~480 "lost" runs as a fix backlog, not an estimate.** Day 3
   alone has 182 runs. The precision
   measured here would support a mostly mechanical fix. But `AGENTS.md`
   requires the user to verify transcription, so the backlog should go through
   the existing generated-review-page flow (`/wave-2-pass` style), one day at
   a time, with Day 3 first. "Added" and "swapped" runs go on the same pages,
   marked lower-confidence.
3. **Change what the Wave 3 audit covers before drawing the next records.**
   Emphasis stops being a sampled defect class, except inside Comic Sans
   passages and underlined text (blind spots 1–2). The rubric in
   `workflow/validation/audits/README.md` should say so, so a future sampling
   bound isn't read as covering emphasis.
4. **Settle two conventions before a checker ships.** Bold vs
   italic (swapped) and colour-only emphasis each need a stated site
   convention first. Otherwise the checker ends up enforcing a rule nobody
   has decided.

## Reproducing

```bash
# per day: summary line, then every run; * marks runs no filter explains
python3 scripts/archive/emphasis-spike-825.py 5
python3 scripts/archive/emphasis-spike-825.py 5 --json /tmp/day-05.json

# against an older snapshot of the content (how the recall table was built)
git archive 9cd1a1a^ content/days/day-04 | tar -x -C /tmp/d4-old
CONTENT=/tmp/d4-old/content/days python3 scripts/archive/emphasis-spike-825.py 4
```

Requires `pdftohtml` (poppler) and `quarto` on `PATH`. The numbers above use
the script's own "unexplained" runs, plus the `neave_note` long-run filter
for lost runs and the POINT/DISEASE-label and blue-quote filters for
added/swapped runs, which were applied when tabulating.
