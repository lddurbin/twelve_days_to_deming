# Conversion Process — Archived

> **Status — historical.** All 12 days have been converted from Neave's
> source PDFs into interactive Quarto chapters. This document preserves the
> per-day workflow that drove the conversion and is kept here for
> traceability — to explain the shape of `workflow/briefs/`,
> `workflow/validation/`, the `12-Days-to-Deming/` source tree, and the
> per-phase scripts that still live in `scripts/`. It is **not** an active
> reference for ongoing edits; for those, see `workflow/PATTERNS.md`.
>
> If a future contributor needs to reproduce the conversion process — for
> example, to onboard newly-released Neave material as additional
> appendices — this is the starting point.

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

| Day | PDF filename | Pages |
|-----|-------------|-------|
| 2 | `E.Day.2.12Oct21.pdf` | 44 |
| 3 | `F.Day.3.13Jan20.pdf` | 66 |
| 4 | `G.Day.4.09Jan20.pdf` | 32 |
| 5 | `H.Day.5.08Feb22.pdf` | 32 |
| 6 | `I.Day.6.19Feb22.pdf` | 32 |
| 7 | `J.Day.7.14Feb22.pdf` | 40 |
| 8 | `K.Day.8.11Jan20.pdf` | 42 |
| 9 | `L.Day.9.15Feb22.pdf` | 36 |
| 10 | `M.Day.10.16Feb22.pdf` | 38 |
| 11 | `N.Day.11.18Jan20.pdf` | 40 |
| 12 | `O.Day.12.16Feb22.pdf` | 48 |

Day 1 was already converted before this workflow was formalised; its source PDF is not in the `PNGs/` tree.

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

## Per-Day Checklist

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
