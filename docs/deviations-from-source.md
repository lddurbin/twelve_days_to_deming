# Deviations from Source

This log records **material departures** from Henry Neave's *12 Days to Deming* course where the site's text, structure, or content differs from the NZOQ PDF originals. The project's stated principle is verbatim transcription, so every material departure is a deliberate choice and is captured here.

## Why this log exists

Future contributors should be able to see at a glance where the site has diverged, and readers cross-referencing the NZOQ PDFs should have a single index of what's different. Without this log, each new deviation gets relitigated from scratch because prior precedent isn't surfaced.

## What counts

Record an entry when the change is **material**. Don't record mechanical changes.

**Material** (record):
- Whole sentences, paragraphs, or passages removed, added, or reworded.
- Pedagogical elements (activities, cross-references, call-outs) omitted or restructured.
- Interactive affordances substituted for static text in a way that changes what the reader does.
- Reorganisation that moves content across chapter or day boundaries.

**Mechanical** (don't record):
- Typography, whitespace, punctuation normalisation.
- Minor reflowing of paragraphs for web layout.
- Image extraction from scans.
- Clear typo corrections where Neave's intent is unambiguous.
- Hyperlinking existing cross-references (e.g. "see page 42" → an in-page anchor) without altering wording.

When in doubt, record it — readers and future contributors are better served by over-inclusion than by silent omission.

## Entry format

Each deviation is an `## YYYY-MM-DD — short title` section with the following fields:

- **What** — one-line description of the change.
- **Where** — site location (chapter, appendix, or surface area).
- **Source reference** — the corresponding location in Neave's PDF, where identifiable.
- **Why** — the reason for departing from the source.
- **Decided in** — link to the issue or PR comment where the decision was locked.
- **Landed in** — implementing PR(s) and/or commit(s), or *Pending — tracked in #NNN* if not yet merged.

Entries are listed newest-first.

---

## 2026-04-28 — Remove decorative clock icons and the welcome-page paragraph that introduces them

- **What** — Removed all 38 chapter-level `create_clock(HH, MM)` decorative SVGs across 15 day chapter files (Day 1, Day 5, Day 8), plus the 4 illustrative clocks on the welcome page (`index.qmd`) — 42 call sites in total. On the welcome page, the three sentences that introduced the clock icons to the reader were also removed: *"Little clock icons such as those I'm showing you against this paragraph will appear both on the opening page for each day against a description of the day's contents and also at various places within the text. Again, treat these indications as rough guides rather than instructions. I believe they will help you to pace yourself appropriately through the reading and particularly when carrying out the activities."* The surrounding paragraph (start/end times, lunch-break box, Day 1 differing length) remains intact. Each clock site was wrapped in a `:::: {.columns}` 85%/15% layout that existed only to position the clock; the wrapper was lifted so prose flows full-width. The `create_clock()` function and `CLOCK` layout-constants block were deleted from `R/functions/main-functions.R`, and `tests/testthat/test-create-clock.R` was removed.
- **Where** — `index.qmd` (welcome page, ~3-sentence prose excision); 15 chapter QMDs across `content/days/day-01/`, `content/days/day-05/`, and `content/days/day-08/01-introduction.qmd`; `R/functions/main-functions.R`; `assets/templates/chapter-template.qmd`; `tests/testthat/test-create-clock.R` (deleted).
- **Source reference** — Neave's printed source uses small clock-face icons in the page margins to anchor each section to a wall-clock time in the original 9 am–5 pm workshop schedule (e.g. *"9.30"*, *"10.25"*, *"12.00"*). The welcome paragraph that introduces those icons is in the *Welcome* section of the printed book.
- **Why** — Three reasons. (1) **Accessibility:** the ggplot SVG clocks had no `aria-label`, no text alternative, no dark-mode variant, and rendered too small to read on most viewports. (2) **No semantic value for self-paced web readers:** the wall-clock times only made sense in the original workshop schedule the icons anchor to, which does not exist on the web; the chapter-top reading-time indicator (`filters/reading-time.lua`) already conveys actionable pacing. (3) **Broken transcription on Day 5:** all 13 clock calls in `02-points-7-to-14.qmd` and `03-the-deadly-diseases.qmd` were stamped to `12:00`, almost certainly a transcription artefact. The welcome-page sentences that introduce the icons were removed because, with the icons gone, *"Little clock icons such as those I'm showing you against this paragraph"* no longer has a referent — leaving the prose would mislead the reader.
- **Decided in** — Issue [#286](https://github.com/lddurbin/twelve_days_to_deming/issues/286). The issue body excluded `index.qmd` from its file list, but `index.qmd` was a hidden caller of `create_clock()` whose meta-commentary paragraph was load-bearing on the icons; the welcome-page excision was made in the same change to keep `quarto render` green and the remaining prose internally consistent.
- **Landed in** — *Pending — tracked in [#286](https://github.com/lddurbin/twelve_days_to_deming/issues/286); implementing in PR [#288](https://github.com/lddurbin/twelve_days_to_deming/pull/288).*

---

## 2026-04-25 — Split `info_callout` into `principle_callout` and `aside_callout`

- **What** — The single `info_callout` class was carrying two semantically distinct jobs: (a) presenting Deming's quoted principles (the 14 Points and the 5 Deadly Diseases — 19 instances) and (b) carrying instructor-voice asides to the reader (drawing-activity instructions and Neave's "NB" study-strategy advisory — 3 instances). Split into `.principle_callout` (19) and `.aside_callout` (3). Each typed callout now pairs a visible CSS `::before` icon with `role="note" aria-label="…"` for screen-reader announcement: `principle_callout` → ◆ + "Principle"; `aside_callout` → ✎ + "Author's note"; `return_callout` → ▶ + "Study resource"; `callout-emphasis` → ★ + "Key insight". Visual styling (background, border, padding) is unchanged from the prior `info_callout` definition; the two new classes share those declarations via a comma-list selector. The single `arrival_callout` instance already had `role="note" aria-label="Navigation note"` and was left untouched.
- **Where** — `assets/styles/main.css` (callout component definitions, dark-mode overrides, mobile and dyslexic-font media queries). Content sites: `content/days/day-03/03-the-importance-of-time.qmd` (2 aside, 1 emphasis), `content/days/day-03/04-more-on-the-sales-data.qmd` (1 aside, the NB), `content/days/day-04/01-introduction.qmd` (1 return), `content/days/day-04/04-points-1-to-6.qmd` (6 principle), `content/days/day-05/02-points-7-to-14.qmd` (8 principle), `content/days/day-05/03-the-deadly-diseases.qmd` (5 principle, 1 return). Pattern documentation in `workflow/PATTERNS.md`.
- **Source reference** — Not a textual deviation from Neave; this is a presentation/markup change made in service of WCAG 1.4.1 (Use of Color).
- **Why** — WCAG 1.4.1 prohibits using colour as the sole means of conveying information. The former `info_callout` and `return_callout` were styled almost identically except for hue (yellow-green vs blue), so a colourblind reader could not distinguish them; screen-reader users had no audible cue at all. The icon adds a non-colour visual cue; `role="note" aria-label="…"` adds the screen-reader announcement. Splitting `info_callout` was incidental to compliance but warranted on its own merits — the two roles needed different labels (a "Deming principle" label is wrong for a drawing-activity note, and vice versa).
- **Decided in** — Conversation on #163 (2026-04-25): user picked icons over text-only cues and approved the principle/aside split when surfaced.
- **Landed in** — PR [#266](https://github.com/lddurbin/twelve_days_to_deming/pull/266).

## 2026-04-26 — Glossary discoverability cue; restyle `<dfn>` to non-italic + amber underline

- **What** — Two changes that together close the discoverability gap left by the appendix-glossary entry below. (1) Added a new paragraph to `index.qmd`'s "Page references and call-outs" section listing the seven glossary-marked terms by name and pointing first-time readers at the [Glossary appendix](../../content/appendix/glossary.qmd). (2) Replaced the user-agent default `<dfn>` rendering (italic) with an upright face plus a 2px solid amber underline, so the marker no longer collides visually with Neave's own use of italics for emphasis. Updated the corresponding paragraph in `accessibility.qmd` (which previously still described the removed tooltip behaviour) to describe the new visual treatment and its WCAG 1.4.1 status.
- **Where** — `index.qmd` (one new paragraph in the front-matter "Page references and call-outs" section), `assets/styles/main.css` (new `dfn` rule in light-mode + dark-mode underline-colour override; removed leftover `.dfn-tooltip` dark-mode rule), `accessibility.qmd` (rewrote the "Glossary tooltips" paragraph that #265's PR had left stale).
- **Source reference** — Not a textual deviation from Neave; the new index.qmd paragraph is editor-voice site scaffolding (parallel to the green-callout and italic-bracket convention paragraphs already in that section), and the CSS change is a presentation choice. Neave's seven term wordings and their in-prose locations are unchanged.
- **Why** — After #265 stripped the inline tooltip layer, an in-prose `<dfn>` marker rendered as plain browser-default italic with no visual or textual cue that an appendix lookup existed; a linear first-time Day 1 reader had no obvious path to discover the glossary. A single discoverability paragraph in the preface closes that gap without reintroducing tooltip complexity. The italic default also collided with Neave's own emphasis use (e.g. `<dfn id="operational-definition">*operational* definition</dfn>` rendered with italic stacking on italic), so a non-italic visual treatment was needed regardless. A 2px solid amber underline keeps the cue non-colour-alone (WCAG 1.4.1) and visually distinct from the 1px blue link underline.
- **Decided in** — [#268](https://github.com/lddurbin/twelve_days_to_deming/issues/268) (the preface-cue proposal from PR #267 review) plus a follow-up design conversation on the dfn-vs-italic collision.
- **Landed in** — *Pending — tracked in [#268](https://github.com/lddurbin/twelve_days_to_deming/issues/268).*
- **Related** — Builds on the 2026-04-26 entry below (glossary appendix + tooltip removal). The optional follow-up phase noted there — linking the first per-Day recurrence of each term to the glossary anchor — remains out of scope and tracked separately.

## 2026-04-26 — Appendix glossary page; strip inline tooltip layer

- **What** — Added a new appendix glossary page at `content/appendix/glossary.qmd` listing the seven audit-approved course-defining terms (alphabetical, with stable anchor slugs and per-term backlinks to the chapter where each is first defined in context). Stripped the inline-tooltip layer that previously rendered the same definitions on hover/focus: removed the `data-definition="…"` attribute from each of the seven `<dfn>` markers (retaining the `<dfn>` element and adding an `id="anchor-slug"` matching the appendix entry), deleted `assets/scripts/dfn-tooltip.js`, dropped its `<script>` registration in `_quarto.yml`, and removed the dotted-underline / popup CSS block in `assets/styles/main.css`. Plain `<dfn>` now renders in browser-default italic. Removed the two pa11y URL entries added in PR #263 specifically to test tooltip-focus accessibility (Day 11 ch 4, Day 12 ch 4) and added the new glossary page in their place.
- **Where** — New: `content/appendix/glossary.qmd`, `workflow/PATTERNS.md` (renamed from `CONVERSION_GUIDE.md` and pruned of conversion-mechanics sections), `workflow/archive/CONVERSION_PROCESS.md` (the conversion-only sections moved here for traceability). Modified: `_quarto.yml` (appendices list + script-tag removal), `content/days/day-01/11-deming-story.qmd` (5 dfn sites), `content/days/day-11/04-theory-of-knowledge-operational-definitions.qmd` (1), `content/days/day-12/04-but-what-can-i-do.qmd` (1), `assets/styles/main.css` (CSS block removed), `.pa11yci.json`, `docs/glossary-audit.md`, plus reference updates in `README.md`, `.claude/agents/codebase-evaluator.md`, `scripts/build-interday-audit.R`, `scripts/archive/README.md`, and `workflow/briefs/appendix-optional-extras-brief.yml`. Deleted: `assets/scripts/dfn-tooltip.js`.
- **Source reference** — The seven definitions are unchanged; same Neave-and-Deming sources cited in the 2026-04-25 audit entry below.
- **Why** — The audit's stated audience is non-linear and returning readers (e.g. someone on Day 7 who's forgotten what "special cause" means a week after Day 3). The first-defining-instance rule placed the tooltip exactly where Neave's surrounding prose was already doing the defining work, and left every subsequent occurrence unmarked — so a returning reader on Day 7 got nothing. An appendix page is a better-shaped affordance for that audience: a single predictable destination, reachable from any chapter, with stable anchors. Once the appendix exists, the inline tooltip is a worse-placed duplicate and the dotted-underline / tab-stop / focus-popup machinery becomes pure cost. Keeping the `<dfn>` element (without the tooltip plumbing) costs nothing and preserves the screen-reader signal at the right place; adding `id` attributes makes the appendix able to deep-link back into context.
- **Decided in** — [#265](https://github.com/lddurbin/twelve_days_to_deming/issues/265), which captured the audience-mismatch concern that closure of [#168](https://github.com/lddurbin/twelve_days_to_deming/issues/168) had left unaddressed.
- **Landed in** — PR [#267](https://github.com/lddurbin/twelve_days_to_deming/pull/267).
- **Related** — Supersedes the inline-tooltip framing in the 2026-04-25 entry below (the seven terms and their wordings remain; only the delivery vehicle changes). Out of scope for this PR but flagged in #265 as an optional follow-up phase: linking the *first* recurrence of each term within each subsequent Day to the glossary anchor.

## 2026-04-25 — Glossary tooltips on seven course-defining terms

- **What** — Wrapped seven specialised terms in `<dfn data-definition="…">` markup at their first defining instance in Neave's prose. Three were landed in PR [#262](https://github.com/lddurbin/twelve_days_to_deming/pull/262) (#167): "common" causes of variation, "special" causes, and PDSA cycle (all in `content/days/day-01/11-deming-story.qmd`). Four are added in this audit: "in statistical control" (Day 1 ch 11, line 154), System of Profound Knowledge (Day 1 ch 11, line 504), operational definition (Day 11 ch 4, line 21), and transformation in Deming's sense (Day 12 ch 4, line 14). Three further candidates were considered and rejected: the Joiner triangle (definition is carried by an adjacent diagram, not a sentence), the funnel experiment (Neave describes the apparatus but the conceptual takeaway is taught experientially), and "appreciation for a system" (Neave never tightly defines the phrase as a unit — only Deming's own definition of "system" appears in the chapter). Each `data-definition` value is sourced from Neave's prose (or a Deming quote Neave reproduces verbatim); none is synthesised from general knowledge. Full audit trail in [`docs/glossary-audit.md`](glossary-audit.md).
- **Where** — `content/days/day-01/11-deming-story.qmd`, `content/days/day-11/04-theory-of-knowledge-operational-definitions.qmd`, `content/days/day-12/04-but-what-can-i-do.qmd`. Audit document at `docs/glossary-audit.md`.
- **Source reference** — Neave's prose at each first-defining-instance location, cited line-by-line in the audit document. The Deming quote inside the `operational definition` tooltip is from *Out of the Crisis* page 231[276] (which Neave already reproduces inline in the chapter); the Deming-tone phrasing inside the `transformation` tooltip paraphrases Neave's own blockquote of *The New Economics* Chapter 4.
- **Why** — Tooltips help non-linear and returning readers (e.g. a Day 7 reader who has forgotten what "special cause" means a week after Day 3). The cap of ~10 terms is the discipline that keeps the feature from drifting into visual noise, tab-stop pollution, or pedagogical short-circuiting. The "reject rather than synthesise" rule keeps tooltip wording faithful to Neave; the rejected three are documented so future contributors don't relitigate the same questions.
- **Decided in** — [#261](https://github.com/lddurbin/twelve_days_to_deming/issues/261) (the cap of ~10 was baked into the issue's acceptance criteria as the explicit thing to push back against; the audit ratified 7 marked / 3 rejected).
- **Landed in** — PR [#263](https://github.com/lddurbin/twelve_days_to_deming/pull/263).
- **Related** — Companion to PR [#262](https://github.com/lddurbin/twelve_days_to_deming/pull/262) (#167), which introduced the `<dfn>` mechanism with three proof-of-concept terms. Superseded in part by the 2026-04-26 entry below: the seven terms remain, but the inline-tooltip layer was replaced by an appendix glossary page.

## 2026-04-23 — Strip inline `[WB NNN]` cross-reference suffixes

- **What** — Removed all 47 inline Workbook-page cross-references from day chapters and the appendix. The bulk (44) were the italic `*[WB NNN]*` and plain `[WB NNN]` suffixes paired with a Day-chapter ref; the remaining 3 were prose-embedded shapes missed by the primary regex sweep — `page 29 [also on WB 151]` (day-09), `(or on WB 123)` (day-08), and `*(WB 56–67)*` (day-05) — all rewritten by hand to strip just the Workbook pointer. A further paired alternative in `content/days/day-12/04-but-what-can-i-do.qmd:74` — `**(pages 14--29** *[or WB 220--234 along with today's page 23]***)**` — was rewritten to `**(pages 14--29, along with today's page 23)**`, preserving the non-Workbook half of the original construct. Every WB ref was paired with an unambiguous Day-chapter pointer, so no navigational information was lost. Non-WB italic-bracketed paginations (e.g. `*Out of the Crisis* page 120 *[141]*` and `*The New Economics* page 58[83]`, which point at parallel editions of Neave's source books rather than the Workbook) were deliberately preserved.
- **Where** — 29 files across `content/days/` and `content/appendix/`.
- **Source reference** — Throughout Neave's original day chapters and appendix, which use a dual page-referencing system giving both the Day-chapter page and the corresponding printable-Workbook page.
- **Why** — Completes the Workbook-removal arc (#185 / #195 / #196 / #202 / #210 / #212). The printed Workbook no longer exists as a separate artefact in this delivery, so the WB page numbers had nothing on the site they could resolve to. Leaving them in place would have kept the codebase half-Workbook, half-not, and would have left a pattern for future per-day PRs to accidentally copy forward. The cross-reference utility they offered to PDF-edition readers is marginal — Day-chapter page headings still preserve structure, so a PDF-edition reader can correlate by heading.
- **Decided in** — Conversation on #213 (2026-04-23): user approved strip after audit confirmed all 44 regex-matched occurrences were safely mechanical; the remaining 3 prose-embedded shapes were identified during rendered-output verification and handled by hand.
- **Landed in** — *Pending — tracked in [#213](https://github.com/lddurbin/twelve_days_to_deming/issues/213).*

## 2026-04-23 — Rewrite index.qmd front-matter Workbook prose

- **What** — Stripped or rewrote the three Workbook-scaffolded sections in the front-matter `index.qmd`:
  1. **"To print or not to print…"** — compressed to three paragraphs and reframed around the site's digital-first active-learning model. Dropped the 2020 sponsor/"hosts" history, the "A. PLEASE START HERE" file pointer, the B1–B4 Workbook instalment definition, the Adobe Acrobat two-page-mode instructions, the gutter-margin explanation, and the back-to-back / non-duplex print procedures. Retained a single paragraph acknowledging that readers who prefer paper can use their browser's Print / Save-as-PDF.
  2. **"Information boxes, etc"** → **renamed "Page references and call-outs"** and compressed to three paragraphs. Removed the yellow/blue `.workbook_callout` round-trip demonstration (including the embedded example divs), the "moving to and from the Workbook" framing, and the `[WB NNN]` notation paragraphs. Preserved the Appendix/Day page-reference disambiguation convention, the description of green `.info_callout` boxes (swapping Neave's Workbook-page example for a site-native one on Day 4 page 16), and the in-quote `[italics in square brackets]` clarification convention.
  3. **"Guidance on printing and binding"** — deleted entirely, including the Neave author's note about Adobe Acrobat rendering, the ring-binder recommendation, the gutter explanation, the duplex-on-non-duplex print procedure, and Neave's own three-ring-binder setup with the "C. Front covers for binders" pointer.
- **Where** — `index.qmd` front matter.
- **Source reference** — Neave's "A. PLEASE START HERE" file, pp. 8–13.
- **Why** — Same rationale as [#196](https://github.com/lddurbin/twelve_days_to_deming/pull/196), [#202](https://github.com/lddurbin/twelve_days_to_deming/pull/202), and [#214](https://github.com/lddurbin/twelve_days_to_deming/pull/214): the printed Workbook no longer exists as a separate artefact in this delivery, the "A. PLEASE START HERE" / B1–B4 file-structure vocabulary doesn't correspond to anything on the site, and Adobe Acrobat / duplex-printer guidance doesn't apply to the Quarto HTML rendering. The site captures reader responses through embedded text inputs and a per-activity notes-download button, so the printed writing-surface framing was actively misleading.
- **Decided in** — Conversation on #212 (2026-04-23): user approved the three-decision set (compress ¶1, rename Section B, delete Section C entirely, combined deviations-log entry).
- **Landed in** — *Pending — tracked in [#212](https://github.com/lddurbin/twelve_days_to_deming/issues/212).*
- **Related** — [#213](https://github.com/lddurbin/twelve_days_to_deming/issues/213) still tracks the pending decision on inline `[WB NNN]` cross-reference suffixes; that question is deferred out of this PR.

## 2026-04-23 — Dead external links to deming.org.uk and rqoq.org.nz

- **What** — Six external hyperlinks retired because their domains no longer resolve. Two treatments were applied:
  1. **Wayback substitution (4 sites)** — `deming.org.uk` references in `content/days/day-01/02-rediscovered.qmd`, `content/days/day-01/06-outline.qmd`, `content/appendix/11-references-and-sources.qmd`, and `index.qmd` now link to the 2012-01-05 archived snapshot (`web.archive.org/web/20120105232234/…`) with an inline annotation that the live site is no longer online. The Feb 2022 "being upgraded" note in `11-references-and-sources.qmd` was rewritten accordingly.
  2. **De-linked with editorial note (2 sites)** — `welcome.qmd:109` (book-ordering footnote) de-linked and annotated "no longer trading"; `welcome.qmd:129` (PDF-hosting mirror list) de-linked and annotated "domain is no longer online and no archived snapshot is available", since `rqoq.org.nz` has zero Wayback captures.
- **Where** — `welcome.qmd`, `index.qmd`, `content/days/day-01/02-rediscovered.qmd`, `content/days/day-01/06-outline.qmd`, `content/appendix/11-references-and-sources.qmd`.
- **Source reference** — Neave's text treats both domains as live resources: the UK Deming Transformation Forum's Learning Store (bookshop/materials) and the NZOQ PDF-hosting mirror.
- **Why** — `deming.org.uk` no longer resolves and has only one Wayback capture (2012); the Forum appears to have wound down. `rqoq.org.nz` no longer resolves and was never archived. The two book-ordering footnote contexts (`welcome.qmd:109`, `index.qmd:568`) were split: `welcome.qmd:109` was fully de-linked because pointing readers at a 2012 snapshot to "order the book" is actively misleading; `index.qmd:568` retained the Wayback link with a clear archival note because its surrounding prose is informational rather than transactional.
- **Decided in** — Conversation on #239 (2026-04-23): user approved Wayback-where-available / editorial-note-where-not, with the welcome.qmd ordering footnote treated as "no longer trading".
- **Landed in** — *Pending — tracked in [#239](https://github.com/lddurbin/twelve_days_to_deming/issues/239).*

## 2026-04-21 — Rewrite or remove Workbook references from prose and front matter

- **What** — Drop or rewrite surviving references to "the Workbook" as a companion artefact, so readers are no longer pointed at a printed object that the site has replaced with in-page text inputs. Four distinct surfaces:
  1. Six prose sentences in day chapters (day-01, day-02, day-03, day-08, day-09, day-12) rewritten to drop the Workbook alternative while preserving the surrounding pedagogical point.
  2. Appendix return-navigation parentheticals of the form `(Return to Workbook page X / Day Y page Z.)` — ~40 instances across `content/appendix/*.qmd` reduced to `(Return to Day Y page Z.)`.
  3. Appendix section-heading cross-references (`## Point 7. … *(Workbook pages 70–71 / Day 5 pages 2–3)*`) reduced to just the Day-chapter half.
  4. `welcome.qmd:111` footnote rewritten to describe the site's in-page text-input model rather than the printed Workbook B1–B4.
- **Where** — See above. One sweep landing across day chapters, appendix, and the front-matter welcome page.
- **Source reference** — Neave's original course materials treat the Workbook as the reader's writing surface and use Workbook page numbers as a parallel reference system alongside Day-chapter page numbers.
- **Why** — The printed Workbook no longer exists as a separate artefact in this delivery; leaving the cross-references in place would send readers looking for something that isn't there. The Day-chapter page numbers carry the full navigation intent on their own.
- **Decided in** — [#185 decision comment](https://github.com/lddurbin/twelve_days_to_deming/issues/185#issuecomment-4286006129) (D1/D2).
- **Landed in** — PR [#214](https://github.com/lddurbin/twelve_days_to_deming/pull/214) (closes #209, #210).
- **Related** — [#213](https://github.com/lddurbin/twelve_days_to_deming/issues/213) tracks the still-pending decision on inline `[WB NNN]` cross-reference suffixes; [#212](https://github.com/lddurbin/twelve_days_to_deming/issues/212) covers the `index.qmd` front-matter Workbook prose still to be addressed.

## 2026-04-21 — Remove inline "see Workbook p. N" page-reference call-outs

- **What** — Delete the `.workbook_callout` divs and their inline "see Workbook p. N" page-reference anchors throughout day chapters. Remove the associated CSS class and any manifest fields that validated their presence.
- **Where** — All `content/days/day-*/` chapters that previously carried `.workbook_callout` divs.
- **Source reference** — Neave's original materials include inline cross-references pointing readers at specific pages of the printed Workbook for response-capture (writing answers, notes, reflections).
- **Why** — The site captures reader responses through embedded text inputs and a notes-download feature, so page references to a printed Workbook were dead links in the new delivery model. The class name and manifest field were coupled to the div and removed alongside it.
- **Decided in** — [#185 decision comment](https://github.com/lddurbin/twelve_days_to_deming/issues/185#issuecomment-4286006129) (D1/D3).
- **Landed in** — PRs [#196](https://github.com/lddurbin/twelve_days_to_deming/pull/196), [#197](https://github.com/lddurbin/twelve_days_to_deming/pull/197), [#202](https://github.com/lddurbin/twelve_days_to_deming/pull/202); commits `2198ed3`, `0cba98d`, `1b6ea4a`, `6375e17`.
