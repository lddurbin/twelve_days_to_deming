# Patterns and Conventions

The house-style reference for *12 Days to Deming*. Lists the CSS classes,
R helpers, interactive-element templates, accessibility conventions, and
inter-day cross-reference rules used across the site, so any future edit
(or future agent) can match the existing patterns without reverse-engineering
them from sample chapters.

> The original per-day conversion workflow that produced the site is
> archived at [`archive/CONVERSION_PROCESS.md`](archive/CONVERSION_PROCESS.md).
> All 12 days are converted; that document is preserved for traceability,
> not for ongoing use.

---

## File Naming Convention

```
content/days/day-XX/NN-slug-name.qmd
```

- `XX` = zero-padded day number (01, 02, ... 12)
- `NN` = zero-padded chapter sequence (01, 02, ...)
- `slug-name` = lowercase-hyphenated descriptive name

Examples:
- `day-01/01-overture.qmd`
- `day-01/13-major-activity.qmd`
- `day-02/04-our-first-control-chart.qmd`

## Standard .qmd Front Matter

Every chapter starts with:

```yaml
---
title: "CHAPTER TITLE IN CAPS"
execute:
  echo: false
---
```

R setup (knitr hooks and function sourcing) is handled automatically via `.Rprofile` → `R/setup.R`. No per-chapter setup chunk is needed.

## _quarto.yml Structure

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
| `.return_callout` | Study resource (read DemDim, watch video) | Blue background, ▶ icon |
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

### Long-Descriptions for Charts and Diagrams

Many control charts, run charts, histograms, and process diagrams in the
course carry pedagogy — the learner is supposed to *see* a pattern, a
special-cause point, a rule violation. Alt text is too short to do that
work; readers who can't parse the visual (screen-reader users,
chart-novices, cognitively-fatigued readers) lose the lesson.

Pair every chart or diagram with a `<details>` block that explains what
the visual is showing, placed directly after the image:

```markdown
![Run chart of monthly sales declining from ~1000 to ~400](/assets/images/day-02/Picture%201.jpg){.lightbox}

<details>
<summary>Describe this chart</summary>

A run chart with months along the x-axis (August through December) and
sales on the y-axis. The line starts near 1000 in August, dips slightly
through September, then drops sharply in October and again in November,
ending near 400 in December.

</details>
```

**Conventions:**

- Use the literal summary text **"Describe this chart"** (or "Describe
  this diagram" for non-chart visuals like apparatus or process flows) so
  the disclosure is predictable across the site.
- Keep alt text concise (≤ 120 chars) — what the image *is*. Put the
  pedagogical *what to see* in the `<details>` body.
- Two to four sentences in the body, focused on the lesson the learner
  should take away — patterns, outliers, rule violations, trends.
- A blank line between `<summary>` and the body is required for Quarto to
  parse the markdown inside.
- For R-rendered charts (`run_chart_plot()`,
  `red_beads_control_chart()`), place the `<details>` block in raw
  markdown immediately after the closing ```` ``` ```` of the R chunk.
- **When to skip:** decorative images (portraits, icons, apparatus
  illustrations whose alt text already does the job), and pure data
  tables presented as images (the data is the data — a description
  repeating "this is a table of weekly results" adds nothing).
- **Repetitive series:** if a chapter shows the same chart with one new
  data point per step (e.g. progressive run charts), describe the first
  and note that subsequent charts add one point each. Don't restate.

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

### Glossary terms

Deming's vocabulary is heavy with terms readers may need to look up — *common
cause*, *special cause*, *PDSA cycle*, *operational definition*,
*transformation*, etc. The course resolves this in two layers:

1. An **appendix glossary** at `content/appendix/glossary.qmd` — the
   canonical, predictable lookup destination for non-linear and returning
   readers.
2. A `<dfn id="anchor-slug">term</dfn>` marker at the **first defining
   instance** in the prose. The `<dfn>` element is HTML's "this is the
   defining instance" semantic; the `id` makes the appendix page able to
   deep-link back to where the term is first taught in context.

There is no inline tooltip layer (it was removed in [#265](https://github.com/lddurbin/twelve_days_to_deming/issues/265) — the appendix
does that job better, without dotted-underline visual noise or duplication
with surrounding prose).

**Cap and audit log.** The full set of marked terms is governed by an
audit at `docs/glossary-audit.md` — capped at **~10 course-defining
terms** to prevent anchor-namespace pollution and pedagogical
short-circuiting. Don't add a new dfn (and a new glossary entry) without
first updating that document with the rationale, source location, anchor
slug, and chosen wording. The cap is the discipline; if a new candidate
is genuinely stronger than one already in the list, displace rather than
expand.

**Syntax:**

```markdown
Deming called them <dfn id="special-cause">"special" causes</dfn>.
```

Then add a matching entry to `content/appendix/glossary.qmd`, in
alphabetical order, with the same anchor slug:

```markdown
## special cause / special-cause variation {#special-cause}

Additional causes of variation that are not there all the time — one-off
happenings or temporary changes that noticeably affect how the process
behaves. Shewhart called them "assignable" causes.

[First defined in context: Day 1, "The Deming story"](../days/day-01/11-deming-story.qmd#special-cause).
```

**When to mark up:**

- The **first defining instance** of a specialised term within the course
  — that is, the chapter where Neave's prose does the defining work.
  Subsequent uses stay plain.
- Pure-prose chapters preferred — avoid wrapping terms inside Deming's own
  block quotes (`<span class="deming_quote">`), where Deming's voice
  shouldn't be tagged with editorial markup.

**When NOT to mark up:**

- Subsequent uses of an already-defined term, anywhere in the course. One
  `<dfn>` per term, course-wide; the anchor is a single canonical target.
- Inside R-emitted figures, control-chart legends, or Mermaid/DiagrammeR
  diagrams.
- Inside `<span class="deming_quote">…</span>` — leave Deming's own words
  untouched; readers expect quotations to be diplomatic transcriptions.

**Anchor-slug style:**

- Lowercase, hyphenated, no quotes or punctuation: `common-cause`, not
  `"common"-cause`.
- Stable forever once shipped — external pages and the appendix page both
  link to it.

**Definition style (in the appendix entry):**

- Two-to-three sentences. Plain language. Don't define a term using two
  more undefined terms.
- Sourced verbatim from Neave or from a Deming quote Neave reproduces. No
  paraphrase from general knowledge.

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

When a figure needs to be extracted (or re-extracted) from a source PNG:

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

Source PNGs at full resolution live in `12-Days-to-Deming/PNGs/` (kept around
specifically so figures can be re-cropped without re-running the PDF→PNG
conversion).
