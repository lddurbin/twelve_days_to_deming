# Day Conversion Guide

Repeatable workflow for converting each day's PDF source materials into interactive Quarto chapters.

**Source PDFs**: `12-Days-to-Deming/PDFs/` (one PDF per day)
**Source PNGs**: `12-Days-to-Deming/PNGs/` (one PNG per original PDF page)
**Recon PNGs**: `12-Days-to-Deming/PNGs-recon/` (resized copies for Phase 1 — **use these for reconnaissance, never the full-size PNGs**)
**Target location**: `content/days/day-XX/` (one `.qmd` file per chapter)

---

## The 5 Phases

### Phase 0: Generate PNGs from PDF

Before Claude can read the source material, the day's PDF must be converted to individual page PNGs. The R script at `scripts/pdf_to_png_converter.R` handles this.

**Command:**

```bash
Rscript scripts/pdf_to_png_converter.R "12-Days-to-Deming/PDFs/<PDF_FILE>" --alt
```

Or via the shell wrapper:

```bash
./scripts/convert_pdf.sh "12-Days-to-Deming/PDFs/<PDF_FILE>" --alt
```

**Example (Day 4):**

```bash
Rscript scripts/pdf_to_png_converter.R "12-Days-to-Deming/PDFs/G.Day.4.09Jan20.pdf" --alt
```

**Details:**
- Uses R packages `pdftools` and `magick`
- Default output: 300 DPI, ~2550x3300px per page
- `--alt` flag uses the more reliable `pdf_convert()` method (recommended)
- Output goes to `12-Days-to-Deming/PNGs/` with naming pattern `{pdf_basename}_page_XXX.png`
- Custom DPI: add `--dpi=N` (e.g. `--dpi=600`)

**Source PDF naming:**

| Day | PDF filename |
|-----|-------------|
| 2 | `E.Day.2.12Oct21.pdf` |
| 3 | `F.Day.3.13Jan20.pdf` |
| 4 | `G.Day.4.09Jan20.pdf` |
| 5 | `H.Day.5.08Feb22.pdf` |
| 6 | `I.Day.6.19Feb22.pdf` |
| 7 | `J.Day.7.14Feb22.pdf` |
| 8 | `K.Day.8.11Jan20.pdf` |
| 9 | `L.Day.9.15Feb22.pdf` |
| 10 | `M.Day.10.16Feb22.pdf` |
| 11 | `N.Day.11.18Jan20.pdf` |
| 12 | `O.Day.12.16Feb22.pdf` |

See also: `scripts/README_pdf_converter.md` for full documentation.

### Phase 0.5: Create Recon PNGs

The API enforces a 2000px max dimension per image for many-image requests. Source PNGs are ~2550x3300, so they must be downsized before Phase 1.

**Command:**

```bash
for f in 12-Days-to-Deming/PNGs/<PREFIX>_page_*.png; do
  magick "$f" -resize 1800x1800\> "12-Days-to-Deming/PNGs-recon/$(basename "$f")"
done
```

- Output: `12-Days-to-Deming/PNGs-recon/` (1391x1800, well under the 2000px limit)
- Originals in `PNGs/` are kept untouched for Phase 3 image cropping
- The `>` flag means "only shrink, never enlarge"

### Phase 1: Reconnaissance

> **IMPORTANT**: Read images from `12-Days-to-Deming/PNGs-recon/`, NOT from `PNGs/`. The full-size PNGs (2550x3300) will cause an API error: `"Could not process image"`. The recon PNGs are resized to 1800px max and must exist before starting this phase — run Phase 0.5 first if they don't.

Claude reads all **recon PNGs** (`PNGs-recon/`) for the day and produces:

1. **Page inventory** — a numbered list of every page with a one-line description
2. **Proposed chapter plan** — how pages group into chapters (slug, title, page range)
3. **Figure inventory** — tables, charts, photos, diagrams found, with page numbers
4. **Interactive element inventory** — Pauses for Thought, Activities, Technical Aids, with identifiers (e.g. "Pause for Thought 3-a")

The user reviews this output and decides on chapter groupings.

### Phase 2: Day Brief

The user fills in `workflow/briefs/day-XX-brief.yml` using the template at `workflow/day-brief-template.yml`. The critical field is the **chapter plan** — everything else Claude determines from the source PNGs directly.

The brief is committed to version control as a record of editorial decisions.

### Phase 3: Build

Claude works through the brief chapter-by-chapter:

1. **Create the `.qmd` file** with standard front matter and R setup block
2. **Transcribe text** word-for-word from the source PNGs
3. **Crop figures** from source PNGs using ImageMagick and save to `assets/images/day-XX/`
4. **Add interactive elements** — Pauses for Thought, Activities, download buttons, clocks
5. **Add callouts** — return-to-reading callouts, principle/aside callouts. Always include `role="note" aria-label="…"` so screen readers announce the type (e.g. `<div class="principle_callout" role="note" aria-label="Principle">…</div>`). The visible icon comes from CSS `::before` automatically.

Each chapter is verified by reading back the `.qmd` file before moving to the next.

### Phase 4: Verify

1. Run transcription validation: `./scripts/validate-transcription.sh <day-number>` — compares PDF text against QMD content and reports potentially missing paragraphs. Review gaps to distinguish genuine omissions from false positives (garbled table content, page headers, intentionally omitted boilerplate).
2. Create a structural manifest at `workflow/validation/day-XX-manifest.yml` (see existing manifests for format), then run: `./scripts/check-structure.sh <day-number>` — checks viewof counts, figure existence, headings, and download buttons.
3. User spot-checks transcription accuracy against source PNGs
4. Run `quarto preview` to check rendering
5. Fix any issues found

#### Phase 4 for appendix content

Both scripts support an `--appendix <slug>` mode for content that lives in
`content/appendix/<slug>/` rather than `content/days/day-XX/`. The mode reads
manifest-declared paths instead of deriving them from the day number, so the
same scripts cover prose-only appendices (e.g. the Balaji Reddie
contributions, Optional Extras) and future appendix PDFs without further
changes.

```bash
./scripts/validate-transcription.sh --appendix contributions-balaji-reddie
./scripts/check-structure.sh --appendix contributions-balaji-reddie
```

**Manifest location:** `workflow/validation/appendix-<slug>-manifest.yml`.

**Minimum manifest fields** (see the Balaji manifest for a worked example):

```yaml
slug: contributions-balaji-reddie
pdf_file: Q.Contributions.from.Balaji.Reddie.11Sep21.pdf
content_dir: content/appendix/contributions-balaji-reddie
interactive_checks: false   # true (default) runs viewof + download-button checks

chapters:
  - file: "00-introduction.qmd"
    figures: []
    headings:
      - "An introduction to a System of Profound Knowledge"
```

For prose-only appendices set `interactive_checks: false` — the viewof and
download-button checks are then skipped and only figure existence and
heading match run per chapter. Interactive appendices (those with OJS input
widgets or download buttons) should either omit `interactive_checks` or set
it to `true`, and populate `viewof_count` / `has_download_button` per chapter
exactly as day manifests do.

**PDF prefix beyond D–O:** The day scripts hard-code the `D–O` letter
prefixes for source PDFs. Appendix manifests sidestep that by naming the
PDF file directly (`pdf_file:`), so any prefix — `P` (Appendix proper), `Q`
(Balaji contributions), `R` (References), `S` (Optional Extras), or future
additions — works without script changes.

### Phase 5: Integrate

1. Wire new chapters into `_quarto.yml` under the correct `part:`
2. Commit all new files (`.qmd` files, images, brief)

---

## Quick Reference

### Source PDF Prefixes and Page Counts

| Day | Prefix | Pages |
|-----|--------|-------|
| 2 | `E.Day.2.12Oct21` | 44 |
| 3 | `F.Day.3.13Jan20` | 66 |
| 4 | `G.Day.4.09Jan20` | 32 |
| 5 | `H.Day.5.08Feb22` | 32 |
| 6 | `I.Day.6.19Feb22` | 32 |
| 7 | `J.Day.7.14Feb22` | 40 |
| 8 | `K.Day.8.11Jan20` | 42 |
| 9 | `L.Day.9.15Feb22` | 36 |
| 10 | `M.Day.10.16Feb22` | 38 |
| 11 | `N.Day.11.18Jan20` | 40 |
| 12 | `O.Day.12.16Feb22` | 48 |

### File Naming Convention

```
content/days/day-XX/NN-slug-name.qmd
```

- `XX` = zero-padded day number (01, 02, ... 12)
- `NN` = zero-padded chapter sequence (01, 02, ...)
- `slug-name` = lowercase-hyphenated descriptive name

Examples from Days 1-2:
- `day-01/01-overture.qmd`
- `day-01/13-major-activity.qmd`
- `day-02/04-our-first-control-chart.qmd`

### Standard .qmd Front Matter

Every chapter starts with:

```yaml
---
title: "CHAPTER TITLE IN CAPS"
execute:
  echo: false
---
```

R setup (knitr hooks and function sourcing) is handled automatically via `.Rprofile` → `R/setup.R`. No per-chapter setup chunk is needed.

### _quarto.yml Structure

Each day is a `part:` with nested `chapters:`:

```yaml
- part: "Day X: The Title"
  chapters:
    - content/days/day-XX/01-first-chapter.qmd
    - content/days/day-XX/02-second-chapter.qmd
```

---

## CSS Classes

**Naming convention:** Use kebab-case for all new CSS classes (e.g. `.float-box`, `.fe-button`). Legacy snake_case classes (e.g. `.return_callout`) are retained as-is to avoid churn.

| Class | Purpose | Visual |
|-------|---------|--------|
| `.thought` | Pause for Thought (no commentary) | Green border |
| `.thought_commentary` | Pause for Thought with commentary | Red border |
| `.thought_commentary .collapse` | Hidden commentary revealed by button | Red background |
| `.technical_aid` | Technical Aid box | Purple background, black border, ⚙ icon |
| `.neave_note` | Author's explanatory aside | Serif font, left-aligned |
| `.deming_quote` | Inline Deming quotation highlight | Blue, bold |
| `.foreman-remark` | Red Beads foreman's dialogue | Navy italic, centered |
| `.return_callout` | External resource (read DemDim, watch video) | Blue background, ▶ icon |
| `.principle_callout` | Quoted Deming principle (14 Points, Deadly Diseases) | Green background, ◆ icon |
| `.aside_callout` | Author's instructional aside (drawing activities, NB notes) | Green background, ✎ icon |
| `.callout-emphasis` | Key insight pull-out | Pink background, ★ icon |
| `.activity_afterthought` | Post-activity italic note | Right-aligned italic |
| `.separator` | Red/black section divider | Red bar with black border |
| `.separator_white` | Inner white space in divider | White bar |
| `.separator_blue` | Inner blue line in divider | Blue line |
| `.major_activity_title` | Major Activity heading pill | Blue rounded pill |
| `.float-box` | Left-floating content box | 300px, left float |
| `.float-box-right` | Right-floating content box | 300px, right float |
| `.float-box-content` | Inner styling for float boxes | Border, background, rounded |
| `.analysis_box_title` | Analysis section title | Bold, centered, 1.3em |

---

## R Functions (from `R/functions/main-functions.R`)

| Function | Purpose | Example |
|----------|---------|---------|
| `create_clock(hour, minute)` | Render a clock face showing the time | `create_clock(9, 30)` |
| `run_chart_plot(values, ...)` | Parameterised run chart (line_width, y_limits, y_breaks, y_minor_breaks, hlines, hline_labels) | `run_chart_plot(c(13, 19, 18, ...))` |
| `red_beads_control_chart(vec, LCL, UCL)` | Control chart with limits (wraps run_chart_plot) | `red_beads_control_chart(vec, 1.4, 18.2)` |
| `make_redbeads_df(day1, day2, ...)` | Build Red Beads data table | See Day 2 `06-your-turn.qmd` |
| `render_redbeads_table(df)` | Render gt table for Red Beads | `render_redbeads_table(df1)` |

---

## Interactive Element Templates

### Pause for Thought (no commentary — green box)

```markdown
<div class="thought">

# PAUSE FOR THOUGHT X–y

Question text here.

```{ojs}
viewof thought_Xy = Inputs.textarea({placeholder: "Type your comments here.", rows: 10})
```

<div class="activity_afterthought">(For brief discussion see Appendix page N.)</div>
</div>
```

### Pause for Thought (with commentary — red box)

```markdown
<div class="thought_commentary">

# PAUSE FOR THOUGHT X–y

Question text here.

```{ojs}
viewof thought_Xy = Inputs.textarea({placeholder: "Type your comments here.", rows: 10})
```

<button class="btn btn-primary" type="button" data-bs-toggle="collapse" data-bs-target="#collapse_Xy" aria-expanded="false" aria-controls="collapse_Xy">
Click this after writing your comments
</button>

<div class="collapse" id="collapse_Xy">
Commentary text here.
</div>
</div>
```

### Activity with Text Input

```markdown
<div class="thought_commentary">

# ACTIVITY X–y

Instructions here.

```{ojs}
viewof activity_Xy_1 = Inputs.textarea({placeholder: "Type your answer here.", rows: 5})
```
</div>
```

For single-line inputs (e.g. Red Beads foreman remarks):

```markdown
```{ojs}
viewof activity_Xy_i = Inputs.text({placeholder: "Type your comment here."})
```
```

### Download Button (end of chapter)

```markdown
```{ojs download_all}
// Download button element
download_button = html`<button class="btn btn-primary" type="button">Download Your Notes</button>`
```

```{ojs download_trigger}
//| output: false

import { downloadNotes } from "../../../assets/scripts/functions.js"

download_button.onclick = () => {
  downloadNotes([viewof thought_Xy, viewof thought_Xz], "thoughts_Xy_Xz.txt");
};
```
```

### Clock (timing indicator)

Clocks appear in a columns layout at the right edge:

```markdown
:::: {.columns}

::: {.column width="85%"}
Content paragraph that appears alongside the clock.
:::

::: {.column width="15%"}
<div style="margin-top: 80px">
```{r, echo=FALSE, message=FALSE, warning=FALSE}
create_clock(3, 40)
```
</div>
:::

::::
```

Adjust `margin-top` to vertically align the clock with the relevant text.

### Technical Aid

```markdown
<div class="technical_aid" role="note" aria-label="Technical aid">
## Technical Aid N

Content with LaTeX math:

$$
\text{formula here}
$$
</div>
```

### Section Separator (end of major section)

```markdown
<div class="separator">
  <div class="separator_white">
  <div class="separator_blue"></div>
  </div>
</div>
```

### Major Activity Title

```markdown
<div class="major_activity_title">
<h1>Major Activity X–y</h1>
</div>
```

### Neave Note (author aside)

```markdown
<div class="neave_note">
Explanatory text in serif font.
</div>
```

Or inline: `<span class="neave_note">...</span>`

### Deming Quote (inline highlight)

```markdown
<span class="deming_quote">"Quoted text from Deming."</span>
```

### Float Box (sidebar content)

```markdown
<div class="float-box">
<div class="float-box-content">
Content in a floating sidebar box.
</div>
</div>
```

Or for right-aligned: use `class="float-box-right"`.

### Image with Lightbox

```markdown
![Description](/assets/images/day-XX/filename.png){.lightbox}
```

With alignment options:

```markdown
![Description](/assets/images/day-XX/filename.png){fig-align="center" width="80%" .lightbox}
```

### Columns Layout

```markdown
:::: {.columns}

::: {.column width="55%"}
Left column content.
:::

::: {.column width="45%"}
Right column content.
:::

::::
```

### Footnotes

```markdown
Some text with a reference[^a].

<!--
FOOTNOTES
-->

[^a]: Footnote text here.
```

---

## Accessibility Conventions

### Language attributes for non-English terms

Screen readers mispronounce foreign-language terms unless they're wrapped in a
`<span>` with a `lang` attribute telling the engine which language to use.

**When to wrap:** Any non-English word or phrase that a reader would recognise
as foreign — Japanese management terms (*kaizen*, *gemba*, *muda*), German
philosophy terms, French or Latin phrases like *raison d'être* or *sine qua
non*, etc.

**When NOT to wrap** (WCAG 3.1.2 exceptions):

- Proper names (people, places, companies — *Toyota*, *Taiichi Ohno*)
- Words fully naturalised in English — `i.e.`, `e.g.`, `etc.`, `vice versa`,
  `status quo`, `ad hoc`. These are in the vernacular; marking them as Latin
  can actually *regress* pronunciation on modern screen readers.
- Single technical terms that have become English (*café*, *résumé*)

**Syntax:**

```markdown
Deming often emphasised <span lang="ja">kaizen</span> (continuous improvement).

The French phrase <span lang="fr">raison d'être</span> captures this well.
```

Use ISO 639-1 codes: `ja` Japanese, `de` German, `fr` French, `la` Latin,
`es` Spanish.

### Glossary tooltips for specialised terms

Deming's vocabulary is heavy with terms readers may need to look up — *common
cause*, *special cause*, *PDSA cycle*, *operational definition*,
*transformation*, etc. The `<dfn>` pattern shows the definition inline on
hover or keyboard focus, so readers don't have to leave the page.

**Cap and audit log.** The full set of marked terms is governed by an
audit at `docs/glossary-audit.md` — capped at **~10 course-defining terms**
to prevent visual noise, tab-stop pollution, and pedagogical
short-circuiting. Don't add a new dfn without first updating that
document with the rationale, source location, and chosen tooltip wording.
The cap is the discipline; if a new candidate is genuinely stronger than
one already in the list, displace rather than expand.

**Syntax:**

```markdown
Deming called them <dfn data-definition="A cause of variation arising from a
specific, identifiable disturbance — not part of the system's normal
operation.">"special" causes</dfn>.
```

The accompanying machinery (`assets/scripts/dfn-tooltip.js`, plus CSS rules
in `assets/styles/main.css`) does the rest: it makes the dfn keyboard-
focusable, injects a sibling `<span role="tooltip">`, wires
`aria-describedby`, and dismisses on Escape.

**When to mark up:**

- The **first defining instance** of a specialised term within a chapter —
  that is, the sentence where the term is introduced or named for the first
  time. `<dfn>` is HTML's "this is the term being defined" element, so the
  semantics match.
- Pure-prose chapters preferred — avoid wrapping terms inside Deming's own
  block quotes, where the dotted underline and tooltip would clash with the
  quote's visual frame.

**When NOT to mark up:**

- Subsequent uses of an already-defined term in the same chapter — one
  marker per chapter is plenty; readers can scroll back if they need a
  refresher.
- Inside R-emitted figures, control-chart legends, or Mermaid/DiagrammeR
  diagrams. The tooltip script only scans the rendered HTML body.
- Inside `<span class="deming_quote">…</span>` — leave Deming's own words
  untouched; readers expect quotations to be diplomatic transcriptions.

**Definition style:**

- Two sentences max — the tooltip should fit comfortably on a phone.
- Plain language. Don't define a term using two more undefined terms.
- Avoid HTML inside `data-definition`: the JS injects it as `textContent`,
  so any tags would be rendered literally.

**Positioning caveat.** The tooltip always opens *above* the term. Avoid
marking up terms that sit in the first line or two of a chapter — the
tooltip would clip above the viewport. Pick a defining instance further
into the prose instead.

### Reading-time indicator

Every chapter is automatically annotated with an estimated reading time
injected under the H1 by `filters/reading-time.lua`. The filter counts
prose in paragraphs, list items, blockquotes, tables, and H2+ headings;
it skips `CodeBlock`, `RawBlock`, image captions, and Quarto's injected
hidden navigation/meta divs. Minutes are computed at 200 wpm and
rounded up.

The filter also detects activity content (`viewof`, `Inputs.textarea`,
`createDownloadButton`, or a `.thought` div) and appends
"+ activities" to the label so readers know that prompts, reflections,
and downloads add to the prose estimate. Output looks like:

- `~ 6 min reading` — prose-only chapter
- `~ 6 min reading + activities` — chapter with embedded widgets

Chapters with fewer than 50 prose words omit the indicator rather than
misrepresent engagement.

No per-chapter action is required — the filter is registered in
`_quarto.yml` and runs for every rendered page.

---

## Inter-Day Cross-References

The course text contains over 200 concrete "Day N page M" references plus a
tail of fuzzy mentions ("as we saw on Day 5", "on Day 9"). Print page numbers
no longer map cleanly onto the digitised chapter structure, so every reference
needs a judgement call on what to link to. The conventions below exist so that
work is mechanical, not per-reference reinvention.

### Anchor convention

Page anchors follow the existing pattern used throughout `content/appendix/`
and `content/days/day-01/`: **`{#sec-pageN}`**, where `N` is the print page
number of *that day*. Two placement forms are permitted:

- **Preferred — attached to a heading** that opens the print page:

  ```markdown
  ## The Deming Prize and the Nashua Corporation {#sec-page2}
  ```

- **Bare marker** on its own line, when the page starts mid-paragraph with no
  natural heading:

  ```markdown
  []{#sec-page7}
  ```

Anchors are file-scoped — `#sec-page7` in one day and `#sec-page7` in another
do **not** collide because links reference them through the file path, not
Quarto's global `@sec-` cross-reference system.

### Link syntax

Use plain Markdown links with a `.qmd` path — Quarto rewrites the extension to
`.html` at render time, and the path resolves correctly during `quarto preview`.

```markdown
<!-- Same-day link: no path needed -->
See [page 27](#sec-page27).

<!-- Cross-day link from a content/days/day-NN/ chapter -->
See [Day 4 page 20](../day-04/04-points-1-to-6.qmd#sec-page20).

<!-- Cross-day link from a content/appendix/ file -->
See [Day 2 page 16](../days/day-02/04-our-first-control-chart.qmd#sec-page16).
```

The relative path differs by source location — `../day-NN/` when the linking
file lives in another day directory, `../days/day-NN/` when it lives in
`content/appendix/`. The audit table's `source_file` column tells you which
form to use for each row.

Do **not** use Quarto's `@sec-pageN` cross-reference syntax for inter-day links
— it is ambiguous across days because `#sec-page7` exists in multiple files.

### Decision rules for concrete refs ("Day N page M")

1. **If the target anchor already exists** → link.
2. **If the target anchor is missing but the print page maps cleanly to a
   heading** → add `{#sec-pageM}` to that heading in the target file, then link.
3. **If the print page falls mid-paragraph with no clean anchor point** → link
   to the nearest preceding anchor and note the approximation in the audit
   table (column `decision = link-approx`).
4. **If the target chapter does not yet exist in the digitised edition** (e.g.
   parts of Days 8–12 that may be restructured) → mark `decision = defer` and
   revisit once the target is in place.

### Decision rules for fuzzy mentions

- **Whole-day phrases** ("on Day 5", "we will see on Day 9") → link to the
  day's first chapter file (`../day-NN/01-*.qmd`), no anchor.
- **Temporal pointers** ("as we saw earlier", "previously", "above") → leave
  as plain text. There is no target to disambiguate.
- **Named section references** ("the Red Beads Experiment", "Point 10") →
  link if the named target has a heading; otherwise leave plain.

### Appendix combo references

Appendix prose contains combined print-era pointers like:

```markdown
*(Return to Workbook page 70 / Day 5 page 2.)*
```

Per the #195 decision (Workbook removal, Option A), strip the Workbook half
and keep the Day-page half, then apply the link rules above:

```markdown
*(Return to [Day 5 page 2](../days/day-05/02-points-7-to-14.qmd#sec-page2).)*
```

The audit table flags each occurrence so the rewrite pattern is applied
uniformly in #200/#201.

### Audit table

The authoritative list of all 211 concrete references lives at
`workflow/inter-day-refs.csv`. It is regenerated by
`scripts/build-interday-audit.R`, which extracts every `[Dd]ay N page M` match
from `content/` and auto-populates the target columns when the target day
already has `#sec-pageM` present. Re-run the script after adding anchors to
refresh the "anchor-needed" flags.

```bash
Rscript scripts/build-interday-audit.R
```

A 30-item fuzzy-mention spot check is appended at the bottom of the CSV
(rows with `kind = fuzzy`) to sanity-check the policy before execution.

---

## Image Cropping Workflow

When a figure needs to be extracted from a source PNG:

1. **Identify** the source PNG file (e.g. `F.Day.3.13Jan20_page_019.png`)
2. **Check dimensions**: `magick identify filename.png` (typically ~2550x3300)
3. **Crop iteratively**:
   ```bash
   magick "source.png" -crop WIDTHxHEIGHT+X+Y "assets/images/day-XX/descriptive-name.png"
   ```
4. **Review** the cropped image, adjust coordinates, repeat until precise
5. **Reference** in `.qmd`:
   ```markdown
   ![Description](/assets/images/day-XX/descriptive-name.png){.lightbox}
   ```

---

## Checklist Per Day

- [ ] Phase 1: Reconnaissance complete — page inventory and chapter plan proposed
- [ ] Phase 2: Day brief filled in at `workflow/briefs/day-XX-brief.yml`
- [ ] Phase 3: All `.qmd` files created and text transcribed
- [ ] Phase 3: All figures cropped and saved to `assets/images/day-XX/`
- [ ] Phase 3: All interactive elements added (Pauses, Activities, downloads, clocks)
- [ ] Phase 4: `validate-transcription.sh` run — gaps reviewed and explained
- [ ] Phase 4: Structural manifest created and `check-structure.sh` passes
- [ ] Phase 4: User has spot-checked transcription
- [ ] Phase 4: `quarto preview` renders without errors
- [ ] Phase 5: Chapters wired into `_quarto.yml`
- [ ] Phase 5: All files committed
