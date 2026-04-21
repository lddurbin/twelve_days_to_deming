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
5. **Add callouts** — return-to-reading callouts, info callouts

Each chapter is verified by reading back the `.qmd` file before moving to the next.

### Phase 4: Verify

1. Run transcription validation: `./scripts/validate-transcription.sh <day-number>` — compares PDF text against QMD content and reports potentially missing paragraphs. Review gaps to distinguish genuine omissions from false positives (garbled table content, page headers, intentionally omitted boilerplate).
2. Create a structural manifest at `workflow/validation/day-XX-manifest.yml` (see existing manifests for format), then run: `./scripts/check-structure.sh <day-number>` — checks viewof counts, figure existence, headings, and download buttons.
3. User spot-checks transcription accuracy against source PNGs
4. Run `quarto preview` to check rendering
5. Fix any issues found

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
| `.technical_aid` | Technical Aid box | Purple background, black border |
| `.neave_note` | Author's explanatory aside | Serif font, left-aligned |
| `.deming_quote` | Inline Deming quotation highlight | Blue, bold |
| `.foreman-remark` | Red Beads foreman's dialogue | Navy italic, centered |
| `.return_callout` | Return-to-reading instruction | Blue background |
| `.info_callout` | General info callout | Green background |
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
<div class="technical_aid">
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
